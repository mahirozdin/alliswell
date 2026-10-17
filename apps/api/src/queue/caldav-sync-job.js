import { CaldavError } from '../lib/caldav/client.js';
import { expandInstances, externalIdFor, parseResource } from '../lib/caldav/ical.js';
import { deriveExternalEvent, EXTERNAL_EVENT_WINDOW } from '../lib/external-events.js';
import { recordSyncWrite } from '../db/sync.js';
import { caldavClientForAccount, caldavUrl, markCaldavReauth } from '../db/calendar.js';
import { CONFLICT } from '../lib/inbound.js';
import { applyExternalEvent, applyProviderEvent } from './calendar-sync-job.js';
import { caldavRemote, ownerTimeZone } from './caldav-mirror.js';

/**
 * The INBOUND half of the CalDAV connector (OPH-380, CALDAV.md §4.2,
 * ADR-0059): RFC 6578 sync-collection → calendar-multiget → the same
 * reconcile Google's feed goes through (`applyProviderEvent`, ADR-0007) for
 * our events, and the same display cache (`applyExternalEvent`, ADR-0008) for
 * the user's own.
 *
 * - **Echo suppression costs nothing**: a changed member whose etag equals the
 *   link's is our own write coming back — it is never even fetched.
 * - **Deleted members** answer 404 in the sync report: the CalDAV spelling of
 *   Google's `status: cancelled`.
 * - **A rejected sync-token** is matched on the DAV precondition
 *   (`valid-sync-token`) or on ANY 4xx to a non-empty token — never on one
 *   status code: RFC 6578 prescribes none, and Radicale answers 403 where
 *   Google answers 410 (CALDAV.md §4.2). The cure is the same: resync from an
 *   empty token, and every resource reconciles itself on the way through.
 *
 * There is no push in CalDAV: the calendar sweep polls every active account
 * (`sweepCalendarAccounts`), and that poll IS the notification.
 */

const isTokenRejection = (err, token) =>
  err instanceof CaldavError &&
  err.code === 'CALDAV_REQUEST_FAILED' &&
  (err.davError === 'valid-sync-token' ||
    (Boolean(token) && err.status >= 400 && err.status < 500 && err.status !== 404));

export async function runCaldavSyncJob(app, { accountId }) {
  if (!app.config.caldav?.enabled) return;
  const account = await app
    .db('calendar_accounts')
    .where({ id: accountId, provider: 'apple_caldav', status: 'active' })
    .whereNull('deleted_at')
    .first();
  if (!account?.default_calendar_id) return;

  try {
    const client = caldavClientForAccount(app, account);
    await syncAccount(app, account, client);
  } catch (err) {
    if (err?.code === 'CALENDAR_ACCOUNT_REAUTH_REQUIRED' || err?.code === 'CALDAV_AUTH_FAILED') {
      if (err.code === 'CALDAV_AUTH_FAILED') await markCaldavReauth(app, account);
      app.log.info({ accountId: account.id }, 'caldav account needs reconnect — skipping sync');
      return;
    }
    // The code, never the message: a URL in it would name the user's server.
    await app
      .db('calendar_accounts')
      .where({ id: account.id })
      .update({
        last_error: `inbound sync failed: ${err?.code ?? 'error'}`,
        updated_at: new Date(),
      });
    throw err;
  }
}

async function syncAccount(app, account, client) {
  const calendarPath = account.default_calendar_id;
  const calendarUrl = caldavUrl(account, calendarPath);

  // Links are read BEFORE the report: a link the mirror writes while the
  // report is in flight belongs to an event the listing may not name yet, and
  // must not be mistaken for one the user deleted (full resync below).
  const links = await app
    .db('calendar_event_links')
    .where({ calendar_account_id: account.id })
    .select();
  const linkByHref = new Map(links.map((link) => [link.provider_event_id, link]));

  let fullResync = !account.sync_token;
  let report;
  try {
    report = await client.syncCollection(calendarUrl, account.sync_token);
  } catch (err) {
    if (!isTokenRejection(err, account.sync_token)) throw err;
    app.log.info({ accountId: account.id }, 'caldav sync token rejected — full resync');
    await app.db('calendar_accounts').where({ id: account.id }).update({ sync_token: null });
    report = await client.syncCollection(calendarUrl, null);
    fullResync = true;
  }

  const timeZone = await ownerTimeZone(app, account);

  // Removed members first: a resource deleted and re-created in one window
  // shows up only as changed (the client already folded that).
  const removed = new Set(report.removed);
  if (fullResync) {
    // A full listing names everything that exists, so whatever we know about
    // in this calendar and it did not name is gone.
    const listed = new Set(report.changed.map((member) => member.href));
    for (const link of links) {
      if (link.provider_calendar_id === calendarPath && !listed.has(link.provider_event_id)) {
        removed.add(link.provider_event_id);
      }
    }
    await dropUnlistedExternals(app, account, listed);
  }
  for (const href of removed) {
    const link = linkByHref.get(href);
    // A tombstone already records that delete; a server that reports the same
    // 404 member again (Radicale does, after a resync) must not erase it.
    if (link && link.conflict_status !== CONFLICT.PROVIDER_DELETED) {
      await applyProviderEvent(app, {
        account,
        event: { id: href, status: 'cancelled', etag: null },
        remote: caldavRemote(account, client, null),
      });
    }
    await dropExternals(app, account, externalIdFor(href), { includeBase: true });
  }

  // Changed members: skip our own echoes without fetching them.
  const toFetch = report.changed
    .filter((member) => {
      const link = linkByHref.get(member.href);
      return !(link?.etag && member.etag && link.etag === member.etag);
    })
    .map((member) => member.href);

  const fetched = toFetch.length > 0 ? await client.multiget(calendarUrl, toFetch) : [];
  const now = new Date();
  for (const resource of fetched) {
    const link = linkByHref.get(resource.href);
    const parsed = parseResource(resource.ics, {
      href: resource.href,
      etag: resource.etag,
      timeZone,
    });
    if (!parsed) {
      if (link) {
        // Our event, but nothing we can read any more: flag it, don't guess.
        await app
          .db('calendar_event_links')
          .where({ id: link.id })
          .update({
            etag: resource.etag ?? null,
            conflict_status: CONFLICT.TIME,
            updated_at: new Date(),
          });
      }
      continue;
    }
    if (link || parsed.taskId) {
      parsed.master.iCalUID = parsed.uid;
      await applyProviderEvent(app, {
        account,
        event: parsed.master,
        remote: caldavRemote(account, client, resource.ics),
      });
      continue;
    }
    await storeForeign(app, { account, parsed, timeZone, now });
  }

  await app
    .db('calendar_accounts')
    .where({ id: account.id })
    .update({
      sync_token: report.token ?? null,
      last_synced_at: new Date(),
      last_error: null,
      updated_at: new Date(),
    });
}

/** A foreign resource → cached events: itself, or its instances in the window. */
async function storeForeign(app, { account, parsed, timeZone, now }) {
  const base = externalIdFor(parsed.master.id);
  const target = { account, provider: 'apple_caldav', calendarId: account.default_calendar_id };

  if (!parsed.recurring) {
    const event = { ...parsed.master, id: base };
    const outcome = deriveExternalEvent(event, { timeZone, now });
    // A series that stopped repeating leaves its instances behind otherwise.
    await dropExternals(app, account, base, { includeBase: false });
    if (outcome.action === 'skip') return;
    await applyExternalEvent(app, { ...target, event, outcome });
    return;
  }

  const from = new Date(now.getTime() - EXTERNAL_EVENT_WINDOW.backDays * 86400_000);
  const to = new Date(now.getTime() + EXTERNAL_EVENT_WINDOW.forwardDays * 86400_000);
  let instances = [];
  try {
    instances = expandInstances(parsed, { from, to, timeZone });
  } catch (err) {
    app.log.warn({ err: err.message }, 'caldav recurrence expansion failed — skipping series');
  }
  const kept = new Set();
  for (const event of instances) {
    const outcome = deriveExternalEvent(event, { timeZone, now });
    if (outcome.action !== 'store') continue;
    kept.add(event.id);
    await applyExternalEvent(app, { ...target, event, outcome });
  }
  // Instances the series no longer produces (an EXDATE, a shortened RRULE)
  // and the plain row it had before it started repeating.
  await dropExternals(app, account, base, { includeBase: true, keep: kept });
}

/** Tombstones cached rows of one resource (`<base>` and `<base>#…`). */
async function dropExternals(app, account, base, { includeBase, keep = new Set() }) {
  const rows = await app
    .db('calendar_external_events')
    .where({ calendar_account_id: account.id })
    .where('provider_event_id', 'like', `${base}%`)
    .whereNull('deleted_at')
    .select();
  for (const row of rows) {
    const isBase = row.provider_event_id === base;
    if (isBase && !includeBase) continue;
    if (!isBase && !row.provider_event_id.startsWith(`${base}#`)) continue;
    if (keep.has(row.provider_event_id)) continue;
    await tombstoneExternal(app, account, row);
  }
}

/** Full resync: rows of resources the listing no longer names are gone. */
async function dropUnlistedExternals(app, account, listedHrefs) {
  const listed = new Set([...listedHrefs].map((href) => externalIdFor(href)));
  const rows = await app
    .db('calendar_external_events')
    .where({ calendar_account_id: account.id, provider_calendar_id: account.default_calendar_id })
    .whereNull('deleted_at')
    .select();
  for (const row of rows) {
    if (!listed.has(row.provider_event_id.split('#')[0])) {
      await tombstoneExternal(app, account, row);
    }
  }
}

async function tombstoneExternal(app, account, row) {
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: account.workspace_id,
      entityType: 'external_event',
      entityId: row.id,
      operation: 'delete',
    });
    await trx('calendar_external_events')
      .where({ id: row.id })
      .update({ deleted_at: new Date(), revision, updated_at: new Date() });
  });
}
