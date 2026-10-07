import { describe, it, expect, beforeAll, afterAll } from 'vitest';

import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

const enabled = process.env.INTEGRATION === '1';

/**
 * A MySQL whose `time_zone` is SYSTEM on a non-UTC host used to stamp column
 * defaults in local wall time, which the API read back as UTC — rows "updated"
 * hours in the future that beat every device under last-write-wins.
 */
describe.runIf(enabled)('integration: the database clock is UTC on every connection', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  it('the session time zone is UTC whatever the server default is', async () => {
    const [rows] = await app.db.raw('SELECT @@session.time_zone AS tz');
    expect(rows[0].tz).toBe('+00:00');
  });

  it('NOW() read through the API driver is the real instant', async () => {
    const [rows] = await app.db.raw('SELECT NOW(3) AS now');
    const drift = Math.abs(new Date(rows[0].now).getTime() - Date.now());
    expect(drift).toBeLessThan(60_000);
  });
});
