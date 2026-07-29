import { newId } from '../lib/ids.js';
import { desiredEventForTask } from '../lib/mirror.js';
import { googleClientFor, getFreshAccessToken } from '../db/calendar.js';

/**
 * One mirror pass for one task (OPH-072/073): reconcile the task's CURRENT
 * state against every active Google account of its workspace. Idempotent —
 * running it twice converges; state lives in `calendar_event_links`
 * (ADR-0003: the mapping table is the source of truth, extended properties
 * are the recovery path).
 */
export async function runMirrorJob(app, { taskId }) {
  const task = await app.db('tasks').where({ id: taskId }).first();
  if (!task) return;

  const accounts = await app
    .db('calendar_accounts')
    .where({ workspace_id: task.workspace_id, provider: 'google', status: 'active' })
    .whereNull('deleted_at')
    .whereNotNull('default_calendar_id')
    .select();

  for (const account of accounts) {
    await mirrorTaskToAccount(app, account, task);
  }
}

async function mirrorTaskToAccount(app, account, task) {
  const desired = desiredEventForTask(task);
  const link = await app
    .db('calendar_event_links')
    .where({ task_id: task.id, calendar_account_id: account.id })
    .first();
  if (!desired && !link) return;

  const google = googleClientFor(app);
  const accessToken = await getFreshAccessToken(app, account);
  const calendarId = link?.provider_calendar_id ?? account.default_calendar_id;

  if (!desired) {
    // A provider-deleted tombstone (OPH-076) is not ours to clean up: the user
    // removed the event themselves, the flagged row records why we stopped
    // mirroring, and there is nothing left to delete. Re-enabling the mirror
    // recreates through the 404 path below.
    if (link.conflict_status === 'provider_deleted_local_exists') return;

    // The task no longer earns an event: remove it (tolerate a remote delete).
    try {
      await google.deleteEvent(accessToken, calendarId, link.provider_event_id);
    } catch (err) {
      if (err?.status !== 404 && err?.status !== 410) throw err;
    }
    await app.db('calendar_event_links').where({ id: link.id }).delete();
    return;
  }

  if (link) {
    try {
      const updated = await google.patchEvent(
        accessToken,
        calendarId,
        link.provider_event_id,
        desired,
      );
      await app
        .db('calendar_event_links')
        .where({ id: link.id })
        .update({
          // The etag we just caused is what tells the inbound worker this
          // change is our own echo and not a user edit (OPH-076).
          etag: updated?.etag ?? null,
          last_provider_updated_at: updated?.updated ? new Date(updated.updated) : null,
          last_local_updated_at: new Date(task.updated_at),
          conflict_status: 'none',
          updated_at: new Date(),
        });
      return;
    } catch (err) {
      if (err?.status !== 404 && err?.status !== 410) throw err;
      // Deleted on Google's side — outbound v1 recreates; two-way conflict
      // policy arrives with OPH-076.
      await app.db('calendar_event_links').where({ id: link.id }).delete();
    }
  }

  // No (usable) link. Re-link before creating: an event carrying our task id
  // may already exist (previous crash, lost link row) — OPH-073.
  const existing = await google.findEventsByTaskId(
    accessToken,
    account.default_calendar_id,
    task.id,
  );
  const match = existing?.items?.[0];
  const event = match
    ? await google.patchEvent(accessToken, account.default_calendar_id, match.id, desired)
    : await google.insertEvent(accessToken, account.default_calendar_id, desired);

  await app.db('calendar_event_links').insert({
    id: newId(),
    task_id: task.id,
    calendar_account_id: account.id,
    provider: 'google',
    provider_calendar_id: account.default_calendar_id,
    provider_event_id: event.id,
    provider_event_uid: event.iCalUID ?? null,
    etag: event.etag ?? null,
    last_provider_updated_at: event.updated ? new Date(event.updated) : null,
    last_local_updated_at: new Date(task.updated_at),
    sync_direction: 'both',
    conflict_status: 'none',
  });
}

/** The backfill window (ADR-0021 §4): −30 days → +12 months. */
export const BACKFILL_BACK_DAYS = 30;
export const BACKFILL_FORWARD_DAYS = 365;

/**
 * Backfill sweep (§7.2 step 4, outbound half): enqueue a mirror pass for every
 * task of the workspace inside the window — used right after an account
 * connects or its default calendar changes.
 *
 * Round 12 removed the `calendar_mirror_enabled: true` filter, because there is
 * no opt-in left to filter on (ADR-0021 §1). What replaces it is a WINDOW, not
 * "everything": an unbounded backfill on a large workspace is tens of thousands
 * of API calls for events nobody will scroll back to, and +12 months is where
 * recurrence stops producing rows anyway. Tasks are matched on any of their
 * dates — a task dragged in the calendar (`scheduled_start_at`) belongs to the
 * window it was dragged into, not to the day it was created.
 */
export async function enqueueWorkspaceMirrorSweep(app, workspaceId, now = new Date()) {
  const from = new Date(now.getTime() - BACKFILL_BACK_DAYS * 86400000);
  const to = new Date(now.getTime() + BACKFILL_FORWARD_DAYS * 86400000);
  const tasks = await app
    .db('tasks')
    .where({ workspace_id: workspaceId })
    .whereNull('deleted_at')
    .whereNull('calendar_mirror_suppressed_at')
    .where((q) =>
      q
        .whereBetween('due_at', [from, to])
        .orWhereBetween('scheduled_start_at', [from, to])
        .orWhere((inner) =>
          inner
            .whereNull('due_at')
            .whereNull('scheduled_start_at')
            .whereBetween('created_at', [from, to]),
        ),
    )
    .select('id');
  for (const task of tasks) {
    app.mirror.enqueue({ workspaceId, taskId: task.id });
  }
  app.log?.info?.({ workspaceId, tasks: tasks.length }, 'calendar backfill queued');
  return tasks.length;
}
