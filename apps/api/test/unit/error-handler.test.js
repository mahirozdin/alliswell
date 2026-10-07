import { describe, it, expect, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

const testConfig = loadConfig({ NODE_ENV: 'test' });

/** What mysql2 throws for the audit's dated announcement under strict mode. */
function strictModeError() {
  const err = new Error(
    "Incorrect datetime value: '2026-10-07T14:23:59.010Z' for column 'starts_at' at row 1 — " +
      'insert into `ee_announcements` (`body`, `created_by_user_id`, `starts_at`) values ' +
      "(NULL, '01M3JE8104AAAAAAAAAAAAAAAA', '2026-10-07T14:23:59.010Z')",
  );
  err.code = 'ER_TRUNCATED_WRONG_VALUE';
  err.errno = 1292;
  err.sql = 'insert into `ee_announcements` …';
  return err;
}

async function appWith(register) {
  const { db } = fakeDb();
  const app = await buildApp({ config: testConfig, db, redis: fakeRedis() });
  await register(app);
  return app;
}

describe('root error handler (OPH-357)', () => {
  it('UI-AUDIT #16: a driver error answers a fixed INTERNAL_ERROR body, no SQL', async () => {
    const logged = vi.fn();
    const app = await appWith((app) => {
      app.get('/boom', async (request) => {
        request.log.error = logged;
        throw strictModeError();
      });
    });

    const res = await app.inject({ method: 'GET', url: '/boom' });
    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({
      statusCode: 500,
      code: 'INTERNAL_ERROR',
      error: 'Internal Server Error',
      message: 'Internal server error',
    });
    expect(res.body).not.toMatch(/insert into|ee_announcements|ER_TRUNCATED|01M3JE/);
    // The real error is not lost: it goes to the log.
    expect(logged).toHaveBeenCalledTimes(1);
    expect(logged.mock.calls[0][0].err.code).toBe('ER_TRUNCATED_WRONG_VALUE');

    await app.close();
  });

  it('UI-AUDIT #16: a runtime error inside a nested plugin is generic too', async () => {
    const app = await appWith((app) =>
      app.register(
        async (child) => {
          child.get('/x', async () => {
            const row = undefined;
            return row.secretColumn;
          });
        },
        { prefix: '/nested' },
      ),
    );

    const res = await app.inject({ method: 'GET', url: '/nested/x' });
    expect(res.statusCode).toBe(500);
    expect(res.json().code).toBe('INTERNAL_ERROR');
    expect(res.body).not.toMatch(/secretColumn|TypeError/);

    await app.close();
  });

  it('UI-AUDIT #16: 4xx bodies are unchanged (coded httpError and schema validation)', async () => {
    const app = await appWith((app) => {
      app.get('/missing', async () => {
        const err = app.httpErrors.notFound('Task not found');
        err.code = 'TASK_NOT_FOUND';
        throw err;
      });
      app.post(
        '/strict',
        {
          schema: {
            body: {
              type: 'object',
              required: ['title'],
              properties: { title: { type: 'string' } },
            },
          },
        },
        async () => ({ ok: true }),
      );
    });

    const missing = await app.inject({ method: 'GET', url: '/missing' });
    expect(missing.statusCode).toBe(404);
    expect(missing.json()).toEqual({
      statusCode: 404,
      code: 'TASK_NOT_FOUND',
      error: 'Not Found',
      message: 'Task not found',
    });

    const invalid = await app.inject({ method: 'POST', url: '/strict', payload: {} });
    expect(invalid.statusCode).toBe(400);
    expect(invalid.json()).toMatchObject({
      statusCode: 400,
      code: 'FST_ERR_VALIDATION',
      error: 'Bad Request',
      message: "body must have required property 'title'",
    });

    await app.close();
  });

  it('UI-AUDIT #16: a 5xx written on purpose keeps its code and words', async () => {
    const app = await appWith((app) => {
      app.get('/unconfigured', async () => {
        const err = app.httpErrors.serviceUnavailable('Storage is not configured');
        err.code = 'STORAGE_NOT_CONFIGURED';
        throw err;
      });
    });

    const res = await app.inject({ method: 'GET', url: '/unconfigured' });
    expect(res.statusCode).toBe(503);
    expect(res.json()).toEqual({
      statusCode: 503,
      code: 'STORAGE_NOT_CONFIGURED',
      error: 'Service Unavailable',
      message: 'Storage is not configured',
    });

    await app.close();
  });

  it("UI-AUDIT #16: a plugin's own error handler wins over the root one", async () => {
    const app = await appWith((app) =>
      app.register(
        async (portal) => {
          portal.setErrorHandler((_err, _request, reply) =>
            reply.code(500).type('text/html').send('<p>Bir sorun oluştu</p>'),
          );
          portal.get('/page', async () => {
            throw strictModeError();
          });
        },
        { prefix: '/p' },
      ),
    );

    const res = await app.inject({ method: 'GET', url: '/p/page' });
    expect(res.statusCode).toBe(500);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.body).toBe('<p>Bir sorun oluştu</p>');

    await app.close();
  });

  it("a route limiter's own 429 body keeps its 429, not a 200", async () => {
    const body = {
      statusCode: 429,
      error: 'Too Many Requests',
      code: 'SALES_TEMPORARILY_UNAVAILABLE',
      message: 'Too many requests right now.',
    };
    const app = await appWith((app) =>
      app.post(
        '/shield',
        {
          config: {
            rateLimit: {
              max: 1,
              timeWindow: '1 minute',
              keyGenerator: () => 'one',
              errorResponseBuilder: () => body,
            },
          },
        },
        async () => ({ ok: true }),
      ),
    );

    expect((await app.inject({ method: 'POST', url: '/shield' })).statusCode).toBe(200);
    const refused = await app.inject({ method: 'POST', url: '/shield' });
    expect(refused.statusCode).toBe(429);
    expect(refused.json()).toEqual(body);

    await app.close();
  });
});
