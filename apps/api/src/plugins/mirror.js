import fp from 'fastify-plugin';
import { syncEvents } from '../lib/sync-events.js';
import { runMirrorJob } from '../queue/mirror-job.js';
import { createJobRunner } from '../queue/runner.js';

/**
 * Calendar mirror queue — the OUTBOUND half of BLUEPRINT §7.2 (OPH-072):
 * every committed task write enqueues a mirror pass for that task. Queue
 * mechanics (BullMQ vs inline, retries, dedupe) live in `queue/runner.js`;
 * the inbound half is `plugins/calendar-sync.js`.
 *
 * The worker re-reads CURRENT task state, so bursts converge to the same
 * result no matter how many jobs run.
 */
export default fp(
  async function mirrorPlugin(app) {
    const mirror = createJobRunner(app, {
      name: 'calendar-mirror',
      handler: (data) => runMirrorJob(app, data),
      jobKey: (data) => `task-${data.taskId}`,
    });

    const onEntityChanged = (change) => {
      if (change.entityType !== 'task') return;
      mirror.enqueue({ workspaceId: change.workspaceId, taskId: change.entityId });
    };
    syncEvents.on('entity:changed', onEntityChanged);

    app.addHook('onClose', async () => {
      syncEvents.off('entity:changed', onEntityChanged);
      await mirror.close();
    });

    app.decorate('mirror', mirror);
  },
  {
    name: 'alliswell-mirror',
    dependencies: ['alliswell-redis', 'alliswell-mysql'],
  },
);
