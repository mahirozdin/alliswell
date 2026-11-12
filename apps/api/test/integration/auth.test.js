import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';
import { resetJwksCacheForTest } from '../../src/lib/oauth-identity.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';
import { localProviderKeys, signIdToken } from '../helpers/idtoken.js';

// Needs real MySQL + Redis with migrations applied (see test/integration/ready.test.js).
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph020-${Date.now()}`;

describe.runIf(enabled)('integration: POST /api/v1/auth/register', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
  });

  afterAll(async () => {
    if (!app) return;
    // Workspaces first (owner FK is RESTRICT); deleting users cascades members + tokens.
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('registers a user and persists workspace, membership and hashed refresh token', async () => {
    const email = `${emailPrefix}-happy@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'integration-pw-1', displayName: 'Integration Kişi' },
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();

    // The issued access token is verifiable by the server (acceptance: usable immediately).
    const claims = app.jwt.verify(body.tokens.accessToken);
    expect(claims.sub).toBe(body.user.id);

    const user = await app.db('users').where({ id: body.user.id }).first();
    expect(user.email).toBe(email);
    expect(user.password_hash).toMatch(/^\$argon2id\$/);
    expect(user.created_at).toBeTruthy();

    const workspace = await app.db('workspaces').where({ id: body.workspace.id }).first();
    expect(workspace.owner_id).toBe(body.user.id);
    expect(workspace.name).toBe("Integration Kişi's Space");

    const member = await app
      .db('workspace_members')
      .where({ workspace_id: body.workspace.id, user_id: body.user.id })
      .first();
    expect(member.role).toBe('owner');

    const token = await app.db('refresh_tokens').where({ user_id: body.user.id }).first();
    expect(token.token_hash).toBe(
      hashRefreshToken(body.tokens.refreshToken, app.config.auth.refreshSecret),
    );
    expect(new Date(token.expires_at).getTime()).toBeGreaterThan(Date.now());
  });

  it('rejects a duplicate email with 409 AUTH_EMAIL_TAKEN and leaves a single user row', async () => {
    const email = `${emailPrefix}-dup@example.com`;
    const payload = { email, password: 'integration-pw-2' };

    expect(
      (await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload })).statusCode,
    ).toBe(201);

    const res = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'AUTH_EMAIL_TAKEN' });

    const rows = await app.db('users').where({ email });
    expect(rows).toHaveLength(1);
  });

  it('rejects weak passwords with 400 and writes nothing', async () => {
    const email = `${emailPrefix}-weak@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'seven77' },
    });
    expect(res.statusCode).toBe(400);
    expect(await app.db('users').where({ email })).toHaveLength(0);
  });

  describe('POST /api/v1/auth/login (OPH-021)', () => {
    const email = `${emailPrefix}-login@example.com`;
    const password = 'login-integration-pw';

    beforeAll(async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { email, password },
      });
      expect(res.statusCode).toBe(201);
    });

    it('logs in and persists a second refresh-token family', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/login',
        payload: { email, password },
      });
      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(app.jwt.verify(body.tokens.accessToken).sub).toBe(body.user.id);

      const rows = await app.db('refresh_tokens').where({ user_id: body.user.id });
      expect(rows).toHaveLength(2);
      expect(rows[0].family_id).not.toBe(rows[1].family_id);
    });

    it('rejects wrong password and unknown email with AUTH_INVALID_CREDENTIALS', async () => {
      for (const payload of [
        { email, password: 'definitely-wrong-1' },
        { email: `${emailPrefix}-ghost@example.com`, password },
      ]) {
        const res = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload });
        expect(res.statusCode).toBe(401);
        expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
      }
    });
  });
});

// OPH-434 (#48) — every sign-in door accepts an optional `deviceId` and binds
// the family it creates to that notification device. A client that sends none
// gets exactly what it got before: an unbound family.
describe.runIf(enabled)('integration: sign-in binds the family to a device (OPH-434)', () => {
  const WEB = 'web.apps.googleusercontent.com';
  const prefix = `${emailPrefix}-bind`;
  let app;
  let key;

  const post = (path, payload) =>
    app.inject({ method: 'POST', url: `/api/v1/auth/${path}`, payload });

  const rowOf = (token) =>
    app
      .db('refresh_tokens')
      .where({ token_hash: hashRefreshToken(token, app.config.auth.refreshSecret) })
      .first();

  const oauthAs = async (subject, extra = {}) =>
    post('oauth', {
      provider: 'google',
      idToken: await signIdToken(key, {
        audience: WEB,
        subject,
        email: `${prefix}-${subject}@example.com`,
        emailVerified: true,
      }),
      ...extra,
    });

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '1000',
        SIGN_IN_GOOGLE_WEB_CLIENT_ID: WEB,
      }),
    });
    key = await localProviderKeys(['google']);
  });

  afterAll(async () => {
    resetJwksCacheForTest();
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${prefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('user_identities').whereIn('user_id', ids).delete();
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('login with deviceId binds the new family', async () => {
    const email = `${prefix}-login@example.com`;
    const password = 'bind-integration-pw';
    const registered = await post('register', { email, password });
    expect(registered.statusCode).toBe(201);
    expect((await rowOf(registered.json().tokens.refreshToken)).device_id).toBeNull();

    const device = newId();
    const res = await post('login', { email, password, deviceId: device });
    expect(res.statusCode).toBe(200);
    const row = await rowOf(res.json().tokens.refreshToken);
    expect(row.device_id).toBe(device);

    // The family the earlier sign-in started is a different session: untouched.
    const older = await rowOf(registered.json().tokens.refreshToken);
    expect(older.family_id).not.toBe(row.family_id);
    expect(older.device_id).toBeNull();

    // And a login without the field still starts an unbound family.
    const plain = await post('login', { email, password });
    expect(plain.statusCode).toBe(200);
    expect((await rowOf(plain.json().tokens.refreshToken)).device_id).toBeNull();
  });

  it('register and oauth accept deviceId', async () => {
    const registerDevice = newId();
    const registered = await post('register', {
      email: `${prefix}-register@example.com`,
      password: 'bind-integration-pw',
      deviceId: registerDevice,
    });
    expect(registered.statusCode).toBe(201);
    expect((await rowOf(registered.json().tokens.refreshToken)).device_id).toBe(registerDevice);

    // A new account through the provider…
    const createdDevice = newId();
    const created = await oauthAs('g-new', { deviceId: createdDevice });
    expect(created.statusCode).toBe(201);
    expect((await rowOf(created.json().tokens.refreshToken)).device_id).toBe(createdDevice);

    // …the same identity signing in again on another device…
    const knownDevice = newId();
    const known = await oauthAs('g-new', { deviceId: knownDevice });
    expect(known.statusCode).toBe(200);
    expect((await rowOf(known.json().tokens.refreshToken)).device_id).toBe(knownDevice);

    // …and a verified address linking onto the password account above.
    const linkDevice = newId();
    const linked = await oauthAs('register', { deviceId: linkDevice });
    expect(linked.statusCode).toBe(200);
    expect(linked.json().user.id).toBe(registered.json().user.id);
    expect((await rowOf(linked.json().tokens.refreshToken)).device_id).toBe(linkDevice);
  });

  it('deviceId that is not a ULID is rejected with 400', async () => {
    const email = `${prefix}-reject@example.com`;
    const password = 'bind-integration-pw';
    const bad = ['not-a-ulid', '01arz3ndektsv4rrffq69g5fav', newId().slice(1), `${newId()}X`, 7];

    for (const deviceId of bad) {
      const res = await post('register', { email, password, deviceId });
      expect(res.statusCode).toBe(400);
    }
    // A refused registration wrote nothing.
    expect(await app.db('users').where({ email }).first('id')).toBeUndefined();

    expect((await post('register', { email, password })).statusCode).toBe(201);
    const [{ before }] = await app
      .db('refresh_tokens')
      .join('users', 'users.id', 'refresh_tokens.user_id')
      .where('users.email', email)
      .count({ before: '*' });
    for (const deviceId of bad) {
      expect((await post('login', { email, password, deviceId })).statusCode).toBe(400);
      expect((await oauthAs('g-reject', { deviceId })).statusCode).toBe(400);
    }
    const [{ after }] = await app
      .db('refresh_tokens')
      .join('users', 'users.id', 'refresh_tokens.user_id')
      .where('users.email', email)
      .count({ after: '*' });
    expect(Number(after)).toBe(Number(before));
    expect(
      await app
        .db('users')
        .where({ email: `${prefix}-g-reject@example.com` })
        .first('id'),
    ).toBeUndefined();
  });
});
