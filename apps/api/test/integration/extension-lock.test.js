import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { coreMigrationsDir, migrationNamesIn } from '../../src/db/migration-dirs.js';

// OPH-343 (ADR-0041) against a real ledger: an extension's migration recorded
// in knex_migrations with the extension itself absent locks the server.
const enabled = process.env.INTEGRATION === '1';

// A ledger row no file in this build answers for. Removed in afterAll — a
// stray row would make the next `knex migrate` refuse a "corrupt" directory.
const FOREIGN = '20990101000000_extension_only_table.js';

const absentConfig = () =>
  loadConfig({ ...process.env, NODE_ENV: 'test', EE_ENABLED: '1', EE_DIR: '/nonexistent/overlay' });

describe.runIf(enabled)('integration: extension lock reads the real migration ledger', () => {
  let probe;

  beforeAll(async () => {
    probe = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
    await probe.db('knex_migrations').where({ name: FOREIGN }).delete();
  });

  afterAll(async () => {
    if (probe) {
      await probe.db('knex_migrations').where({ name: FOREIGN }).delete();
      await probe.close();
    }
  });

  it('reads the real ledger: the plain build exactly when no foreign migration is in it', async () => {
    // The expectation comes from the ledger itself, because the two places
    // this runs hold different databases: core CI migrates core alone (clean →
    // open), a checkout with the overlay migrates both (foreign rows → locked).
    // Real rows are never touched to force a branch.
    const known = new Set(migrationNamesIn(coreMigrationsDir()));
    const names = (await probe.db('knex_migrations').select('name')).map((r) => r.name);
    const foreign = names.filter((name) => !known.has(name));
    const app = await buildApp({ config: absentConfig() });
    try {
      const res = await app.inject({ method: 'GET', url: '/health/ready' });
      if (foreign.length === 0) {
        expect(app.ee.lock).toBeNull();
        expect(res.statusCode).toBe(200);
        expect(Object.keys(res.json().checks).sort()).toEqual(['mysql', 'redis']);
      } else {
        expect(app.ee.lock).toEqual({ code: 'EXTENSION_MISSING' });
        expect(res.statusCode).toBe(503);
      }
    } finally {
      await app.close();
    }
  });

  it('a ledger row the build has no file for locks the server', async () => {
    await probe
      .db('knex_migrations')
      .insert({ name: FOREIGN, batch: 999, migration_time: new Date() });
    const app = await buildApp({ config: absentConfig() });
    try {
      expect(app.ee.lock).toEqual({ code: 'EXTENSION_MISSING' });
      const api = await app.inject({ method: 'GET', url: '/api/v1/me' });
      expect(api.statusCode).toBe(503);
      expect(api.json()).toMatchObject({ code: 'EXTENSION_UNAVAILABLE' });
      const ready = await app.inject({ method: 'GET', url: '/health/ready' });
      expect(ready.statusCode).toBe(503);
      expect(ready.json().checks.extension).toEqual({ status: 'down', error: 'EXTENSION_MISSING' });
    } finally {
      await app.close();
      await probe.db('knex_migrations').where({ name: FOREIGN }).delete();
    }
  });
});
