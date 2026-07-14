import { describe, it, expect } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

const testConfig = loadConfig({ NODE_ENV: 'test' });

async function buildTestApp(dbOptions) {
  const { db, tables } = fakeDb(dbOptions);
  const app = await buildApp({ config: testConfig, db, redis: fakeRedis() });
  return { app, tables };
}

function register(app, payload) {
  return app.inject({ method: 'POST', url: '/api/v1/auth/register', payload });
}

describe('POST /api/v1/auth/register (OPH-020)', () => {
  it('creates user, personal workspace, owner membership and a session', async () => {
    const { app, tables } = await buildTestApp();
    const res = await register(app, {
      email: 'mahir@example.com',
      password: 'correct-horse-battery',
      displayName: 'Mahir',
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();

    expect(body.user).toMatchObject({ email: 'mahir@example.com', displayName: 'Mahir' });
    expect(body.workspace.name).toBe("Mahir's Space");
    expect(body.workspace.slug).toMatch(/^mahir-s-space-[0-9a-f]{8}$/);

    // Access token: verifiable JWT, correct claims, 15-minute lifetime.
    const claims = app.jwt.verify(body.tokens.accessToken);
    expect(claims.sub).toBe(body.user.id);
    expect(claims.email).toBe('mahir@example.com');
    expect(claims.iss).toBe('alliswell-api');
    expect(claims.aud).toBe('alliswell-app');
    expect(claims.exp - claims.iat).toBe(900);
    expect(body.tokens.accessTokenExpiresInSec).toBe(900);

    // Refresh token: opaque, returned raw, stored only as an HMAC hash.
    expect(body.tokens.refreshToken).toMatch(/^[A-Za-z0-9_-]{64}$/);
    expect(tables.refresh_tokens).toHaveLength(1);
    const stored = tables.refresh_tokens[0];
    expect(stored.token_hash).toBe(
      hashRefreshToken(body.tokens.refreshToken, testConfig.auth.refreshSecret),
    );
    expect(stored.token_hash).not.toContain(body.tokens.refreshToken);
    expect(stored.user_id).toBe(body.user.id);
    expect(stored.family_id).toBeDefined();
    const msUntilExpiry = new Date(body.tokens.refreshTokenExpiresAt).getTime() - Date.now();
    expect(msUntilExpiry).toBeGreaterThan(29 * 24 * 60 * 60 * 1000);
    expect(msUntilExpiry).toBeLessThanOrEqual(30 * 24 * 60 * 60 * 1000);

    // Rows created in one logical write: argon2id hash, owner membership.
    expect(tables.users).toHaveLength(1);
    expect(tables.users[0].password_hash).toMatch(/^\$argon2id\$/);
    expect(tables.users[0].password_hash).not.toContain('correct-horse-battery');
    expect(tables.workspaces[0]).toMatchObject({ owner_id: body.user.id, name: "Mahir's Space" });
    expect(tables.workspace_members[0]).toMatchObject({
      workspace_id: body.workspace.id,
      user_id: body.user.id,
      role: 'owner',
    });

    await app.close();
  });

  it('lowercases the email and derives names from the local part without displayName', async () => {
    const { app, tables } = await buildTestApp();
    const res = await register(app, {
      email: 'Ayse.Yilmaz@Example.COM',
      password: 'long-enough-pw',
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.user.email).toBe('ayse.yilmaz@example.com');
    expect(body.user.displayName).toBeNull();
    expect(body.workspace.name).toBe("ayse.yilmaz's Space");
    expect(tables.users[0].email).toBe('ayse.yilmaz@example.com');

    await app.close();
  });

  it('rejects a duplicate email with AUTH_EMAIL_TAKEN (case-insensitive)', async () => {
    const { app } = await buildTestApp();
    expect(
      (await register(app, { email: 'dup@example.com', password: 'password-123' })).statusCode,
    ).toBe(201);

    const res = await register(app, { email: 'DUP@example.com', password: 'password-456' });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'AUTH_EMAIL_TAKEN' });

    await app.close();
  });

  it('maps a lost unique-index race to AUTH_EMAIL_TAKEN as well', async () => {
    // Pre-check sees nothing, the INSERT hits uq_users_email — like two concurrent registers.
    const { app } = await buildTestApp({ hideUsersFromPrecheck: true });
    expect(
      (await register(app, { email: 'race@example.com', password: 'password-123' })).statusCode,
    ).toBe(201);

    const res = await register(app, { email: 'race@example.com', password: 'password-456' });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'AUTH_EMAIL_TAKEN' });

    await app.close();
  });

  it('rejects invalid payloads with 400 before touching the database', async () => {
    const { app, tables } = await buildTestApp();

    const cases = [
      { email: 'weak@example.com', password: 'seven77' }, // < 8 chars
      { email: 'not-an-email', password: 'long-enough-pw' },
      { password: 'long-enough-pw' }, // missing email
      { email: 'x@example.com' }, // missing password
      { email: 'x@example.com', password: 'long-enough-pw', displayName: '' },
    ];
    // (Unknown body properties are silently stripped — Fastify's default Ajv
    // uses removeAdditional with `additionalProperties: false` — not rejected.)
    for (const payload of cases) {
      const res = await register(app, payload);
      expect(res.statusCode, JSON.stringify(payload)).toBe(400);
    }
    expect(tables.users).toHaveLength(0);

    await app.close();
  });
});
