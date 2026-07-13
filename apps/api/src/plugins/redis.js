import fp from 'fastify-plugin';
import { Redis } from 'ioredis';
import { withTimeout } from '../lib/async.js';

/**
 * Decorates the app with `app.redis` (an ioredis instance).
 *
 * The offline queue is disabled so commands fail fast while disconnected —
 * /health/ready then reports `down` immediately instead of hanging. A background
 * retry strategy keeps reconnecting, so recovery is automatic.
 *
 * Tests may pass a stub via `buildApp({ redis })`.
 */
export default fp(
  async function redisPlugin(app, opts) {
    const owned = !opts.redis;
    const redis =
      opts.redis ??
      new Redis(app.config.redisUrl, {
        lazyConnect: true,
        enableOfflineQueue: false,
        maxRetriesPerRequest: 1,
        retryStrategy: (times) => Math.min(times * 500, 5000),
      });

    if (owned) {
      redis.on('error', (err) => app.log.warn({ err: err.message }, 'redis connection error'));
      try {
        await withTimeout(redis.connect(), 2000, 'redis connect');
      } catch (err) {
        app.log.warn(
          { err: err.message },
          'redis not reachable at boot; /health/ready will report degraded until it recovers',
        );
      }
    }

    app.decorate('redis', redis);

    app.addHook('onClose', async () => {
      if (owned) {
        try {
          await redis.quit();
        } catch {
          redis.disconnect();
        }
      }
    });
  },
  { name: 'alliswell-redis' },
);
