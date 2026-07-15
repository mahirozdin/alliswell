import fp from 'fastify-plugin';
import { Queue, Worker } from 'bullmq';
import { syncEvents } from '../lib/sync-events.js';
import { runMirrorJob } from '../queue/mirror-job.js';

/**
 * Calendar mirror queue (OPH-072, BLUEPRINT §7.2): every committed task write
 * enqueues a mirror pass for that task. With Redis up this is a BullMQ queue
 * (durable, exponential-backoff retries, shared across API instances);
 * without it — dev degraded mode and the in-memory unit-test db — an inline
 * runner executes jobs on the next tick with the same retry semantics, and
 * `app.mirror.idle()` lets tests await convergence deterministically.
 *
 * The worker re-reads CURRENT state, so bursts converge to the same result
 * no matter how many jobs run; the queue dedupes pending jobs per task.
 */
export default fp(
  async function mirrorPlugin(app) {
    const useBullmq = typeof app.redis?.duplicate === 'function' && app.redis.status === 'ready';

    let mirror;
    if (useBullmq) {
      // BullMQ requires maxRetriesPerRequest: null on its connections.
      const options = {
        lazyConnect: false,
        enableOfflineQueue: true,
        maxRetriesPerRequest: null,
      };
      const queue = new Queue('calendar-mirror', {
        connection: app.redis.duplicate(options),
      });
      const worker = new Worker('calendar-mirror', (job) => runMirrorJob(app, job.data), {
        connection: app.redis.duplicate(options),
      });
      worker.on('failed', (job, err) => {
        app.log.warn({ err: err.message, taskId: job?.data?.taskId }, 'mirror job failed');
      });

      mirror = {
        enqueue: (data) =>
          queue.add('mirror-task', data, {
            // Pending jobs dedupe per task; completed ones are purged so the
            // next change can enqueue again. An ACTIVE job missing this
            // change is fine — it reads current state, and the follow-up
            // enqueue after it completes converges.
            jobId: `task-${data.taskId}`,
            attempts: 5,
            backoff: { type: 'exponential', delay: 1000 },
            removeOnComplete: true,
            removeOnFail: true,
          }),
        idle: async () => {}, // integration tests poll outcomes instead
      };
      app.addHook('onClose', async () => {
        await worker.close();
        await queue.close();
      });
    } else {
      const queued = new Set();
      let chain = Promise.resolve();
      mirror = {
        enqueue(data) {
          if (queued.has(data.taskId)) return;
          queued.add(data.taskId);
          chain = chain.then(async () => {
            queued.delete(data.taskId);
            for (let attempt = 1; attempt <= 3; attempt += 1) {
              try {
                await runMirrorJob(app, data);
                return;
              } catch (err) {
                if (attempt === 3) {
                  app.log.warn(
                    { err: err.message, taskId: data.taskId },
                    'mirror job failed (inline)',
                  );
                }
              }
            }
          });
        },
        idle: () => chain,
      };
    }

    const onEntityChanged = (change) => {
      if (change.entityType !== 'task') return;
      mirror.enqueue({ workspaceId: change.workspaceId, taskId: change.entityId });
    };
    syncEvents.on('entity:changed', onEntityChanged);
    app.addHook('onClose', async () => {
      syncEvents.off('entity:changed', onEntityChanged);
    });

    app.decorate('mirror', mirror);
  },
  {
    name: 'alliswell-mirror',
    dependencies: ['alliswell-redis', 'alliswell-mysql'],
  },
);
