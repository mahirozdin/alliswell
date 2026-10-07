import { describe, it, expect } from 'vitest';
import { createSigner } from 'fast-jwt';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { credentialRateKey, identityRateKey } from '../../src/lib/rate-limit.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

async function bootApp(env = {}) {
  const { db, tables } = fakeDb();
  const app = await buildApp({
    config: loadConfig({ NODE_ENV: 'test', ...env }),
    db,
    redis: fakeRedis(),
  });
  await app.ready();
  return { app, tables };
}

async function register(app, email, ip = '10.0.0.1') {
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    remoteAddress: ip,
    payload: { email, password: 'correct-horse-battery', displayName: email.split('@')[0] },
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

const login = (app, payload, ip = '10.0.0.1') =>
  app.inject({ method: 'POST', url: '/api/v1/auth/login', remoteAddress: ip, payload });

const me = (app, token, ip = '10.0.0.1') =>
  app.inject({
    method: 'GET',
    url: '/api/v1/me',
    remoteAddress: ip,
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });

const fakeRequest = (headers = {}, extra = {}) => ({ headers, ip: '10.0.0.1', ...extra });

describe('rate-limit keys (OPH-357, ADR-0045)', () => {
  it('UI-AUDIT #25: a verified access token is its user; anything unproven is the IP', async () => {
    const { app } = await bootApp();
    const token = app.signAccessToken({ id: '01USERAAAAAAAAAAAAAAAAAAAA', email: 'a@example.com' });
    expect(identityRateKey(app, fakeRequest({ authorization: `Bearer ${token}` }))).toBe(
      'user:01USERAAAAAAAAAAAAAAAAAAAA',
    );

    // Signed with another secret: no bucket of its own.
    const forged = createSigner({
      key: 'not-the-secret',
      iss: 'alliswell-api',
      aud: 'alliswell-app',
    })({ sub: '01USERBBBBBBBBBBBBBBBBBBBB' });
    expect(identityRateKey(app, fakeRequest({ authorization: `Bearer ${forged}` }))).toBe(
      'ip:10.0.0.1',
    );
    // Expired: the same.
    const expired = createSigner({
      key: app.config.auth.accessSecret,
      iss: 'alliswell-api',
      aud: 'alliswell-app',
      expiresIn: 1,
      clockTimestamp: Date.now() - 60_000,
    })({ sub: '01USERCCCCCCCCCCCCCCCCCCCC' });
    expect(identityRateKey(app, fakeRequest({ authorization: `Bearer ${expired}` }))).toBe(
      'ip:10.0.0.1',
    );
    expect(identityRateKey(app, fakeRequest())).toBe('ip:10.0.0.1');
    // API keys keep their own bucket (ADR-0032 §5).
    expect(identityRateKey(app, fakeRequest({ authorization: 'Bearer awk_abc' }))).toMatch(
      /^apikey:[0-9a-f]{64}$/,
    );

    await app.close();
  });

  it('UI-AUDIT #25: a credential request counts per IP + account, case-insensitively', () => {
    const a = credentialRateKey(fakeRequest({}, { body: { email: 'Ali@Example.com' } }));
    const a2 = credentialRateKey(fakeRequest({}, { body: { email: 'ali@example.com' } }));
    const b = credentialRateKey(fakeRequest({}, { body: { email: 'veli@example.com' } }));
    const other = credentialRateKey(
      fakeRequest({}, { body: { email: 'ali@example.com' }, ip: '10.9.9.9' }),
    );
    expect(a).toBe(a2);
    expect(a).not.toBe(b);
    expect(a).not.toBe(other);
    // The address never becomes a bucket name.
    expect(a).not.toMatch(/ali/i);
  });

  it('UI-AUDIT #25: twelve people behind one NAT sign in within a minute', async () => {
    const { app } = await bootApp({ RATE_LIMIT_AUTH_MAX: '10' });
    const people = Array.from({ length: 12 }, (_, i) => `worker${i}@example.com`);
    // Registering from elsewhere: only the shift-start logins share the address.
    for (const [i, email] of people.entries()) await register(app, email, `10.1.0.${i + 1}`);

    for (const email of people) {
      const res = await login(app, { email, password: 'correct-horse-battery' }, '203.0.113.7');
      expect(res.statusCode).toBe(200);
    }

    await app.close();
  });

  it('UI-AUDIT #25: one account with eleven wrong passwords still gets RATE_LIMITED', async () => {
    const { app } = await bootApp({ RATE_LIMIT_AUTH_MAX: '10' });
    await register(app, 'ali@example.com', '10.1.0.1');

    const wrong = { email: 'ali@example.com', password: 'nope-nope-nope' };
    for (let i = 0; i < 10; i += 1) {
      expect((await login(app, wrong, '203.0.113.7')).statusCode).toBe(401);
    }
    const res = await login(app, wrong, '203.0.113.7');
    expect(res.statusCode).toBe(429);
    const body = res.json();
    expect(body).toMatchObject({
      statusCode: 429,
      code: 'RATE_LIMITED',
      error: 'Too Many Requests',
    });
    expect(Number.isInteger(body.retryAfter)).toBe(true);
    expect(body.retryAfter).toBeGreaterThan(0);
    expect(body.retryAfter).toBeLessThanOrEqual(60);
    expect(Number(res.headers['retry-after'])).toBe(body.retryAfter);
    // The capital letters are the same account.
    const shouted = await login(app, { ...wrong, email: 'ALI@example.com' }, '203.0.113.7');
    expect(shouted.statusCode).toBe(429);

    await app.close();
  });

  it('UI-AUDIT #25: spraying many accounts from one address hits the per-IP ceiling', async () => {
    const { app } = await bootApp({ RATE_LIMIT_AUTH_MAX: '10', RATE_LIMIT_AUTH_IP_MAX: '5' });
    for (let i = 0; i < 5; i += 1) {
      const res = await login(
        app,
        { email: `nobody${i}@example.com`, password: 'x' },
        '198.51.100.1',
      );
      expect(res.statusCode).toBe(401);
    }
    const res = await login(app, { email: 'nobody9@example.com', password: 'x' }, '198.51.100.1');
    expect(res.statusCode).toBe(429);
    expect(res.json()).toMatchObject({ code: 'RATE_LIMITED' });
    expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
    // Another address is not affected.
    const elsewhere = await login(
      app,
      { email: 'nobody9@example.com', password: 'x' },
      '198.51.100.2',
    );
    expect(elsewhere.statusCode).toBe(401);

    await app.close();
  });

  it('UI-AUDIT #25 / D3: signed-in traffic counts per user, not per shared IP', async () => {
    const { app } = await bootApp({ RATE_LIMIT_MAX: '3', RATE_LIMIT_AUTH_MAX: '100' });
    const a = await register(app, 'a@example.com');
    const b = await register(app, 'b@example.com');

    for (let i = 0; i < 3; i += 1) {
      expect((await me(app, a.tokens.accessToken, '203.0.113.7')).statusCode).toBe(200);
    }
    const limited = await me(app, a.tokens.accessToken, '203.0.113.7');
    expect(limited.statusCode).toBe(429);
    expect(limited.json()).toMatchObject({ code: 'RATE_LIMITED' });
    expect(limited.headers['retry-after']).toBeDefined();

    // Same address, other person: their own budget.
    expect((await me(app, b.tokens.accessToken, '203.0.113.7')).statusCode).toBe(200);
    // The same person from another address is still the same person.
    expect((await me(app, a.tokens.accessToken, '198.51.100.9')).statusCode).toBe(429);

    await app.close();
  });

  it('UI-AUDIT #25: a forged token cannot mint a fresh bucket', async () => {
    const { app } = await bootApp({ RATE_LIMIT_MAX: '2' });
    const forge = (sub) =>
      createSigner({ key: 'not-the-secret', iss: 'alliswell-api', aud: 'alliswell-app' })({ sub });
    // A route without its own guard, so the limiter is what answers.
    const root = (token) =>
      app.inject({
        method: 'GET',
        url: '/',
        remoteAddress: '198.51.100.3',
        headers: { authorization: `Bearer ${token}` },
      });

    expect((await root(forge('01AAAAAAAAAAAAAAAAAAAAAAAA'))).statusCode).toBe(200);
    expect((await root(forge('01BBBBBBBBBBBBBBBBBBBBBBBB'))).statusCode).toBe(200);
    const third = await root(forge('01CCCCCCCCCCCCCCCCCCCCCCCC'));
    expect(third.statusCode).toBe(429);
    expect(third.json().code).toBe('RATE_LIMITED');

    await app.close();
  });
});
