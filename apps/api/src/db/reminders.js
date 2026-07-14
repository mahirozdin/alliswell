import { newId } from '../lib/ids.js';
import { recordSyncWrite } from './sync.js';

/** Statuses that still mean "this alarm will (or may) fire". */
const ACTIVE_STATUSES = ['scheduled', 'snoozed', 'delivered'];

/** Task states in which no alarm must fire. */
const SILENCED_TASK_STATUSES = new Set(['completed', 'cancelled', 'archived']);

function sameInstant(a, b) {
  const [ta, tb] = [a && new Date(a).getTime(), b && new Date(b).getTime()];
  return ta === tb;
}

/**
 * Keeps the task's reminder row in lockstep with the task (OPH-034, BLUEPRINT
 * §4.9). Call inside the SAME transaction as the task write, with the
 * post-write task row:
 *
 * - task wants an alarm (remind_at set, task live and not completed/cancelled/
 *   archived) → upsert the active reminder, re-armed to `scheduled`
 * - task no longer wants one → terminal-ize the active reminder
 *   (`completed` when the task was completed, else `cancelled`)
 *
 * No-ops when the reminder already matches — a title-only patch must not burn
 * a reminder revision. Reminders are sync entities: every real change records
 * its own sync revision.
 */
export async function reconcileTaskReminder(trx, { workspaceId, task }) {
  const active = await trx('reminders')
    .where({ task_id: task.id })
    .whereNull('deleted_at')
    .whereIn('status', ACTIVE_STATUSES)
    .orderBy('created_at', 'desc')
    .first();

  const wantsReminder =
    task.remind_at != null && task.deleted_at == null && !SILENCED_TASK_STATUSES.has(task.status);

  if (!wantsReminder) {
    if (!active) return;
    const status = task.status === 'completed' ? 'completed' : 'cancelled';
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'reminder',
      entityId: active.id,
      operation: 'update',
      changedFields: ['status'],
    });
    await trx('reminders')
      .where({ id: active.id })
      .update({ status, revision, updated_at: new Date() });
    return;
  }

  const desired = {
    remind_at: new Date(task.remind_at),
    timezone: task.timezone,
    alarm_level: task.is_urgent ? 'urgent' : 'normal',
    requires_acknowledgement: Boolean(task.requires_acknowledgement),
    repeat_rule: task.repeat_rule ?? null,
    status: 'scheduled',
    snoozed_until: null,
    delivered_at: null,
    acknowledged_at: null,
  };

  if (active) {
    // A moved remind_at re-arms the alarm completely (clears snooze/delivery
    // state). Anything else only mirrors task fields and MUST preserve an
    // in-flight snooze (OPH-035) — a title patch must not wake an alarm up.
    const remindMoved = !sameInstant(active.remind_at, desired.remind_at);
    const patch = remindMoved
      ? desired
      : {
          timezone: desired.timezone,
          alarm_level: desired.alarm_level,
          requires_acknowledgement: desired.requires_acknowledgement,
          repeat_rule: desired.repeat_rule,
        };

    const unchanged =
      !remindMoved &&
      active.timezone === patch.timezone &&
      active.alarm_level === patch.alarm_level &&
      Boolean(active.requires_acknowledgement) === patch.requires_acknowledgement &&
      (active.repeat_rule ?? null) === patch.repeat_rule;
    if (unchanged) return;

    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'reminder',
      entityId: active.id,
      operation: 'update',
      changedFields: Object.keys(patch),
    });
    await trx('reminders')
      .where({ id: active.id })
      .update({ ...patch, revision, updated_at: new Date() });
    return;
  }

  const id = newId();
  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'reminder',
    entityId: id,
    operation: 'create',
  });
  await trx('reminders').insert({ id, task_id: task.id, ...desired, revision });
}
