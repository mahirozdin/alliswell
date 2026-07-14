import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';

// Needs real MySQL + Redis with migrations applied. This suite fires many auth
// calls, so it raises the per-route auth rate limit for its own app instance.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph022-${Date.now()}`;

describe.runIf(enabled)('integration: refresh rotation and logout', () => {
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

  async function registerUser(tag) {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-${tag}@example.com`, password: 'integration-pw-3' },
    });
    expect(res.statusCode).toBe(201);
    return res.json();
  }

  const refresh = (refreshToken) =>
    app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken } });

  it('rotates within one family and detects reuse across the chain', async () => {
    const registered = await registerUser('rotate');
    const rt1 = registered.tokens.refreshToken;

    const rt2 = (await refresh(rt1)).json().tokens.refreshToken;
    const res3 = await refresh(rt2);
    expect(res3.statusCode).toBe(200);
    const rt3 = res3.json().tokens.refreshToken;

    const rows = await app.db('refresh_tokens').where({ user_id: registered.user.id });
    expect(rows).toHaveLength(3);
    expect(new Set(rows.map((r) => r.family_id)).size).toBe(1);
    expect(rows.filter((r) => r.rotated_at === null)).toHaveLength(1);

    // Replay the first token: 401 + the whole family is revoked in the database.
    const reuse = await refresh(rt1);
    expect(reuse.statusCode).toBe(401);
    expect(reuse.json()).toMatchObject({ code: 'AUTH_REFRESH_REUSED' });

    const afterRows = await app.db('refresh_tokens').where({ user_id: registered.user.id });
    expect(afterRows.every((r) => r.revoked_at !== null)).toBe(true);
    expect((await refresh(rt3)).statusCode).toBe(401);
  });

  it('logout revokes one session; ?all=true revokes the family', async () => {
    const registered = await registerUser('logout');
    const rt1 = registered.tokens.refreshToken;
    const rt2 = (await refresh(rt1)).json().tokens.refreshToken;

    // Single logout on the active token.
    const single = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: rt2 },
    });
    expect(single.statusCode).toBe(204);
    expect((await refresh(rt2)).statusCode).toBe(401);

    // New session, rotate once, then logout-all with the newest token.
    const login = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: `${emailPrefix}-logout@example.com`, password: 'integration-pw-3' },
    });
    const lt1 = login.json().tokens.refreshToken;
    const lt2 = (await refresh(lt1)).json().tokens.refreshToken;

    const all = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout?all=true',
      payload: { refreshToken: lt2 },
    });
    expect(all.statusCode).toBe(204);

    // The login family is fully revoked — but the register family's rotated (not
    // revoked) rt1 is untouched: single logout and logout-all stay family-scoped.
    const lt1Row = await app
      .db('refresh_tokens')
      .where({ token_hash: hashRefreshToken(lt1, app.config.auth.refreshSecret) })
      .first();
    const activeInLoginFamily = await app
      .db('refresh_tokens')
      .where({ family_id: lt1Row.family_id })
      .whereNull('revoked_at');
    expect(activeInLoginFamily).toHaveLength(0);
  });
});
