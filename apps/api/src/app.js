import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import sensible from '@fastify/sensible';
import { loadConfig } from './config.js';
import { apiKeyRateBucket } from './lib/api-keys.js';
import mysqlPlugin from './plugins/mysql.js';
import redisPlugin from './plugins/redis.js';
import authPlugin from './plugins/auth.js';
import socketPlugin from './plugins/socket.js';
import mirrorPlugin from './plugins/mirror.js';
import calendarSyncPlugin from './plugins/calendar-sync.js';
import storagePlugin from './plugins/storage.js';
import storageGcPlugin from './plugins/storage-gc.js';
import accountGcPlugin from './plugins/account-gc.js';
import seriesGcPlugin from './plugins/series-gc.js';
import aiPlugin from './plugins/ai.js';
import healthRoutes from './routes/health.js';
import authRoutes from './routes/auth.js';
import meRoutes from './routes/me.js';
import apiKeyRoutes from './routes/api-keys.js';
import projectRoutes from './routes/projects.js';
import tagRoutes from './routes/tags.js';
import taskRoutes from './routes/tasks.js';
import noteRoutes from './routes/notes.js';
import syncRoutes from './routes/sync.js';
import notificationDeviceRoutes from './routes/notification-devices.js';
import reminderRoutes from './routes/reminders.js';
import googleIntegrationRoutes from './routes/integrations-google.js';
import storageRoutes from './routes/storage.js';
import fileRoutes from './routes/files.js';
import folderRoutes from './routes/folders.js';
import quickLinkRoutes from './routes/quick-links.js';
import taskSeriesRoutes from './routes/task-series.js';
import importExportRoutes from './routes/import-export.js';
import aiRoutes from './routes/ai.js';
import oauthRoutes from './routes/oauth.js';
import mcpRoutes from './routes/mcp.js';

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
export async function buildApp({ config = loadConfig(), logger, db, redis, storage } = {}) {
  const app = Fastify({
    logger: logger ?? loggerOptions(config),
    requestIdHeader: 'x-request-id',
    genReqId: () => crypto.randomUUID(),
    // Behind a reverse proxy (every production install: Apache/Nginx/Caddy in
    // front of a loopback-bound API) EVERY request otherwise reads as
    // 127.0.0.1, which collapses the per-IP rate limits into one shared bucket
    // — the 10/min auth limit would then apply to the whole deployment, not
    // per client — and puts the proxy's address in every log line. TRUST_PROXY
    // makes Fastify read X-Forwarded-For instead. Off by default: trusting that
    // header when the API is directly reachable would let anyone spoof an IP.
    trustProxy: config.trustProxy,
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
  // Key-authenticated requests get their own bucket and their own ceiling
  // (ADR-0032 §5): a script must not spend its user's per-IP budget, and one
  // runaway key must not throttle every other client of the instance. Both
  // callbacks read the header rather than `request.apiKeyAuth`, because the
  // limiter runs before authentication has decided anything.
  await app.register(rateLimit, {
    max: (request) => (apiKeyRateBucket(request) ? config.apiKeyRateLimitMax : config.rateLimitMax),
    timeWindow: '1 minute',
    keyGenerator: (request) => apiKeyRateBucket(request) ?? request.ip,
  });
  await app.register(mysqlPlugin, { db });
  await app.register(redisPlugin, { redis });
  await app.register(storagePlugin, { storage });
  await app.register(storageGcPlugin);
  await app.register(accountGcPlugin);
  await app.register(seriesGcPlugin);
  await app.register(authPlugin);
  await app.register(aiPlugin);
  await app.register(socketPlugin);
  await app.register(mirrorPlugin);
  await app.register(calendarSyncPlugin);

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
  await app.register(apiKeyRoutes, { prefix: '/api/v1' });
  await app.register(projectRoutes, { prefix: '/api/v1' });
  await app.register(tagRoutes, { prefix: '/api/v1' });
  await app.register(taskRoutes, { prefix: '/api/v1' });
  await app.register(noteRoutes, { prefix: '/api/v1' });
  await app.register(syncRoutes, { prefix: '/api/v1' });
  await app.register(notificationDeviceRoutes, { prefix: '/api/v1' });
  await app.register(reminderRoutes, { prefix: '/api/v1' });
  await app.register(googleIntegrationRoutes, { prefix: '/api/v1' });
  await app.register(storageRoutes, { prefix: '/api/v1' });
  await app.register(fileRoutes, { prefix: '/api/v1' });
  await app.register(folderRoutes, { prefix: '/api/v1' });
  await app.register(quickLinkRoutes, { prefix: '/api/v1' });
  await app.register(taskSeriesRoutes, { prefix: '/api/v1' });
  // OPH-266: the bulk surface an API key exists for (issue #3).
  await app.register(importExportRoutes, { prefix: '/api/v1' });
  // Conditional registration IS the AI_ENABLED gate: with the feature off,
  // every /ai/* route 404s exactly like a server that never had it (OPH-215).
  if (config.ai.enabled) {
    await app.register(aiRoutes, { prefix: '/api/v1' });
  }
  // The MCP track (OPH-218, ADR-0022) rides its own switch — no /api/v1
  // prefix: /.well-known/*, /oauth/* and /mcp are protocol-fixed paths.
  // Unconfigured instances answer 404 inside the routes (never a boot error).
  if (config.mcp.enabled) {
    await app.register(oauthRoutes);
    await app.register(mcpRoutes);
  }

  return app;
}
