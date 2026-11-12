import fp from 'fastify-plugin';

import { syncEvents } from '../lib/sync-events.js';
import { sendAlarmStopWake, sendWakeHint } from '../db/reminder-push.js';
import { createJobRunner } from '../queue/runner.js';

/**
 * The wake-up hint (OPH-322, ADR-0038 §1): a reminder changed, so the devices
 * that schedule it locally are told to sync — and the alarm then rings from
 * the device's own clock, with its full behaviour intact. Since OPH-436 a task
 * or project change wakes them too (the home-screen widget shows those), and
 * an urgent alarm handled on one phone wakes the others ringing it, past the
 * minute gate (see [createWakeDispatcher]).
 *
 * ── THE STORM THIS EXISTS TO SURVIVE ──────────────────────────────────────
 *
 * `entity:changed` fires once per committed write. Somebody dragging a
 * reminder across a calendar, or a recurrence materialising a dozen
 * occurrences, produces a burst — and every one of them would otherwise be a
 * radio wake on every phone in the workspace.
 *
 * The job key alone does NOT stop that, which is worth writing down because
 * the plan assumed it did. Both runners forget a key the moment the job leaves
 * the queue: the inline one deletes it as the handler STARTS, and BullMQ's
 * `removeOnComplete` frees the `jobId` the moment it finishes. Ten writes
 * spread over a few seconds therefore produced four hints, not one — measured,
 * not guessed (`push-wake.test.js`).
 *
 * So the minute is remembered HERE, and the key stays as the second line of
 * defence for two events in the same tick. The memory is per instance: two
 * replicas can each send one hint for the same minute, which is a phone
 * waking twice in the worst case rather than ten times, and the alternative —
 * a claimed row like `reminder_push_log` — is a migration and a write on the
 * hot path of every reminder change, for a message whose whole content is
 * "sync".
 *
 * ── AND WHY THE KEY IS THE WORKSPACE, NOT THE USER ────────────────────────
 *
 * The plan said `wake:<userId>:<minute>`, which needs the member list BEFORE
 * enqueueing — a `workspace_members` query on the hot path of every reminder
 * write, to produce a key that coalesces less. The recipients are the
 * workspace's members either way (ADR-0038 §5), so resolving them in the
 * HANDLER costs one query per minute instead of one per write.
 */
/**
 * The coalescing key: one hint per workspace per minute. Exported so the test
 * measures the key the plugin actually uses rather than a copy of it.
 */
export const wakeJobKey = (data) => `wake:${data.workspaceId}:${data.minute}`;

/** Which minute an instant falls in — the bucket bursts collapse into. */
export const wakeMinuteOf = (now) => Math.floor(now / 60_000);

/**
 * One hint per workspace per minute, remembered on this instance.
 *
 * A separate object because it is the part with a behaviour worth testing: the
 * job key alone lets a burst through (see the note above), and a gate that
 * only looked right would be found out on somebody's phone rather than here.
 */
export function createWakeGate({ keep = 10_000, forgetAfterMinutes = 60 } = {}) {
  const lastMinute = new Map();
  return {
    /** True when this workspace has not been woken for this minute yet. */
    admit(workspaceId, minute) {
      if (lastMinute.get(workspaceId) === minute) return false;
      lastMinute.set(workspaceId, minute);
      if (lastMinute.size > keep) {
        for (const [id, m] of lastMinute) {
          if (minute - m > forgetAfterMinutes) lastMinute.delete(id);
        }
      }
      return true;
    },
    get size() {
      return lastMinute.size;
    },
  };
}

/**
 * What a wake is for (OPH-436, #50): a reminder schedules an alarm, and a task
 * or a project is what the Android home-screen widget shows. Everything else
 * (notes, files, tags) changes nothing a backgrounded phone has to redraw.
 */
export const WAKE_ENTITY_TYPES = Object.freeze(new Set(['reminder', 'task', 'project']));

/**
 * The window in which an urgent alarm may still be ringing somewhere. Back:
 * the longest insistent chain (40 min, `reminder_profile.dart`) plus 5 min of
 * slack. Forward: one minute, for a device clock slightly ahead of ours.
 */
export const ALARM_STOP_LOOKBACK_MS = 45 * 60_000;
export const ALARM_STOP_LOOKAHEAD_MS = 60_000;

/** The statuses a ringing alarm ends in when somebody handles it. */
const HANDLED_STATUSES = new Set(['acknowledged', 'completed', 'cancelled']);

/**
 * Could this reminder row have just stopped an urgent alarm that is ringing on
 * another phone (#48, gap B)? Snoozing is only ever done to a ringing alarm,
 * so `snoozed` always counts. A handled status counts when the alarm's last
 * ring started inside the window: `remind_at`, or the last snooze, which a
 * snoozed-then-acknowledged row still carries in `snoozed_until`.
 */
export function isAlarmStop(reminder, now) {
  if (reminder.alarm_level !== 'urgent') return false;
  if (reminder.status === 'snoozed') return true;
  if (!HANDLED_STATUSES.has(reminder.status)) return false;
  const inWindow = (at) => {
    if (at == null) return false;
    const t = new Date(at).getTime();
    return t >= now - ALARM_STOP_LOOKBACK_MS && t <= now + ALARM_STOP_LOOKAHEAD_MS;
  };
  return inWindow(reminder.remind_at) || inWindow(reminder.snoozed_until);
}

/**
 * One stop per reminder REVISION, not per minute: two different
 * acknowledgements of two alarms in the same minute must both get through,
 * while one revision announced twice must not wake anybody twice.
 * `updated_at` is DATETIME(3), so the millisecond identifies the write.
 */
export const alarmStopJobKey = (data) => `alarm-stop:${data.reminderId}:${data.revisionMs}`;

/**
 * Turns one `entity:changed` into at most two jobs: the minute-gated hint
 * every Android device gets, and, for a reminder that may have stopped a
 * ringing alarm, a stop wake that skips the gate. Exported so the test drives
 * the decision the plugin actually makes.
 *
 * The stop keys are remembered here for the same reason the gate remembers
 * minutes: the runners forget a job key as the job leaves the queue.
 */
export function createWakeDispatcher({ db, gate, wake, stop, now = Date.now, keep = 1_000 }) {
  const seenStops = new Set();

  return async function dispatch(change) {
    if (!WAKE_ENTITY_TYPES.has(change.entityType)) return;
    const { workspaceId } = change;

    const minute = wakeMinuteOf(now());
    if (gate.admit(workspaceId, minute)) {
      wake.enqueue({ workspaceId, minute });
    }

    // A reminder that was only just created has never rung anywhere, and a
    // recurrence materialising a dozen of them must not cost a dozen reads.
    if (change.entityType !== 'reminder' || change.operation === 'create') return;

    // Read once, after the commit that announced it (the event fires post-
    // commit, `db/sync.js`), so the row is the state the phones will pull.
    const row = await db('reminders')
      .where({ id: change.entityId })
      .first('id', 'status', 'alarm_level', 'remind_at', 'snoozed_until', 'updated_at');
    if (!row || !isAlarmStop(row, now())) return;

    const data = {
      workspaceId,
      reminderId: row.id,
      revisionMs: new Date(row.updated_at).getTime(),
    };
    const key = alarmStopJobKey(data);
    if (seenStops.has(key)) return;
    seenStops.add(key);
    if (seenStops.size > keep) {
      // Insertion order: the oldest revision goes first.
      seenStops.delete(seenStops.values().next().value);
    }
    await stop.enqueue(data);
  };
}

export default fp(
  async function pushWakePlugin(app) {
    const wake = createJobRunner(app, {
      name: 'push-wake',
      handler: (data) => sendWakeHint(app, data),
      jobKey: wakeJobKey,
    });
    const stop = createJobRunner(app, {
      name: 'push-alarm-stop',
      handler: (data) => sendAlarmStopWake(app, data),
      jobKey: alarmStopJobKey,
    });

    const dispatch = createWakeDispatcher({
      db: (...args) => app.db(...args),
      gate: createWakeGate(),
      wake,
      stop,
    });

    const onEntityChanged = (change) => {
      // Nothing to send with means nothing to enqueue: an instance without
      // push credentials should not build a queue it will never drain, nor
      // read a reminder row on every write to decide what not to send.
      if (!app.pushTransport || !app.pushTransport.providers.includes('fcm')) return;
      dispatch(change).catch((err) =>
        app.log.warn({ err: err.message, change }, 'push wake dispatch failed'),
      );
    };
    syncEvents.on('entity:changed', onEntityChanged);

    app.addHook('onClose', async () => {
      syncEvents.off('entity:changed', onEntityChanged);
      await wake.close();
      await stop.close();
    });

    app.decorate('pushWake', wake);
  },
  {
    name: 'alliswell-push-wake',
    dependencies: ['alliswell-redis', 'alliswell-mysql', 'alliswell-push'],
  },
);
