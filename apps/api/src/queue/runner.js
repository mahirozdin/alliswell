import { Queue, Worker } from 'bullmq';

/**
 * A background job runner in two modes, so the same feature code works with or
 * without Redis (OPH-072, generalized for OPH-074/075):
 *
 * - **Redis up** → a BullMQ queue: durable, exponential-backoff retries, and
 *   shared across API instances (only one of them runs any given job).
 * - **Redis down** → dev degraded mode and the in-memory unit-test db: an
 *   inline runner drains jobs on the next tick with the same retry shape, and
 *   `idle()` lets tests await convergence deterministically.
 *
 * Both modes dedupe PENDING jobs by `jobKey`, which is safe because every
 * handler here re-reads current state and converges — a burst of enqueues for
 * the same key is the same work. An ACTIVE job that misses the newest change
 * is fine too: the enqueue that follows it runs again.
 *
 * @param {import('fastify').FastifyInstance} app
 * @param {{ name: string, handler: (data: any) => Promise<void>,
 *           jobKey: (data: any) => string, attempts?: number }} spec
 * @returns {{ enqueue: (data: any) => Promise<void>, idle: () => Promise<void>,
 *             close: () => Promise<void> }}
 */
export function createJobRunner(app, { name, handler, jobKey, attempts = 5 }) {
  const useBullmq = typeof app.redis?.duplicate === 'function' && app.redis.status === 'ready';

  if (useBullmq) {
    // BullMQ requires maxRetriesPerRequest: null on its connections.
    const options = { lazyConnect: false, enableOfflineQueue: true, maxRetriesPerRequest: null };
    // The prefix is what keeps deployments that share a Redis from consuming
    // each other's jobs (config.redisKeyPrefix) — a stolen job is not just
    // misrouted, it is LOST: the thief's own MySQL has no such task, so the
    // handler returns quietly and the change never reaches the calendar.
    const prefix = app.config.redisKeyPrefix;
    const queue = new Queue(name, { connection: app.redis.duplicate(options), prefix });
    const worker = new Worker(name, (job) => handler(job.data), {
      connection: app.redis.duplicate(options),
      prefix,
    });
    worker.on('failed', (job, err) => {
      app.log.warn({ err: err.message, job: job?.data }, `${name} job failed`);
    });

    return {
      // Never rejects: enqueueing is fire-and-forget at most call sites, and a
      // queue hiccup must not fail the request that triggered it.
      enqueue: (data) =>
        queue
          .add(name, data, {
            jobId: jobKey(data),
            attempts,
            backoff: { type: 'exponential', delay: 1000 },
            removeOnComplete: true,
            removeOnFail: true,
          })
          .then(
            () => {},
            (err) => app.log.warn({ err: err.message, job: data }, `${name} enqueue failed`),
          ),
      idle: async () => {}, // integration tests poll outcomes instead
      close: async () => {
        await worker.close();
        await queue.close();
      },
    };
  }

  const pending = new Set();
  let chain = Promise.resolve();
  const INLINE_ATTEMPTS = 3;

  return {
    enqueue(data) {
      const key = jobKey(data);
      if (pending.has(key)) return Promise.resolve();
      pending.add(key);
      chain = chain.then(async () => {
        pending.delete(key);
        for (let attempt = 1; attempt <= INLINE_ATTEMPTS; attempt += 1) {
          try {
            await handler(data);
            return;
          } catch (err) {
            if (attempt === INLINE_ATTEMPTS) {
              app.log.warn({ err: err.message, job: data }, `${name} job failed (inline)`);
            }
          }
        }
      });
      return Promise.resolve();
    },
    idle: () => chain,
    close: () => chain.catch(() => {}),
  };
}
