import { newId } from '../lib/ids.js';
import { recordSyncWrite } from './sync.js';

/** Statuses that still mean "this alarm will (or may) fire". */
const ACTIVE_STATUSES = ['scheduled', 'snoozed', 'delivered'];

/** Task states in which no alarm must fire. */
const SILENCED_TASK_STATUSES = new Set(['completed', 'cancelled', 'archived']);

/**
 * The two alarms a task can own (OPH-175, round 9). `remind` is the nudge the
 * user asked for; `due` is the deadline itself. Order matters: `remind` is
 * reconciled first, and an instant shared by both belongs to it.
 */
export const ALARM_KINDS = ['remind', 'due'];

function sameInstant(a, b) {
  const [ta, tb] = [a && new Date(a).getTime(), b && new Date(b).getTime()];
  return ta === tb;
}

/**
 * Every alarm a task should have RIGHT NOW, as `[{ kind, at }]` (BLUEPRINT §4.9,
 * NOTIFICATIONS §5a). One rule, one place: REST, the sync push and the calendar
 * job all read it, and the app mirrors it in `ReminderStore.watchAlarms`.
 *
 * - `remind` — whenever `remind_at` is set, at any priority.
 * - `due` — an URGENT task alarms at its deadline **even when a reminder
 *   exists**. Round 9's core correction: a reminder is a nudge BEFORE the
 *   deadline, not a replacement for it. (Round 6 had `remind_at ?? due_at`,
 *   which silently dropped the deadline alarm.)
 * - Both instants equal → only `remind` survives; one moment must never ring
 *   twice.
 * - A task that is deleted, completed, cancelled, archived — or whose alarms the
 *   user silenced indefinitely (`alarms_muted_at`, OPH-178) — has none.
 */
export function alarmInstantsFor(task) {
  if (task.deleted_at != null) return [];
  if (SILENCED_TASK_STATUSES.has(task.status)) return [];
  // Tolerated as undefined until OPH-178 adds the column.
  if (task.alarms_muted_at != null) return [];

  const instants = [];
  if (task.remind_at != null) instants.push({ kind: 'remind', at: task.remind_at });
  if (task.is_urgent && task.due_at != null) instants.push({ kind: 'due', at: task.due_at });
  if (instants.length === 2 && sameInstant(instants[0].at, instants[1].at)) {
    return [instants[0]];
  }
  return instants;
}

/**
 * Keeps a task's reminder rows in lockstep with the task (OPH-034/OPH-175,
 * BLUEPRINT §4.9). Call inside the SAME transaction as the task write, with the
 * post-write task row. Each [ALARM_KINDS] entry is reconciled on its own:
 *
 * - the task wants that alarm → upsert its active row, re-armed to `scheduled`
 * - it does not → terminal-ize that row (`completed` when the task was
 *   completed, else `cancelled`)
 *
 * No-ops when a row already matches — a title-only patch must not burn a
 * reminder revision, and must never wake a snoozed alarm. Reminders are sync
 * entities: every real change records its own revision.
 */
export async function reconcileTaskReminder(trx, { workspaceId, task }) {
  const wanted = new Map(alarmInstantsFor(task).map((i) => [i.kind, i.at]));
  for (const kind of ALARM_KINDS) {
    await reconcileOne(trx, { workspaceId, task, kind, remindAt: wanted.get(kind) ?? null });
  }
}

async function reconcileOne(trx, { workspaceId, task, kind, remindAt }) {
  const active = await trx('reminders')
    .where({ task_id: task.id, kind })
    .whereNull('deleted_at')
    .whereIn('status', ACTIVE_STATUSES)
    .orderBy('created_at', 'desc')
    .first();

  if (remindAt == null) {
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
    remind_at: new Date(remindAt),
    timezone: task.timezone,
    alarm_level: task.is_urgent ? 'urgent' : 'normal',
    requires_acknowledgement: Boolean(task.requires_acknowledgement),
    repeat_rule: task.repeat_rule ?? null,
    status: 'scheduled',
    snoozed_until: null,
    delivered_at: null,
    acknowledged_at: null,
    // A moved instant is a fresh alarm, not "round seven" (OPH-177).
    snooze_count: 0,
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
  await trx('reminders').insert({ id, task_id: task.id, kind, ...desired, revision });
}
