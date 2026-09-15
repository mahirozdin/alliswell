import { newId } from '../lib/ids.js';
import { buildReminderPayload } from '../lib/push/payload.js';

/**
 * The due sweep (OPH-315, ADR-0038 §1/§2/§3) — the first thing in AllisWell
 * that sends a push at the moment an alarm is supposed to ring.
 *
 * ── WHY THIS EXISTS AT ALL, AND ONLY FOR SOME DEVICES ─────────────────────
 *
 * `NOTIFICATIONS.md` §0 says the device is the clock, and on every platform
 * with a scheduling API that stays true. The browser has no such API — a
 * closed tab schedules nothing — so ADR-0038 §3 amends §0 for exactly one
 * platform: on the web the SERVER is the clock. Everywhere else this sweep is
 * a safety net, not a schedule, and it only fires at a device whose local
 * schedule is known to be out of date.
 *
 * ── THE INSTANT A REMINDER FIRES IS NOT ALWAYS `remind_at` ────────────────
 *
 * A snoozed reminder keeps its original `remind_at` and carries the new
 * instant in `snoozed_until` (`routes/sync.js:776-784`). Sweeping `remind_at`
 * alone would therefore miss every snooze — its `remind_at` is already behind
 * the window — and would stamp the log row with the wrong instant, when
 * `reminder_push_log.fire_at` exists precisely to tell one firing from the
 * next. So the two statuses are two queries, which is also the only shape that
 * can use an index: `idx_reminders_due` is `(status, remind_at)`, and an OR
 * across two different columns cannot.
 *
 * ── THE WINDOW LOOKS BACK, NOT FORWARD ────────────────────────────────────
 *
 * A push IS the alarm on the web: the service worker shows it when it arrives,
 * because it has nothing to schedule it with. Sending five minutes early would
 * ring five minutes early. So the window covers what has BECOME due since the
 * last tick — `[now - dueWindowSec, now]` — which is what also makes a missed
 * tick recoverable rather than lost.
 *
 * ── STALENESS IS ONE COMPARISON ───────────────────────────────────────────
 *
 * `notification_devices.last_seen_at < reminders.updated_at` (ADR-0038 §2). A
 * device that synced after the change already holds the alarm locally and must
 * NOT be pushed to, or the user gets warned twice for one reminder. The web is
 * the exception in the other direction: it is pushed to whether it is stale or
 * not, because holding the alarm locally buys a browser nothing.
 *
 * ── AND SENDING IS CLAIMED, NOT REMEMBERED ────────────────────────────────
 *
 * Two instances sweep the same minute; one timer that missed a tick sweeps a
 * window that overlaps the next one. Neither may send twice, and neither may
 * ask the other. The insert into `reminder_push_log` IS the claim: the unique
 * index on `(reminder_id, device_id, fire_at)` makes exactly one of them win,
 * and the loser is told by ER_DUP_ENTRY that somebody else has this one.
 *
 * `reminders.status` is deliberately untouched — writing `delivered` onto it
 * would be a revision per reminder per device, pulled down by every client at
 * the busiest minute of its day, for something no client needs to know.
 */

/** Statuses whose alarm has not fired yet and has not been cancelled. */
export const DUE_STATUSES = Object.freeze(['scheduled', 'snoozed']);

/**
 * The instant this row is about. `delivered` is not swept — it has already
 * rung — so the only two shapes are the two in [DUE_STATUSES].
 */
export function fireInstantOf(reminder) {
  return reminder.status === 'snoozed' && reminder.snoozed_until != null
    ? reminder.snoozed_until
    : reminder.remind_at;
}

/**
 * Does this device still need to be told? The web always does (it cannot
 * schedule); everything else only when it has not synced since the change.
 */
export function needsPush(device, reminder) {
  if (device.platform === 'web') return true;
  return new Date(device.last_seen_at).getTime() < new Date(reminder.updated_at).getTime();
}

/**
 * Everything that fell due in `[from, to]` and has not rung yet, as rows with
 * the instant already resolved. Two queries rather than one OR — see the note
 * above about the index.
 */
export async function findDueReminders(db, { from, to }) {
  const scheduled = await db('reminders')
    .where('status', 'scheduled')
    .whereNull('deleted_at')
    .where('remind_at', '>=', from)
    .where('remind_at', '<=', to)
    .select();
  const snoozed = await db('reminders')
    .where('status', 'snoozed')
    .whereNull('deleted_at')
    .where('snoozed_until', '>=', from)
    .where('snoozed_until', '<=', to)
    .select();
  return [...scheduled, ...snoozed];
}

/**
 * The devices of every member of the workspaces those reminders belong to
 * (ADR-0038 §5 — not a widening: exactly the devices that schedule the alarm
 * locally today), keyed by reminder id.
 *
 * Deliberately four small `whereIn` queries instead of one join: the sets are
 * one sweep window wide, and the API's unit suite runs without MySQL
 * (`test/helpers/fakedb.js`), which is where the idempotency of this path is
 * actually proved.
 */
async function devicesByReminder(db, reminders, { providers }) {
  const taskIds = [...new Set(reminders.map((r) => r.task_id))];
  const tasks = await db('tasks').whereIn('id', taskIds).select('id', 'workspace_id');
  const workspaceOf = new Map(tasks.map((t) => [t.id, t.workspace_id]));

  const workspaceIds = [...new Set(tasks.map((t) => t.workspace_id))];
  const members = await db('workspace_members')
    .whereIn('workspace_id', workspaceIds)
    .select('workspace_id', 'user_id');
  const usersOf = new Map();
  for (const m of members) {
    if (!usersOf.has(m.workspace_id)) usersOf.set(m.workspace_id, []);
    usersOf.get(m.workspace_id).push(m.user_id);
  }

  const userIds = [...new Set(members.map((m) => m.user_id))];
  const devices =
    userIds.length === 0
      ? []
      : await db('notification_devices').whereIn('user_id', userIds).select();
  const reachable = devices.filter(
    // A device with no credentials is not a device we can reach, and one that
    // was written off stays written off until it registers again (OPH-312).
    (d) => d.invalid_at == null && providers.includes(d.push_provider),
  );
  const devicesOf = new Map();
  for (const d of reachable) {
    if (!devicesOf.has(d.user_id)) devicesOf.set(d.user_id, []);
    devicesOf.get(d.user_id).push(d);
  }

  const out = new Map();
  for (const reminder of reminders) {
    const workspaceId = workspaceOf.get(reminder.task_id);
    const users = usersOf.get(workspaceId) ?? [];
    out.set(
      reminder.id,
      users.flatMap((userId) => devicesOf.get(userId) ?? []).filter((d) => needsPush(d, reminder)),
    );
  }
  return out;
}

/**
 * Claims one (reminder, device, instant) by inserting the log row. Returns the
 * row id, or `null` when another sweep already holds it.
 */
async function claim(db, { reminder, device, fireAt }) {
  const id = newId();
  try {
    await db('reminder_push_log').insert({
      id,
      reminder_id: reminder.id,
      device_id: device.id,
      fire_at: fireAt,
      provider: device.push_provider,
      result: 'pending',
    });
    return id;
  } catch (err) {
    if (err?.code === 'ER_DUP_ENTRY') return null;
    throw err;
  }
}

/**
 * One pass. Returns `{ due, claimed, sent, failed }` — numbers a test can
 * assert, which is why the sweep reports rather than logs its own success.
 *
 * @param {object} app the fastify instance (db, pushTransport, log, config)
 * @param {{now?: Date}} options the clock, injected — the API suite does not
 *   fake timers, it passes the instant it wants (the house pattern of
 *   `seriesGc.sweep(now)`).
 */
export async function sweepDuePushes(app, { now = new Date() } = {}) {
  const empty = { due: 0, claimed: 0, sent: 0, failed: 0 };
  // No credentials, no sending — and nothing half-done in between (ADR-0038
  // §7). An instance that has not configured push behaves exactly as it did
  // before any of this existed.
  if (!app.pushTransport) return empty;

  const from = new Date(now.getTime() - app.config.push.dueWindowSec * 1000);
  const reminders = await findDueReminders(app.db, { from, to: now });
  if (reminders.length === 0) return empty;

  const targets = await devicesByReminder(app.db, reminders, {
    providers: app.pushTransport.providers,
  });

  let claimed = 0;
  let sent = 0;
  let failed = 0;

  for (const reminder of reminders) {
    const devices = targets.get(reminder.id) ?? [];
    if (devices.length === 0) continue;

    const fireAt = new Date(fireInstantOf(reminder));
    const claims = new Map();
    for (const device of devices) {
      const logId = await claim(app.db, { reminder, device, fireAt });
      if (logId) claims.set(device.id, logId);
    }
    if (claims.size === 0) continue;
    claimed += claims.size;

    // The payload names the row and the fixed message; the words live on the
    // device (BLUEPRINT §8.3). `alert` is what makes it a push the user SEES,
    // which on the web is the whole point and on mobile is the fallback.
    const payload = buildReminderPayload({
      reminderId: reminder.id,
      taskId: reminder.task_id,
      fireAt: fireAt.toISOString(),
      alert: 'reminder_due',
    });
    const results = await app.pushTransport.send(
      devices.filter((d) => claims.has(d.id)),
      payload,
    );

    const outcomeOf = new Map(results.map((r) => [r.deviceId, r.outcome]));
    for (const [deviceId, logId] of claims) {
      const ok = outcomeOf.get(deviceId) === 'sent';
      if (ok) sent += 1;
      else failed += 1;
      await app
        .db('reminder_push_log')
        .where({ id: logId })
        .update(ok ? { result: 'sent', sent_at: new Date() } : { result: 'failed' });
    }
  }

  if (claimed > 0) {
    app.log?.info?.({ due: reminders.length, claimed, sent, failed }, 'reminder push sweep');
  }
  return { due: reminders.length, claimed, sent, failed };
}
