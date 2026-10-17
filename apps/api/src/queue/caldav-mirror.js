import { newId } from '../lib/ids.js';
import { desiredBlockForTask } from '../lib/mirror.js';
import {
  hrefForTask,
  matchesBlock,
  mergeTaskIntoIcs,
  parseResource,
  veventForTask,
} from '../lib/caldav/ical.js';
import { CaldavError } from '../lib/caldav/client.js';
import { caldavClientForAccount, caldavUrl, markCaldavReauth } from '../db/calendar.js';
import { applyProviderEvent } from './calendar-sync-job.js';

/**
 * The OUTBOUND half of the CalDAV connector (OPH-380, CALDAV.md §4.3,
 * ADR-0059) — `mirror-job.js`'s Google pass, spoken in CalDAV:
 *
 * - **create**: `PUT If-None-Match: *` at the deterministic href
 *   `<calendar>/alliswell-<taskId>.ics`. A 412 there means the event already
 *   exists (a crash before the link row, a reconnect) — ours is ADOPTED, never
 *   duplicated.
 * - **update**: no PATCH exists, so GET → merge our fields → `PUT If-Match`.
 *   The user's alarms, colour and location survive.
 * - **foreign etag before a write**: the user edited the event and the poll
 *   has not seen it yet. The shared ADR-0007 reconcile runs FIRST, so a drag
 *   in the calendar is applied to the task instead of being overwritten.
 * - **delete**: `DELETE If-Match`; on 412 local is canonical — re-read and
 *   delete anyway.
 *
 * Every write stores the etag it caused: that is echo suppression
 * (LESSONS calendar), and without it every own write looks like a user edit.
 */

const isReauth = (err) =>
  err?.code === 'CALENDAR_ACCOUNT_REAUTH_REQUIRED' || err?.code === 'CALDAV_AUTH_FAILED';

/** The account owner's zone: floating times in their calendar are theirs. */
export async function ownerTimeZone(app, account) {
  const owner = await app.db('users').where({ id: account.user_id }).first();
  return owner?.timezone ?? 'Europe/Istanbul';
}

/**
 * The CalDAV operations the shared reconcile (`applyProviderEvent`) executes,
 * bound to one fetched resource (`ics`) — a push merges into what the user's
 * calendar holds rather than rebuilding it.
 */
export function caldavRemote(account, client, ics) {
  const urlOf = (event) => caldavUrl(account, event.id);
  return {
    provider: 'apple_caldav',
    calendarId: account.default_calendar_id,
    eventUid: (event) => event.iCalUID ?? null,
    deleteEvent: async (event) => {
      await deleteCanonically(client, urlOf(event), event.etag);
    },
    pushTask: async (task, event) => {
      const block = desiredBlockForTask(task);
      if (!block) return null;
      const body = (ics && mergeTaskIntoIcs(ics, block)) ?? veventForTask(block);
      const etag = await client.put(urlOf(event), body, { ifMatch: event.etag ?? '*' });
      return { etag, updated: new Date().toISOString() };
    },
  };
}

/** DELETE If-Match; a 412 means it changed since — local wins, delete that. */
async function deleteCanonically(client, url, etag) {
  try {
    await client.delete(url, etag ?? null);
  } catch (err) {
    if (err?.status !== 412) throw err;
    const fresh = await client.get(url);
    if (fresh) await client.delete(url, fresh.etag ?? null);
  }
}

export async function mirrorTaskToCaldav(app, account, task) {
  const block = desiredBlockForTask(task);
  const link = await app
    .db('calendar_event_links')
    .where({ task_id: task.id, calendar_account_id: account.id })
    .first();
  if (!block && !link) return;

  try {
    const client = caldavClientForAccount(app, account);
    await mirrorWith(app, { account, task, block, link, client });
  } catch (err) {
    if (!isReauth(err)) throw err;
    // Retrying cannot fix a revoked password: flag it once and stop.
    if (err.code === 'CALDAV_AUTH_FAILED') await markCaldavReauth(app, account);
    app.log.info({ accountId: account.id }, 'caldav account needs reconnect — skipping mirror');
  }
}

async function mirrorWith(app, { account, task, block, link, client }) {
  const links = () => app.db('calendar_event_links');

  if (!block) {
    // A provider-deleted tombstone (ADR-0007) is not ours to clean up: the
    // user removed the event, and the flagged row records why we stopped.
    if (link.conflict_status === 'provider_deleted_local_exists') return;
    await deleteCanonically(client, caldavUrl(account, link.provider_event_id), link.etag);
    await links().where({ id: link.id }).delete();
    return;
  }

  if (link) {
    const url = caldavUrl(account, link.provider_event_id);
    const current = await client.get(url);
    if (!current) {
      // Gone on the server while the task still wants it: the user deleted it
      // and the poll has not told us yet. Same answer the poll's 404 gives —
      // keep the task, stop mirroring it (ADR-0007 tombstone) — rather than
      // resurrecting an event the user just removed.
      await applyProviderEvent(app, {
        account,
        event: { id: link.provider_event_id, status: 'cancelled', etag: null },
        remote: caldavRemote(account, client, null),
      });
      return;
    }
    if (current.etag && current.etag !== link.etag) {
      const timeZone = await ownerTimeZone(app, account);
      const parsed = parseResource(current.ics, {
        href: link.provider_event_id,
        etag: current.etag,
        timeZone,
      });
      if (parsed) {
        parsed.master.iCalUID = parsed.uid;
        const decision = await applyProviderEvent(app, {
          account,
          event: parsed.master,
          remote: caldavRemote(account, client, current.ics),
        });
        // Anything but `touch` has already written (the task, the event, or
        // the link) and re-enqueued what follows; this pass is done.
        if (decision !== 'touch') return;
        const freshTask = await app.db('tasks').where({ id: task.id }).first();
        const freshLink = await links().where({ id: link.id }).first();
        const freshBlock = desiredBlockForTask(freshTask);
        if (!freshLink || !freshBlock) return;
        await writeBlock(app, {
          link: freshLink,
          task: freshTask,
          block: freshBlock,
          client,
          url,
          current,
        });
        return;
      }
    }
    await writeBlock(app, { link, task, block, client, url, current });
    return;
  }

  // No (usable) link: create at the deterministic href — or adopt what is there.
  const href = hrefForTask(account.default_calendar_id, task.id);
  const url = caldavUrl(account, href);
  let etag;
  try {
    etag = await client.put(url, veventForTask(block), { ifNoneMatch: '*' });
  } catch (err) {
    if (err?.status !== 412) throw err;
    const existing = await client.get(url);
    const parsed = existing
      ? parseResource(existing.ics, { href, etag: existing.etag, timeZone: 'UTC' })
      : null;
    if (!existing || parsed?.taskId !== task.id) {
      throw new CaldavError('Another resource already sits at the task’s href', {
        status: 412,
        code: 'CALDAV_HREF_TAKEN',
      });
    }
    const merged = mergeTaskIntoIcs(existing.ics, block) ?? veventForTask(block);
    etag = await client.put(url, merged, { ifMatch: existing.etag ?? '*' });
  }

  const row = {
    task_id: task.id,
    calendar_account_id: account.id,
    provider: 'apple_caldav',
    provider_calendar_id: account.default_calendar_id,
    provider_event_id: href,
    provider_event_uid: task.id,
    etag: etag ?? null,
    last_provider_updated_at: new Date(),
    last_local_updated_at: new Date(task.updated_at),
    sync_direction: 'both',
    conflict_status: 'none',
  };
  try {
    await links().insert({ id: newId(), ...row });
  } catch (err) {
    if (err?.code !== 'ER_DUP_ENTRY') throw err;
    // The inbound poll adopted it between our PUT and here — same row, update.
    await links()
      .where({ calendar_account_id: account.id, provider_event_id: href })
      .update({ ...row, updated_at: new Date() });
  }
}

/** Merge + `PUT If-Match`, or — when nothing we map changed — bookkeeping only. */
async function writeBlock(app, { link, task, block, client, url, current }) {
  const timeZone = 'UTC'; // only used to read back OUR fields, which are UTC
  const parsed = parseResource(current.ics, {
    href: link.provider_event_id,
    etag: current.etag,
    timeZone,
  });
  const linkPatch = {
    last_local_updated_at: new Date(task.updated_at),
    updated_at: new Date(),
  };
  if (parsed && matchesBlock(parsed, block)) {
    await app
      .db('calendar_event_links')
      .where({ id: link.id })
      .update({ ...linkPatch, etag: current.etag ?? link.etag });
    return;
  }
  const body = mergeTaskIntoIcs(current.ics, block) ?? veventForTask(block);
  // A 412 here = the user wrote in the gap since our GET. Throwing lets the
  // queue retry the whole pass, which then reconciles their edit first.
  const etag = await client.put(url, body, { ifMatch: current.etag ?? link.etag ?? '*' });
  await app
    .db('calendar_event_links')
    .where({ id: link.id })
    .update({
      ...linkPatch,
      etag: etag ?? null,
      last_provider_updated_at: new Date(),
      conflict_status: 'none',
    });
}
