import { describe, it, expect } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

// Generous auth rate limit: these suites fire many auth calls per app instance.
const testConfig = loadConfig({ NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' });

async function appWithSession() {
  const { db, tables } = fakeDb();
  const app = await buildApp({ config: testConfig, db, redis: fakeRedis() });
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email: 'mahir@example.com', password: 'correct-horse-battery' },
  });
  expect(res.statusCode).toBe(201);
  const body = res.json();
  return { app, tables, user: body.user, refreshToken: body.tokens.refreshToken };
}

const refresh = (app, refreshToken) =>
  app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken } });
const logout = (app, refreshToken, all = false) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/auth/logout${all ? '?all=true' : ''}`,
    payload: { refreshToken },
  });

describe('POST /api/v1/auth/refresh (OPH-022)', () => {
  it('rotates through a chain: same family, old tokens retired, new one usable', async () => {
    const { app, tables, user, refreshToken: rt1 } = await appWithSession();

    const res2 = await refresh(app, rt1);
    expect(res2.statusCode).toBe(200);
    const rt2 = res2.json().tokens.refreshToken;
    expect(rt2).not.toBe(rt1);
    expect(res2.json().user.id).toBe(user.id);
    expect(app.jwt.verify(res2.json().tokens.accessToken).sub).toBe(user.id);

    const res3 = await refresh(app, rt2);
    expect(res3.statusCode).toBe(200);
    const rt3 = res3.json().tokens.refreshToken;

    expect(tables.refresh_tokens).toHaveLength(3);
    const families = new Set(tables.refresh_tokens.map((r) => r.family_id));
    expect(families.size).toBe(1); // rotation keeps the family id

    const byHash = (token) =>
      tables.refresh_tokens.find(
        (r) => r.token_hash === hashRefreshToken(token, testConfig.auth.refreshSecret),
      );
    expect(byHash(rt1).rotated_at).toBeTruthy();
    expect(byHash(rt2).rotated_at).toBeTruthy();
    expect(byHash(rt3).rotated_at).toBeFalsy();
    expect(byHash(rt3).revoked_at).toBeFalsy();

    await app.close();
  });

  it('detects reuse of a rotated token and revokes the entire family', async () => {
    const { app, tables, refreshToken: rt1 } = await appWithSession();
    const rt2 = (await refresh(app, rt1)).json().tokens.refreshToken;
    const rt3 = (await refresh(app, rt2)).json().tokens.refreshToken;

    // Attacker (or broken client) replays the first token.
    const res = await refresh(app, rt1);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_REFRESH_REUSED' });

    // The WHOLE chain is dead, including the freshest token.
    expect(tables.refresh_tokens.every((r) => r.revoked_at)).toBe(true);
    const after = await refresh(app, rt3);
    expect(after.statusCode).toBe(401);

    await app.close();
  });

  it('rejects unknown and expired tokens with AUTH_INVALID_REFRESH_TOKEN', async () => {
    const { app, tables, user } = await appWithSession();

    const unknown = await refresh(app, 'this-token-was-never-issued-by-us');
    expect(unknown.statusCode).toBe(401);
    expect(unknown.json()).toMatchObject({ code: 'AUTH_INVALID_REFRESH_TOKEN' });

    // Seed a token whose row is already past its expiry.
    const expiredToken = 'expired-token-for-oph022-tests';
    tables.refresh_tokens.push({
      id: 'row-expired',
      user_id: user.id,
      family_id: 'family-expired',
      token_hash: hashRefreshToken(expiredToken, testConfig.auth.refreshSecret),
      expires_at: new Date(Date.now() - 1000),
    });
    const expired = await refresh(app, expiredToken);
    expect(expired.statusCode).toBe(401);
    expect(expired.json()).toMatchObject({ code: 'AUTH_INVALID_REFRESH_TOKEN' });

    await app.close();
  });

  it('rejects refresh for a soft-deleted user', async () => {
    const { app, tables, refreshToken } = await appWithSession();
    tables.users[0].deleted_at = new Date();
    const res = await refresh(app, refreshToken);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_REFRESH_TOKEN' });
    await app.close();
  });
});

describe('POST /api/v1/auth/logout (OPH-022)', () => {
  it('revokes only the presented token by default', async () => {
    const { app, tables, refreshToken: registerToken } = await appWithSession();
    const login = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: 'mahir@example.com', password: 'correct-horse-battery' },
    });
    const loginToken = login.json().tokens.refreshToken;

    expect((await logout(app, loginToken)).statusCode).toBe(204);

    const secret = testConfig.auth.refreshSecret;
    const rowOf = (t) =>
      tables.refresh_tokens.find((r) => r.token_hash === hashRefreshToken(t, secret));
    expect(rowOf(loginToken).revoked_at).toBeTruthy();
    expect(rowOf(registerToken).revoked_at).toBeFalsy(); // other session untouched

    // The revoked session cannot refresh anymore (reuse path revokes, still 401).
    expect((await refresh(app, loginToken)).statusCode).toBe(401);
    expect((await refresh(app, registerToken)).statusCode).toBe(200);

    await app.close();
  });

  it('?all=true revokes the whole family after a rotation chain', async () => {
    const { app, tables, refreshToken: rt1 } = await appWithSession();
    const rt2 = (await refresh(app, rt1)).json().tokens.refreshToken;
    const rt3 = (await refresh(app, rt2)).json().tokens.refreshToken;

    expect((await logout(app, rt3, true)).statusCode).toBe(204);
    expect(tables.refresh_tokens.every((r) => r.revoked_at)).toBe(true);

    await app.close();
  });

  it('is idempotent: unknown tokens and repeat logouts still answer 204', async () => {
    const { app, refreshToken } = await appWithSession();
    expect((await logout(app, 'never-issued-token-1234567890')).statusCode).toBe(204);
    expect((await logout(app, refreshToken)).statusCode).toBe(204);
    expect((await logout(app, refreshToken)).statusCode).toBe(204);
    await app.close();
  });
});
