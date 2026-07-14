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
import authPlugin from './plugins/auth.js';
import healthRoutes from './routes/health.js';
import authRoutes from './routes/auth.js';
import meRoutes from './routes/me.js';
import projectRoutes from './routes/projects.js';
import tagRoutes from './routes/tags.js';
import taskRoutes from './routes/tasks.js';
import noteRoutes from './routes/notes.js';

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
  await app.register(cors, {
    origin: config.corsOrigin,
    // @fastify/cors defaults to the CORS-safelisted methods (GET/HEAD/POST),
    // which silently blocks browser PATCH/PUT/DELETE preflights (feedback
    // round 3, item 1 — web task edits never reached the server).
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  });
  await app.register(rateLimit, { max: config.rateLimitMax, timeWindow: '1 minute' });
  await app.register(mysqlPlugin, { db });
  await app.register(redisPlugin, { redis });
  await app.register(authPlugin);

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
      docs: 'https://github.com/mahirozdin/alliswell',
      health: '/health/ready',
    }),
  );

  await app.register(healthRoutes, { prefix: '/health' });
  await app.register(authRoutes, { prefix: '/api/v1/auth' });
  await app.register(meRoutes, { prefix: '/api/v1' });
  await app.register(projectRoutes, { prefix: '/api/v1' });
  await app.register(tagRoutes, { prefix: '/api/v1' });
  await app.register(taskRoutes, { prefix: '/api/v1' });
  await app.register(noteRoutes, { prefix: '/api/v1' });

  return app;
}
