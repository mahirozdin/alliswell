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
          etag: updated?.etag ?? null,
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
    last_local_updated_at: new Date(task.updated_at),
    sync_direction: 'both',
    conflict_status: 'none',
  });
}

/**
 * Backfill sweep (§7.2 step 4, outbound half): enqueue a mirror pass for
 * every mirror-enabled task of the workspace — used right after an account
 * connects or its default calendar changes.
 */
export async function enqueueWorkspaceMirrorSweep(app, workspaceId) {
  const tasks = await app
    .db('tasks')
    .where({ workspace_id: workspaceId, calendar_mirror_enabled: true })
    .whereNull('deleted_at')
    .select('id');
  for (const task of tasks) {
    app.mirror.enqueue({ workspaceId, taskId: task.id });
  }
  return tasks.length;
}
