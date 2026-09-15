import fp from 'fastify-plugin';

import { syncEvents } from '../lib/sync-events.js';
import { sendWakeHint } from '../db/reminder-push.js';
import { createJobRunner } from '../queue/runner.js';

/**
 * The wake-up hint (OPH-322, ADR-0038 §1): a reminder changed, so the devices
 * that schedule it locally are told to sync — and the alarm then rings from
 * the device's own clock, with its full behaviour intact.
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

export default fp(
  async function pushWakePlugin(app) {
    const wake = createJobRunner(app, {
      name: 'push-wake',
      handler: (data) => sendWakeHint(app, data),
      jobKey: wakeJobKey,
    });

    const gate = createWakeGate();

    const onEntityChanged = (change) => {
      if (change.entityType !== 'reminder') return;
      // Nothing to send with means nothing to enqueue: an instance without
      // push credentials should not build a queue it will never drain.
      if (!app.pushTransport) return;

      const minute = wakeMinuteOf(Date.now());
      if (!gate.admit(change.workspaceId, minute)) return;
      wake.enqueue({ workspaceId: change.workspaceId, minute });
    };
    syncEvents.on('entity:changed', onEntityChanged);

    app.addHook('onClose', async () => {
      syncEvents.off('entity:changed', onEntityChanged);
      await wake.close();
    });

    app.decorate('pushWake', wake);
  },
  {
    name: 'alliswell-push-wake',
    dependencies: ['alliswell-redis', 'alliswell-mysql', 'alliswell-push'],
  },
);
