import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL (strict mode, as every install runs it).
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('integration: root error handler (OPH-357)', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
    // The audit's #16 in miniature: an ISO-8601 string written to a DATETIME
    // column, unconverted — strict MySQL refuses it with the statement in the
    // message.
    app.post('/__oph357/dated', async () => {
      await app.db.transaction(async (trx) => {
        await trx.raw('CREATE TEMPORARY TABLE oph357_dated (starts_at DATETIME(3))');
        await trx('oph357_dated').insert({ starts_at: '2026-10-07T14:23:59.010Z' });
      });
      return { ok: true };
    });
  });

  afterAll(async () => {
    await app?.close();
  });

  it('UI-AUDIT #16: a strict-mode MySQL error answers 500 without SQL', async () => {
    const res = await app.inject({ method: 'POST', url: '/__oph357/dated' });
    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({
      statusCode: 500,
      code: 'INTERNAL_ERROR',
      error: 'Internal Server Error',
      message: 'Internal server error',
    });
    expect(res.body).not.toMatch(/insert|oph357_dated|starts_at|ER_TRUNCATED|datetime/i);
  });
});
