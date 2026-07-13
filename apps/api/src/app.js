import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import sensible from '@fastify/sensible';
import { loadConfig } from './config.js';
import mysqlPlugin from './plugins/mysql.js';
import redisPlugin from './plugins/redis.js';
import healthRoutes from './routes/health.js';

const require = createRequire(import.meta.url);
const pkg = require('../package.json');

function loggerOptions(config) {
  if (config.env === 'test') return false;
  const options = { level: config.logLevel };
  if (config.env === 'development') {
    options.transport = {
      target: 'pino-pretty',
      options: { translateTime: 'HH:MM:ss.l', ignore: 'pid,hostname' },
    };
  }
  return options;
}

/**
 * Application factory. Everything (config, logger, connections) is injectable so
 * tests can build a fully functional app with stubbed infrastructure:
 *
 *   const app = await buildApp({ config, db: fakeDb, redis: fakeRedis });
 *   const res = await app.inject({ method: 'GET', url: '/health/ready' });
 */
export async function buildApp({ config = loadConfig(), logger, db, redis } = {}) {
  const app = Fastify({
    logger: logger ?? loggerOptions(config),
    requestIdHeader: 'x-request-id',
    genReqId: () => crypto.randomUUID(),
  });

  app.decorate('config', config);
  app.decorate('pkg', { name: pkg.name, version: pkg.version });

  await app.register(sensible);
  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, { origin: config.corsOrigin });
  await app.register(rateLimit, { max: config.rateLimitMax, timeWindow: '1 minute' });
  await app.register(mysqlPlugin, { db });
  await app.register(redisPlugin, { redis });

  app.get(
    '/',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            properties: {
              name: { type: 'string' },
              version: { type: 'string' },
              docs: { type: 'string' },
              health: { type: 'string' },
            },
          },
        },
      },
    },
    async () => ({
      name: 'AllisWell API',
      version: app.pkg.version,
      docs: 'https://github.com/mahirtahaozdin/alliswell',
      health: '/health/ready',
    }),
  );

  await app.register(healthRoutes, { prefix: '/health' });

  return app;
}
