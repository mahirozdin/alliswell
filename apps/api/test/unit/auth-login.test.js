import { describe, it, expect } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

const testConfig = loadConfig({ NODE_ENV: 'test' });

async function appWithUser({ config = testConfig } = {}) {
  const { db, tables } = fakeDb();
  const app = await buildApp({ config, db, redis: fakeRedis() });
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: {
      email: 'mahir@example.com',
      password: 'correct-horse-battery',
      displayName: 'Mahir',
    },
  });
  expect(res.statusCode).toBe(201);
  return { app, tables, registered: res.json() };
}

function login(app, payload) {
  return app.inject({ method: 'POST', url: '/api/v1/auth/login', payload });
}

describe('POST /api/v1/auth/login (OPH-021)', () => {
  it('returns the same token/user shape as register and starts a new family', async () => {
    const { app, tables, registered } = await appWithUser();
    const res = await login(app, { email: 'mahir@example.com', password: 'correct-horse-battery' });

    expect(res.statusCode).toBe(200);
    const body = res.json();

    expect(body.user).toEqual(registered.user);
    expect(Object.keys(body.tokens).sort()).toEqual(Object.keys(registered.tokens).sort());
    const claims = app.jwt.verify(body.tokens.accessToken);
    expect(claims.sub).toBe(registered.user.id);

    // A login is a new session: second refresh-token row, in a NEW rotation family.
    expect(tables.refresh_tokens).toHaveLength(2);
    const [first, second] = tables.refresh_tokens;
    expect(second.user_id).toBe(registered.user.id);
    expect(second.family_id).not.toBe(first.family_id);
    expect(second.token_hash).not.toBe(first.token_hash);

    await app.close();
  });

  it('normalizes the email case', async () => {
    const { app } = await appWithUser();
    const res = await login(app, { email: 'MAHIR@Example.COM', password: 'correct-horse-battery' });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.email).toBe('mahir@example.com');
    await app.close();
  });

  it('rejects a wrong password with AUTH_INVALID_CREDENTIALS', async () => {
    const { app, tables } = await appWithUser();
    const res = await login(app, { email: 'mahir@example.com', password: 'wrong-password-1' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
    expect(tables.refresh_tokens).toHaveLength(1); // no new session

    await app.close();
  });

  it('rejects an unknown email with the same code (no user/pass distinction)', async () => {
    const { app } = await appWithUser();
    const res = await login(app, { email: 'nobody@example.com', password: 'whatever-pw-1' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
    await app.close();
  });

  it('rejects soft-deleted users and null-hash accounts', async () => {
    const { app, tables } = await appWithUser();

    tables.users[0].deleted_at = new Date();
    let res = await login(app, { email: 'mahir@example.com', password: 'correct-horse-battery' });
    expect(res.statusCode).toBe(401);

    tables.users[0].deleted_at = null;
    tables.users[0].password_hash = null; // future OAuth-only account
    res = await login(app, { email: 'mahir@example.com', password: 'correct-horse-battery' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });

    await app.close();
  });

  it('applies the tighter auth rate limit per IP', async () => {
    const config = loadConfig({ NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '3' });
    const { app } = await appWithUser({ config });

    const payload = { email: 'mahir@example.com', password: 'wrong-password-1' };
    // The limiter buckets per route+IP, so the register call above doesn't count
    // against /login: exactly 3 attempts pass, the 4th trips.
    for (let i = 0; i < 3; i += 1) {
      expect((await login(app, payload)).statusCode).toBe(401);
    }
    const res = await login(app, payload);
    expect(res.statusCode).toBe(429);

    await app.close();
  });
});
