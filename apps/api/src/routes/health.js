import { withTimeout } from '../lib/async.js';

const CHECK_TIMEOUT_MS = 1500;

const componentSchema = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['up', 'down'] },
    latencyMs: { type: 'number' },
    error: { type: 'string' },
  },
  required: ['status'],
};

const readySchema = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['ok', 'degraded'] },
    checks: {
      type: 'object',
      // `extension` appears only when there is one to report (OPH-343): a
      // loaded overlay, or a server locked because its extension is missing.
      // The plain build's answer carries exactly the two it always did.
      properties: { mysql: componentSchema, redis: componentSchema, extension: componentSchema },
      required: ['mysql', 'redis'],
    },
  },
  required: ['status', 'checks'],
};

async function checkMysql(app) {
  const startedAt = Date.now();
  try {
    await withTimeout(app.db.raw('SELECT 1'), CHECK_TIMEOUT_MS, 'mysql ping');
    return { status: 'up', latencyMs: Date.now() - startedAt };
  } catch (err) {
    return { status: 'down', error: err.message };
  }
}

async function checkRedis(app) {
  const startedAt = Date.now();
  try {
    await withTimeout(app.redis.ping(), CHECK_TIMEOUT_MS, 'redis ping');
    return { status: 'up', latencyMs: Date.now() - startedAt };
  } catch (err) {
    return { status: 'down', error: err.message };
  }
}

export default async function healthRoutes(app) {
  app.get(
    '/live',
    {
      config: { rateLimit: false },
      schema: {
        response: {
          200: {
            type: 'object',
            properties: {
              status: { type: 'string', enum: ['ok'] },
              uptimeSec: { type: 'number' },
              version: { type: 'string' },
            },
            required: ['status'],
          },
        },
      },
    },
    async () => ({
      status: 'ok',
      uptimeSec: Math.round(process.uptime()),
      version: app.pkg.version,
    }),
  );

  app.get(
    '/ready',
    {
      config: { rateLimit: false },
      schema: { response: { 200: readySchema, 503: readySchema } },
    },
    async (_request, reply) => {
      const [mysql, redis] = await Promise.all([checkMysql(app), checkRedis(app)]);
      const checks = { mysql, redis };
      const extension = (await app.ee?.readiness?.()) ?? null;
      if (extension) checks.extension = extension;
      const ok =
        mysql.status === 'up' && redis.status === 'up' && (!extension || extension.status === 'up');
      return reply.code(ok ? 200 : 503).send({ status: ok ? 'ok' : 'degraded', checks });
    },
  );
}
