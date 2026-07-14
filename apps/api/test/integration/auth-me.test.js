import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph023-${Date.now()}`;

describe.runIf(enabled)('integration: GET /api/v1/me (Epic 03 acceptance)', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('register → immediately call an authenticated endpoint → refresh → call again', async () => {
    const email = `${emailPrefix}-acceptance@example.com`;
    const registered = (
      await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { email, password: 'acceptance-pw-1', displayName: 'Kabul Testi' },
      })
    ).json();

    // Epic 03 acceptance: the register response's access token works right away.
    const first = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
      headers: { authorization: `Bearer ${registered.tokens.accessToken}` },
    });
    expect(first.statusCode).toBe(200);
    expect(first.json().user).toMatchObject({ id: registered.user.id, email });
    expect(first.json().workspaces).toEqual([
      expect.objectContaining({ id: registered.workspace.id, role: 'owner' }),
    ]);

    // Rotate the session and use the NEW access token.
    const refreshed = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: registered.tokens.refreshToken },
    });
    expect(refreshed.statusCode).toBe(200);
    const second = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
      headers: { authorization: `Bearer ${refreshed.json().tokens.accessToken}` },
    });
    expect(second.statusCode).toBe(200);
    expect(second.json().user.id).toBe(registered.user.id);
  });

  it('rejects unauthenticated and cross-signed requests', async () => {
    expect((await app.inject({ method: 'GET', url: '/api/v1/me' })).statusCode).toBe(401);
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
      headers: { authorization: 'Bearer definitely.not.valid' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_TOKEN' });
  });
});
