import crypto from 'node:crypto';
import { newId } from '../lib/ids.js';
import { recordSyncWrite } from '../db/sync.js';
import { reconcileTaskReminder } from '../db/reminders.js';
import { desiredEventForTask } from '../lib/mirror.js';
import { reconcileProviderEvent, CONFLICT } from '../lib/inbound.js';
import { deriveExternalEvent } from '../lib/external-events.js';
import { newChannelToken, hashChannelToken } from '../lib/tokens.js';
import { googleClientFor, getFreshAccessToken } from '../db/calendar.js';

/**
 * The INBOUND half of BLUEPRINT §7.2 (OPH-074/075/076): keep the push channel
 * alive (step 6), consume the changes it announces (step 8), match them to
 * tasks (step 9) and apply them (step 10). Policy lives in `lib/inbound.js`
 * — this file only executes it.
 */

/** Renew a day before Google drops the channel; a lapsed channel syncs nothing. */
const WATCH_RENEW_SLACK_MS = 24 * 60 * 60 * 1000;
/** 250 events/page — a guard against paginating forever on an API hiccup. */
const MAX_PAGES = 50;

/**
 * The two feeds an account syncs (ADR-0008 §3). Same calendar, opposite
 * `singleEvents`, therefore separate cursors — one Google sync token is tied to
 * the parameters it was issued with:
 *
 * - `mirror`   — recurrence MASTERS visible, so OPH-076 can spot a user turning
 *                our block into a series (`time_conflict`).
 * - `external` — recurring events expanded into INSTANCES, which is the only
 *                shape a calendar grid can draw.
 */
const FEEDS = {
  mirror: { cursorColumn: 'sync_token', singleEvents: false },
  external: { cursorColumn: 'external_sync_token', singleEvents: true },
};

async function loadSyncableAccount(app, accountId) {
  const account = await app
    .db('calendar_accounts')
    .where({ id: accountId, provider: 'google', status: 'active' })
    .whereNull('deleted_at')
    .first();
  // No calendar chosen yet → nothing to watch and nothing to sync (OPH-071).
  return account?.default_calendar_id ? account : null;
}

// ── Step 6: push channel lifecycle ─────────────────────────────────────────

/**
 * (Re)opens the push channel for an account's calendar. Idempotent by design:
 * it always mints a NEW channel and retires the previous one, so a half-failed
 * renewal costs a duplicate notification, never a blind spot.
 */
export async function runWatchJob(app, { accountId }) {
  const address = app.config.calendar.webhookUrl;
  if (!address) return; // no public webhook → the sweep polls instead

  const account = await loadSyncableAccount(app, accountId);
  if (!account) return;

  const accessToken = await getFreshAccessTokenOrSkip(app, account);
  if (!accessToken) return;

  const google = googleClientFor(app);
  const channelId = crypto.randomUUID();
  const token = newChannelToken();
  const channel = await google.watchEvents(accessToken, account.default_calendar_id, {
    channelId,
    address,
    token,
    ttlSeconds: app.config.calendar.watchTtlSec,
  });

  const previous = {
    channelId: account.webhook_channel_id,
    resourceId: account.webhook_resource_id,
  };

  await app
    .db('calendar_accounts')
    .where({ id: account.id })
    .update({
      webhook_channel_id: channelId,
      webhook_channel_token_hash: hashChannelToken(token, app.config.auth.refreshSecret),
      webhook_resource_id: channel?.resourceId ?? null,
      // Google decides the real lifetime; ours was only a request.
      webhook_expires_at: channel?.expiration ? new Date(Number(channel.expiration)) : null,
      updated_at: new Date(),
    });

  // Order matters: the new channel is live BEFORE the old one dies, so no
  // change can slip through the gap between them. Overlap only duplicates
  // notifications, and the sync is idempotent.
  if (previous.channelId && previous.resourceId) {
    await google.stopChannel(accessToken, previous);
  }
}

// ── Step 8: incremental sync ───────────────────────────────────────────────

/**
 * Consumes everything that changed on the account's calendar since the last
 * pass and reconciles each event against its task.
 *
 * Errors are deliberately LOUD (they bubble → BullMQ retries with backoff →
 * `last_error` shows up in the account status endpoint). Events we merely
 * cannot interpret never throw — `lib/inbound.js` answers `time_conflict` for
 * those — so a throw here really does mean infrastructure, which is what
 * retrying is for.
 */
export async function runInboundSyncJob(app, { accountId }) {
  const account = await loadSyncableAccount(app, accountId);
  if (!account) return;

  const accessToken = await getFreshAccessTokenOrSkip(app, account);
  if (!accessToken) return;

  // Captured BEFORE the fetch: a webhook landing mid-sync must not have its
  // announcement cleared by this pass (compare-and-clear below).
  const dirtyMarker = account.sync_dirty_at ?? null;
  const google = googleClientFor(app);

  try {
    // Feed 1 — our own events: task ⇄ event reconcile (ADR-0007).
    const mirror = await fetchFeed(app, google, account, accessToken, FEEDS.mirror);
    for (const event of mirror.events) {
      await applyProviderEvent(app, { account, event, google, accessToken });
    }

    // Feed 2 — the user's own events, cached for display (ADR-0008). Same
    // trigger, same pass; one extra request, not one per event.
    const external = await fetchFeed(app, google, account, accessToken, FEEDS.external);
    await applyExternalEvents(app, { account, events: external.events });

    const patch = { last_synced_at: new Date(), last_error: null, updated_at: new Date() };
    // Only advance a cursor when Google actually handed one over — a missing
    // token must not silently reset us to full syncs forever.
    if (mirror.nextSyncToken) patch.sync_token = mirror.nextSyncToken;
    if (external.nextSyncToken) patch.external_sync_token = external.nextSyncToken;
    await app.db('calendar_accounts').where({ id: account.id }).update(patch);

    if (dirtyMarker) {
      const cleared = await app
        .db('calendar_accounts')
        .where({ id: account.id, sync_dirty_at: dirtyMarker })
        .update({ sync_dirty_at: null });
      // Not cleared → a newer webhook arrived while we were fetching. Leave the
      // marker standing and give what it announced its own pass.
      if (!cleared) app.calendarSync.enqueueSync(account.id);
    }
  } catch (err) {
    await app
      .db('calendar_accounts')
      .where({ id: account.id })
      .update({ last_error: `inbound sync failed: ${err.message}`, updated_at: new Date() });
    throw err;
  }
}

/** Returns null (instead of throwing) when the account needs reconnecting — it
 *  has already been flipped to `error`, and retries cannot fix consent. */
async function getFreshAccessTokenOrSkip(app, account) {
  try {
    return await getFreshAccessToken(app, account);
  } catch (err) {
    if (err?.code === 'CALENDAR_ACCOUNT_REAUTH_REQUIRED') {
      app.log.info({ accountId: account.id }, 'calendar account needs reconnect — skipping sync');
      return null;
    }
    throw err;
  }
}

async function fetchFeed(app, google, account, accessToken, feed) {
  const collect = async (syncToken) => {
    const events = [];
    let pageToken = null;
    let nextSyncToken = null;
    for (let page = 0; page < MAX_PAGES; page += 1) {
      const res = await google.listEvents(accessToken, account.default_calendar_id, {
        syncToken,
        pageToken,
        singleEvents: feed.singleEvents,
      });
      events.push(...(res?.items ?? []));
      // Google puts nextSyncToken on the LAST page only.
      nextSyncToken = res?.nextSyncToken ?? nextSyncToken;
      pageToken = res?.nextPageToken ?? null;
      if (!pageToken) break;
    }
    return { events, nextSyncToken };
  };

  const cursor = account[feed.cursorColumn];
  if (!cursor) return collect(null);
  try {
    return await collect(cursor);
  } catch (err) {
    if (err?.status !== 410) throw err;
    // Google invalidated the token (expiry, ACL change). A full resync is the
    // only cure — and it needs no local wipe: both feeds are keyed by event id,
    // so every event reconciles itself on the way through.
    app.log.info(
      { accountId: account.id, cursor: feed.cursorColumn },
      'google sync token expired — full resync',
    );
    await app
      .db('calendar_accounts')
      .where({ id: account.id })
      .update({ [feed.cursorColumn]: null });
    return collect(null);
  }
}

// ── Steps 9-10: match to a task, apply the decision ────────────────────────

async function applyProviderEvent(app, { account, event, google, accessToken }) {
  const link = await app
    .db('calendar_event_links')
    .where({ calendar_account_id: account.id, provider_event_id: event.id })
    .first();

  // Mapping table first, extended property second (ADR-0003): the property is
  // the recovery path when the link row is gone.
  const taskId = link?.task_id ?? event.extendedProperties?.private?.alliswell_task_id ?? null;
  // Deliberately NOT filtering deleted_at — a deleted task still has an
  // opinion about its event (namely: remove it).
  const task = taskId
    ? await app.db('tasks').where({ id: taskId, workspace_id: account.workspace_id }).first()
    : null;

  let alreadyLinked = false;
  if (!link && task) {
    const other = await app
      .db('calendar_event_links')
      .where({ task_id: task.id, calendar_account_id: account.id })
      .first();
    alreadyLinked = Boolean(other);
  }

  const outcome = reconcileProviderEvent({ event, link, task, alreadyLinked });
  if (outcome.decision !== 'ignore') {
    app.log.debug(
      { eventId: event.id, decision: outcome.decision, reason: outcome.reason },
      'inbound reconcile',
    );
  }

  const observed = {
    etag: event.etag ?? null,
    last_provider_updated_at: event.updated ? new Date(event.updated) : null,
    updated_at: new Date(),
  };
  const flagged = outcome.conflictStatus ? { conflict_status: outcome.conflictStatus } : {};
  const updateLink = (patch) => app.db('calendar_event_links').where({ id: link.id }).update(patch);

  switch (outcome.decision) {
    case 'ignore':
      return;

    case 'drop-link':
      // Both sides agree the event is gone — the mapping has nothing left to map.
      await app.db('calendar_event_links').where({ id: link.id }).delete();
      return;

    case 'touch':
      await updateLink({ ...observed, ...flagged });
      return;

    case 'flag':
      await updateLink({ ...observed, ...flagged });
      return;

    case 'adopt':
      await app.db('calendar_event_links').insert({
        id: newId(),
        task_id: task.id,
        calendar_account_id: account.id,
        provider: 'google',
        provider_calendar_id: account.default_calendar_id,
        provider_event_id: event.id,
        provider_event_uid: event.iCalUID ?? null,
        etag: observed.etag,
        last_provider_updated_at: observed.last_provider_updated_at,
        sync_direction: 'both',
        conflict_status: CONFLICT.NONE,
      });
      // Adopted as-is; the outbound mirror brings its content back in line.
      app.mirror.enqueue({ workspaceId: account.workspace_id, taskId: task.id });
      return;

    case 'remove-remote': {
      const calendarId = link.provider_calendar_id ?? account.default_calendar_id;
      try {
        await google.deleteEvent(accessToken, calendarId, event.id);
      } catch (err) {
        if (err?.status !== 404 && err?.status !== 410) throw err;
      }
      await updateLink({ ...observed, ...flagged });
      return;
    }

    case 'push': {
      // Local won the last-write-wins race — put it back the way the task says.
      const calendarId = link.provider_calendar_id ?? account.default_calendar_id;
      const updated = await google.patchEvent(
        accessToken,
        calendarId,
        event.id,
        desiredEventForTask(task),
      );
      await updateLink({
        etag: updated?.etag ?? null,
        last_provider_updated_at: updated?.updated
          ? new Date(updated.updated)
          : observed.last_provider_updated_at,
        last_local_updated_at: new Date(task.updated_at),
        ...flagged,
        updated_at: new Date(),
      });
      return;
    }

    case 'stop-mirror':
    case 'apply': {
      // Flag BEFORE writing the task: that write announces itself, and the
      // mirror queue may reach this link before the next statement runs. A
      // `provider_deleted_local_exists` tombstone that is not recorded yet
      // looks like an ordinary stale link — and gets deleted.
      await updateLink({ ...observed, ...flagged });
      await writeTaskFromProvider(app, { account, task, patch: outcome.taskPatch });
      const fresh = await app.db('tasks').where({ id: task.id }).first();
      // Record the task's NEW updated_at as reconciled too. Without this the
      // mirror pass our own write triggers would look like a fresh local
      // change on the next notification, and every edit would land as a
      // phantom conflict.
      await updateLink({ last_local_updated_at: new Date(fresh.updated_at) });
      return;
    }

    default:
      throw new Error(`Unhandled inbound decision "${outcome.decision}"`);
  }
}

// ── The user's own events, cached for display (OPH-082, ADR-0008) ──────────

/**
 * The other half of the feed: meetings and appointments AllisWell did not
 * create. We store them so the Calendar and Home views can answer "what does my
 * day look like" offline, and we never write them back.
 */
async function applyExternalEvents(app, { account, events }) {
  if (events.length === 0) return;
  // All-day boundaries are calendar dates, so they need a timezone to become
  // instants. The account's owner is whose day this is.
  const owner = await app.db('users').where({ id: account.user_id }).first();
  const timeZone = owner?.timezone ?? 'Europe/Istanbul';
  const now = new Date();

  for (const event of events) {
    const outcome = deriveExternalEvent(event, { timeZone, now });
    if (outcome.action === 'skip') continue;
    await applyExternalEvent(app, { account, event, outcome });
  }
}

async function applyExternalEvent(app, { account, event, outcome }) {
  const existing = await app
    .db('calendar_external_events')
    .where({ calendar_account_id: account.id, provider_event_id: event.id })
    .first();

  if (outcome.action === 'drop') {
    // Cancelled, or it left the window. Nothing stored → nothing to do (a full
    // resync replays the user's whole history through here).
    if (!existing || existing.deleted_at != null) return;
    await app.db.transaction(async (trx) => {
      const revision = await recordSyncWrite(trx, {
        workspaceId: account.workspace_id,
        entityType: 'external_event',
        entityId: existing.id,
        operation: 'delete',
      });
      await trx('calendar_external_events')
        .where({ id: existing.id })
        .update({ deleted_at: new Date(), revision, updated_at: new Date() });
    });
    return;
  }

  // Unchanged since we last saw it. Skipping keeps a full resync — which
  // replays EVERY event — from burning a revision per meeting and waking every
  // device for nothing.
  if (
    existing &&
    existing.deleted_at == null &&
    existing.etag &&
    existing.etag === outcome.values.etag
  ) {
    return;
  }

  await app.db.transaction(async (trx) => {
    const id = existing?.id ?? newId();
    const revision = await recordSyncWrite(trx, {
      workspaceId: account.workspace_id,
      entityType: 'external_event',
      entityId: id,
      operation: existing ? 'update' : 'create',
    });
    const row = {
      ...outcome.values,
      workspace_id: account.workspace_id,
      calendar_account_id: account.id,
      provider: 'google',
      provider_calendar_id: account.default_calendar_id,
      provider_event_id: event.id,
      revision,
      deleted_at: null, // an event can come back from out-of-window
      updated_at: new Date(),
    };
    if (existing) {
      await trx('calendar_external_events').where({ id: existing.id }).update(row);
    } else {
      await trx('calendar_external_events').insert({ id, ...row });
    }
  });
}

/**
 * A provider change written like any other task write: one transaction, a sync
 * revision so every replica hears about it (§6.2), and the reminder reconciled
 * alongside. Attributed to the user whose calendar spoke.
 */
async function writeTaskFromProvider(app, { account, task, patch }) {
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: account.workspace_id,
      entityType: 'task',
      entityId: task.id,
      operation: 'update',
      changedFields: Object.keys(patch),
    });
    await trx('tasks')
      .where({ id: task.id })
      .update({ ...patch, revision, updated_by: account.user_id, updated_at: new Date() });
    const fresh = await trx('tasks').where({ id: task.id }).first();
    await reconcileTaskReminder(trx, { workspaceId: account.workspace_id, task: fresh });
  });
}

// ── Periodic upkeep ────────────────────────────────────────────────────────

/**
 * One indexed pass over the active accounts (§7.2 steps 6-8):
 *
 * - channels expire and Google never renews them → re-watch before they lapse
 * - a webhook may have landed while the worker was down → dirty accounts sync
 * - no public webhook URL (localhost, NAT, no TLS) → poll instead, so inbound
 *   sync works for every self-hoster rather than only the publicly-reachable
 *   ones. This poll IS the notification for them.
 *
 * Safe to run on every API instance at once: enqueues dedupe per account.
 */
export async function sweepCalendarAccounts(app) {
  const accounts = await app
    .db('calendar_accounts')
    .where({ provider: 'google', status: 'active' })
    .whereNull('deleted_at')
    .whereNotNull('default_calendar_id')
    .select();

  const renewBefore = Date.now() + WATCH_RENEW_SLACK_MS;
  for (const account of accounts) {
    if (app.config.calendar.webhookUrl) {
      const expiresAt = account.webhook_expires_at
        ? new Date(account.webhook_expires_at).getTime()
        : 0;
      if (!account.webhook_channel_id || expiresAt < renewBefore) {
        app.calendarSync.enqueueWatch(account.id);
      }
    }
    if (account.sync_dirty_at || !account.webhook_channel_id) {
      app.calendarSync.enqueueSync(account.id);
    }
  }
  return accounts.length;
}
