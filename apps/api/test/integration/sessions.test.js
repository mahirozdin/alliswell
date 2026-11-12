import { describe, it, expect, beforeAll, afterAll } from 'vitest';

import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

const enabled = process.env.INTEGRATION === '1';
const emailPrefix = `oph284-${Date.now()}`;

/// OPH-284 — "where am I signed in?", and closing one of them.
///
/// The claim this suite has to defend is the one a session screen makes by
/// existing: that the list is what a person means by sessions, and that
/// closing one actually ends it. Both are easy to get wrong in the same
/// direction — a list of token ROWS looks right until somebody's phone has
/// refreshed a hundred times, and revoking one ROW looks right until the
/// client refreshes and carries on.
describe.runIf(enabled)('integration: sessions', () => {
  let app;
  let user;

  const register = (email, headers = {}) =>
    app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      headers,
      payload: { email, password: 'integration-pw-1', displayName: 'Ada' },
    });

  const login = (headers = {}) =>
    app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      headers,
      payload: { email: user.email, password: 'integration-pw-1' },
    });

  const refresh = (refreshToken) =>
    app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken } });

  const sessions = (query = '') =>
    app.inject({
      method: 'GET',
      url: `/api/v1/auth/sessions${query}`,
      headers: { authorization: `Bearer ${user.accessToken}` },
    });

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000' }),
    });
    const res = await register(`${emailPrefix}-ada@example.com`, {
      'user-agent': 'FirstDevice/1.0',
    });
    const body = res.json();
    user = {
      id: body.user.id,
      email: body.user.email,
      accessToken: body.tokens.accessToken,
      refreshToken: body.tokens.refreshToken,
    };
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

  it('records the device that signed in — the column existed and nothing wrote to it', async () => {
    const list = (await sessions()).json();
    expect(list).toHaveLength(1);
    expect(list[0].deviceName).toBe('FirstDevice/1.0');
    expect(list[0].createdIp).toBeTruthy();
  });

  it('a refresh is a ROTATION, not a new session', async () => {
    // The trap this whole design exists to avoid: rows accumulate, sessions
    // must not. One sign-in that has refreshed twice is still one session.
    const first = await refresh(user.refreshToken);
    expect(first.statusCode).toBe(200);
    const second = await refresh(first.json().tokens.refreshToken);
    expect(second.statusCode).toBe(200);
    user.refreshToken = second.json().tokens.refreshToken;

    const rows = await app.db('refresh_tokens').where({ user_id: user.id });
    expect(rows.length).toBe(3); // three rows...

    const list = (await sessions()).json();
    expect(list).toHaveLength(1); // ...one session.
    // And the session's "last seen" moved, which is what the rotation is for.
    expect(list[0].lastSeenAt > list[0].createdAt).toBe(true);
  });

  it('a second sign-in is a second session, and each names its own device', async () => {
    const other = await login({ 'user-agent': 'SecondDevice/2.0' });
    expect(other.statusCode).toBe(200);
    user.otherRefreshToken = other.json().tokens.refreshToken;

    const list = (await sessions()).json();
    expect(list).toHaveLength(2);
    expect(list.map((s) => s.deviceName).sort()).toEqual(['FirstDevice/1.0', 'SecondDevice/2.0']);
  });

  it('the caller can have their own session marked, by naming it', async () => {
    // An access token carries no family claim on purpose, so the caller says
    // which session is theirs by presenting its refresh token.
    const list = (await sessions(`?refreshToken=${encodeURIComponent(user.refreshToken)}`)).json();
    const current = list.filter((s) => s.current);
    expect(current).toHaveLength(1);
    expect(current[0].deviceName).toBe('FirstDevice/1.0');
  });

  // ── The acceptance ──────────────────────────────────────────────────────
  it('closing a session KILLS ITS REFRESH — the whole point', async () => {
    const list = (await sessions()).json();
    const target = list.find((s) => s.deviceName === 'SecondDevice/2.0');

    const closed = await app.inject({
      method: 'DELETE',
      url: `/api/v1/auth/sessions/${target.id}`,
      headers: { authorization: `Bearer ${user.accessToken}` },
    });
    expect(closed.statusCode).toBe(204);

    // The refresh token that session was holding is now worthless.
    const dead = await refresh(user.otherRefreshToken);
    expect(dead.statusCode).toBe(401);

    // And it is gone from the list rather than shown greyed out.
    expect((await sessions()).json()).toHaveLength(1);
  });

  it("closing a session that is not yours is a 404, not somebody else's logout", async () => {
    const stranger = await register(`${emailPrefix}-bob@example.com`);
    const strangerBody = stranger.json();
    const strangerFamily = (
      await app.db('refresh_tokens').where({ user_id: strangerBody.user.id }).first('family_id')
    ).family_id;

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/auth/sessions/${strangerFamily}`,
      headers: { authorization: `Bearer ${user.accessToken}` },
    });
    expect(res.statusCode).toBe(404);

    // Untouched: knowing a family id must not be enough to end a session.
    expect((await refresh(strangerBody.tokens.refreshToken)).statusCode).toBe(200);
  });

  it('"sign me out everywhere else" keeps exactly the session you named', async () => {
    await login({ 'user-agent': 'ThirdDevice/3.0' });
    await login({ 'user-agent': 'FourthDevice/4.0' });
    expect((await sessions()).json().length).toBe(3);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/sessions/revoke-others',
      headers: { authorization: `Bearer ${user.accessToken}` },
      payload: { refreshToken: user.refreshToken },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().revoked).toBeGreaterThan(0);

    const left = (await sessions()).json();
    expect(left).toHaveLength(1);
    expect(left[0].deviceName).toBe('FirstDevice/1.0');
    // The one that was kept still works.
    expect((await refresh(user.refreshToken)).statusCode).toBe(200);
  });
});

/// OPH-435 (#48) — the reverse direction: a session that ends takes the
/// notification device bound to it (`refresh_tokens.device_id`, OPH-434) with
/// it, so a signed-out install stops receiving fallback pushes. Fresh
/// accounts per test, so the counts never depend on test order.
describe.runIf(enabled)('integration: ending a session removes its device (OPH-435)', () => {
  let app;
  let seq = 0;
  const prefix = `${emailPrefix}-oph435`;
  const PASSWORD = 'integration-pw-1';

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000' }),
    });
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${prefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  const session = (body, email) => ({
    id: body.user.id,
    email,
    refreshToken: body.tokens.refreshToken,
    headers: { authorization: `Bearer ${body.tokens.accessToken}` },
  });

  /** A fresh account whose first session is bound to `deviceId`, registered as a device. */
  const account = async (deviceId) => {
    seq += 1;
    const email = `${prefix}-${seq}@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: PASSWORD, deviceId },
    });
    expect(res.statusCode).toBe(201);
    const s = session(res.json(), email);
    await putDevice(s, deviceId);
    return s;
  };

  /** Another sign-in of the same account on `deviceId`, registered as a device. */
  const signIn = async (user, deviceId) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: user.email, password: PASSWORD, deviceId },
    });
    expect(res.statusCode).toBe(200);
    const s = session(res.json(), user.email);
    await putDevice(s, deviceId);
    return s;
  };

  const putDevice = async (s, deviceId) => {
    const res = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: s.headers,
      payload: { platform: 'android' },
    });
    expect([200, 201]).toContain(res.statusCode);
  };

  const devices = async (userId) =>
    (await app.db('notification_devices').where({ user_id: userId }).select('id'))
      .map((r) => r.id)
      .sort();

  const liveFamilies = (userId) =>
    app
      .db('refresh_tokens')
      .where({ user_id: userId })
      .whereNull('revoked_at')
      .whereNull('rotated_at')
      .select('family_id', 'device_id');

  it('revoking a session removes the notification device bound to it', async () => {
    const mine = newId();
    const phone = newId();
    const me = await account(mine);
    await signIn(me, phone);
    const phoneFamily = (await liveFamilies(me.id)).find((r) => r.device_id === phone).family_id;

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/auth/sessions/${phoneFamily}`,
      headers: me.headers,
    });
    expect(res.statusCode).toBe(204);

    expect(await devices(me.id)).toEqual([mine]);
  });

  it('revoke-others keeps only the caller device row', async () => {
    const mine = newId();
    const me = await account(mine);
    await signIn(me, newId());
    await signIn(me, newId());
    expect(await devices(me.id)).toHaveLength(3);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/sessions/revoke-others',
      headers: me.headers,
      payload: { refreshToken: me.refreshToken },
    });
    expect(res.statusCode).toBe(200);

    expect(await devices(me.id)).toEqual([mine]);
    // The caller's own session still works.
    expect(
      (
        await app.inject({
          method: 'POST',
          url: '/api/v1/auth/refresh',
          payload: { refreshToken: me.refreshToken },
        })
      ).statusCode,
    ).toBe(200);
  });

  it('password change removes every bound notification device', async () => {
    const me = await account(newId());
    await signIn(me, newId());
    // A device registered by an older client, bound to no family, is not a
    // session and stays.
    const unbound = newId();
    await putDevice(me, unbound);
    expect(await devices(me.id)).toHaveLength(3);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/password',
      headers: me.headers,
      payload: { currentPassword: PASSWORD, newPassword: 'integration-pw-2' },
    });
    expect(res.statusCode).toBe(204);

    expect(await devices(me.id)).toEqual([unbound]);
  });

  it('refresh reuse removes the device bound to the burned family', async () => {
    const mine = newId();
    const phone = newId();
    const me = await account(mine);
    const other = await signIn(me, phone);

    const first = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: other.refreshToken },
    });
    expect(first.statusCode).toBe(200);
    // The rotated token comes back: theft, so the whole family burns.
    const reused = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: other.refreshToken },
    });
    expect(reused.statusCode).toBe(401);
    expect(reused.json().code).toBe('AUTH_REFRESH_REUSED');

    expect(await devices(me.id)).toEqual([mine]);
  });
});
