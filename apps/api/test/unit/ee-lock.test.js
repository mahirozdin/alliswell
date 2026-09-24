import { describe, it, expect, afterEach } from 'vitest';
import { fileURLToPath } from 'node:url';

import { buildTestApp, registerUser } from '../helpers/authed.js';
import { loadConfig } from '../../src/config.js';

/**
 * OPH-343 (ADR-0041) — the loader locks the server when an extension that
 * governs data cannot be served. The five states of the failure policy in
 * `src/lib/ee.js`, plus the two ways the ledger can answer late.
 */

const FIXTURE_DIR = fileURLToPath(new URL('../fixtures/ee-overlay', import.meta.url));
const BROKEN_DIR = fileURLToPath(new URL('../fixtures/ee-overlay-broken', import.meta.url));
const HALFWAY_DIR = fileURLToPath(new URL('../fixtures/ee-overlay-halfway', import.meta.url));
const ABSENT_DIR = '/nonexistent/overlay';

// A ledger row no file in this build answers for — what an extension's
// migrations leave behind when the extension itself is gone.
const FOREIGN_MIGRATION = { name: '20990101000000_extension_only_table.js' };

const config = (dir, extra = {}) =>
  loadConfig({
    NODE_ENV: 'test',
    RATE_LIMIT_AUTH_MAX: '1000',
    EE_ENABLED: '1',
    EE_DIR: dir,
    ...extra,
  });

let app;

afterEach(async () => {
  await app?.close();
  app = undefined;
});

/** Builds the app and seeds the fake ledger BEFORE the loader reads it. */
async function build(dir, { ledger = [], extra, dbOptions } = {}) {
  const built = await buildTestApp({
    config: config(dir, extra),
    dbOptions: { ...dbOptions, seedLedger: ledger },
  });
  return built;
}

const ready = async () => {
  const res = await app.inject({ method: 'GET', url: '/health/ready' });
  return { status: res.statusCode, body: res.json() };
};

describe('extension lock (OPH-343)', () => {
  it('plain build (disabled): readiness carries exactly mysql and redis, nothing is locked', async () => {
    ({ app } = await buildTestApp());
    const r = await ready();
    expect(r.status).toBe(200);
    expect(Object.keys(r.body.checks).sort()).toEqual(['mysql', 'redis']);
    expect(app.ee.lock).toBeNull();
    const user = await registerUser(app, { email: 'plain@example.com' });
    const me = await app.inject({ method: 'GET', url: '/api/v1/me', headers: user.headers });
    expect(me.statusCode).toBe(200);
  });

  it('absent overlay + clean ledger = the plain build, byte for byte', async () => {
    ({ app } = await build(ABSENT_DIR));
    expect(app.ee.lock).toBeNull();
    const r = await ready();
    expect(r.status).toBe(200);
    expect(Object.keys(r.body.checks).sort()).toEqual(['mysql', 'redis']);
  });

  it('AW-E01: absent overlay + a ledger it wrote → locked; a member cannot delete a task', async () => {
    // The tester's scenario: a deploy lost the extension's files while the
    // database still holds what it wrote. A member it restricted to viewing
    // must not get the plain build's wider rights — the server refuses.
    ({ app } = await build(ABSENT_DIR, { ledger: [FOREIGN_MIGRATION] }));
    expect(app.ee.lock).toEqual({ code: 'EXTENSION_MISSING' });

    const del = await app.inject({
      method: 'DELETE',
      url: '/api/v1/tasks/01HZZZZZZZZZZZZZZZZZZZZZZZ',
    });
    expect(del.statusCode).toBe(503);
    expect(del.json()).toMatchObject({ code: 'EXTENSION_UNAVAILABLE' });

    const live = await app.inject({ method: 'GET', url: '/health/live' });
    expect(live.statusCode).toBe(200);
    const r = await ready();
    expect(r.status).toBe(503);
    expect(r.body.checks.extension).toEqual({ status: 'down', error: 'EXTENSION_MISSING' });
  });

  it('EE_REQUIRED=false: the operator accepts plain-build rules over that ledger', async () => {
    ({ app } = await build(ABSENT_DIR, {
      ledger: [FOREIGN_MIGRATION],
      extra: { EE_REQUIRED: 'false' },
    }));
    expect(app.ee.lock).toBeNull();
    expect((await ready()).status).toBe(200);
  });

  it('EE_REQUIRED=true: absence locks even over a clean ledger', async () => {
    ({ app } = await build(ABSENT_DIR, { extra: { EE_REQUIRED: 'true' } }));
    expect(app.ee.lock).toEqual({ code: 'EXTENSION_REQUIRED' });
    const res = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: {} });
    expect(res.statusCode).toBe(503);
  });

  it('a present overlay that fails to load locks — in every EE_REQUIRED state', async () => {
    for (const extra of [{}, { EE_REQUIRED: 'false' }]) {
      ({ app } = await build(BROKEN_DIR, { extra }));
      expect(app.ee.loaded).toBe(false);
      expect(app.ee.error).toMatch(/already taken/);
      expect(app.ee.lock).toEqual({ code: 'EXTENSION_LOAD_FAILED' });
      const r = await ready();
      expect(r.status).toBe(503);
      expect(r.body.checks.extension).toEqual({ status: 'down', error: 'EXTENSION_LOAD_FAILED' });
      await app.close();
      app = undefined;
    }
  });

  it('an overlay that fails halfway is not served from its half-registered state', async () => {
    ({ app } = await build(HALFWAY_DIR));
    expect(app.ee.loaded).toBe(false);
    expect(app.ee.permissionResolvers).toHaveLength(1); // the half that did register
    expect(app.ee.lock).toEqual({ code: 'EXTENSION_LOAD_FAILED' });
    const res = await app.inject({ method: 'GET', url: '/api/v1/me' });
    expect(res.statusCode).toBe(503);
  });

  it('a loaded overlay is open and readiness says so', async () => {
    ({ app } = await build(FIXTURE_DIR, { ledger: [FOREIGN_MIGRATION] }));
    expect(app.ee.loaded).toBe(true);
    expect(app.ee.lock).toBeNull();
    const r = await ready();
    expect(r.status).toBe(200);
    expect(r.body.checks.extension).toEqual({ status: 'up' });
  });

  it('an unreadable ledger locks, and is asked again until it answers', async () => {
    ({ app } = await build(ABSENT_DIR, { dbOptions: { failLedgerReads: 1 } }));
    expect(app.ee.lock).toEqual({ code: 'EXTENSION_UNVERIFIED' });
    // Liveness is exempt from the lock and does not ask; readiness asks again,
    // the ledger now answers clean → open.
    const live = await app.inject({ method: 'GET', url: '/health/live' });
    expect(live.statusCode).toBe(200);
    const r = await ready();
    expect(r.status).toBe(200);
    expect(app.ee.lock).toBeNull();
  });

  it('a database that was never migrated has written nothing → open', async () => {
    ({ app } = await build(ABSENT_DIR, { dbOptions: { ledgerMissing: true } }));
    expect(app.ee.lock).toBeNull();
  });
});
