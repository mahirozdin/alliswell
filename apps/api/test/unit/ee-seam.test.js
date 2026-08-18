import { describe, it, expect, afterEach } from 'vitest';
import { fileURLToPath } from 'node:url';

import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fullDance, callTool } from '../helpers/mcpdance.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

/**
 * EE-002 — the enterprise overlay seam. The contract under test: absent
 * overlay = CE byte for byte; a fixture overlay can use every hook (route,
 * sync pull + push, MCP tool, permission collection, core-route reach); a
 * broken overlay fails open to CE loudly, never fatally.
 */

const FIXTURE_DIR = fileURLToPath(new URL('../fixtures/ee-overlay', import.meta.url));
const BROKEN_DIR = fileURLToPath(new URL('../fixtures/ee-overlay-broken', import.meta.url));

const eeConfig = (dir) =>
  loadConfig({ NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000', EE_ENABLED: '1', EE_DIR: dir });

const CLIENT_ID = newId();

let app;

afterEach(async () => {
  await app?.close();
});

describe('EE overlay seam (EE-002)', () => {
  it('is CE by default under test env: no overlay, no routes, no marker', async () => {
    ({ app } = await buildTestApp());
    expect(app.ee).toMatchObject({ enabled: false, loaded: false, error: null });
    const probe = await app.inject({ method: 'GET', url: '/api/v1/__seam-probe' });
    expect(probe.statusCode).toBe(404);
    const health = await app.inject({ method: 'GET', url: '/health/live' });
    expect(health.headers['x-seam-probe']).toBeUndefined();
  });

  it('enabled without a checkout still boots as CE (absence is not an error)', async () => {
    ({ app } = await buildTestApp({ config: eeConfig('/nonexistent/overlay') }));
    expect(app.ee).toMatchObject({ enabled: true, loaded: false, error: null });
    const health = await app.inject({ method: 'GET', url: '/health/live' });
    expect(health.statusCode).toBe(200);
  });

  it('loads the fixture overlay: route answers, hooks reach core routes', async () => {
    ({ app } = await buildTestApp({ config: eeConfig(FIXTURE_DIR) }));
    expect(app.ee.loaded).toBe(true);
    const probe = await app.inject({ method: 'GET', url: '/api/v1/__seam-probe' });
    expect(probe.statusCode).toBe(200);
    expect(probe.json()).toMatchObject({ ok: true, source: 'overlay' });
    // The ordering guarantee: an overlay hook fires on a CORE route.
    const health = await app.inject({ method: 'GET', url: '/health/live' });
    expect(health.headers['x-seam-probe']).toBe('1');
    expect(app.ee.permissions).toEqual([expect.objectContaining({ id: 'probe.view' })]);
  });

  it('flows an overlay sync entity through /sync/pull', async () => {
    ({ app } = await buildTestApp({ config: eeConfig(FIXTURE_DIR) }));
    const owner = await registerUser(app, { email: 'seam@example.com' });
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/__seam-probe/${owner.workspace.id}`,
      headers: owner.headers,
    });
    expect(created.statusCode).toBe(200);
    const { id } = created.json();

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=0`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    const change = res.json().changes.find((c) => c.entityType === 'seam_probe');
    expect(change).toMatchObject({
      entityId: id,
      operation: 'create',
      data: { id, title: 'probe' },
    });
  });

  it('applies an overlay push entity; the same push is unsupported without the overlay', async () => {
    const pushProbe = (headers, workspaceId) =>
      app.inject({
        method: 'POST',
        url: '/api/v1/sync/push',
        headers,
        payload: {
          clientId: CLIENT_ID, // ULID — the push schema types clientId as one
          workspaceId,
          baseRevision: 0,
          mutations: [
            {
              clientMutationId: newId(),
              entityType: 'seam_probe',
              entityId: newId(),
              operation: 'create',
              patch: { title: 'pushed' },
            },
          ],
        },
      });

    ({ app } = await buildTestApp({
      config: eeConfig(FIXTURE_DIR),
      dbOptions: { extraTables: ['seam_probes'] },
    }));
    const owner = await registerUser(app, { email: 'seam-push@example.com' });
    const applied = await pushProbe(owner.headers, owner.workspace.id);
    expect(applied.statusCode).toBe(200);
    expect(applied.json().results[0]).toMatchObject({ status: 'applied' });
    await app.close();

    ({ app } = await buildTestApp());
    const ceOwner = await registerUser(app, { email: 'seam-ce@example.com' });
    const refused = await pushProbe(ceOwner.headers, ceOwner.workspace.id);
    expect(refused.statusCode).toBe(200);
    expect(refused.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNSUPPORTED_ENTITY',
    });
  });

  it('lists and calls an overlay MCP tool through the full dance', async () => {
    ({ app } = await buildTestApp({ config: eeConfig(FIXTURE_DIR) }));
    await registerUser(app, { email: 'seam-mcp@example.com' });
    const { tokens } = await fullDance(app, { email: 'seam-mcp@example.com' });
    const result = await callTool(app, tokens.access_token, 'seam_probe_tool', {});
    expect(result.isError).toBeFalsy();
    expect(result.structuredContent).toEqual({ ok: true });
  });

  it('fails open to CE when the overlay is broken — loudly, not fatally', async () => {
    ({ app } = await buildTestApp({ config: eeConfig(BROKEN_DIR) }));
    expect(app.ee.loaded).toBe(false);
    expect(app.ee.error).toMatch(/already taken/);
    const health = await app.inject({ method: 'GET', url: '/health/live' });
    expect(health.statusCode).toBe(200);
  });
});
