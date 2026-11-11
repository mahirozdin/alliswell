import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const prefix = `oph435-${Date.now()}`;
const PASSWORD = 'integration-pw-435';

/**
 * OPH-435 (#48) — removing a device is a real remote sign-out.
 *
 * `DELETE /notification-devices/:id` revokes every live refresh family bound
 * to that device (`refresh_tokens.device_id`, OPH-434) in the same
 * transaction that removes the row, and stays "always 204". Every test gets a
 * fresh account so one test's families never leak into another's counts.
 */
describe.runIf(enabled)('integration: device removal signs the device out (OPH-435)', () => {
  let app;
  let seq = 0;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '500' }),
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

  /** A fresh account; its first session is bound to `deviceId` when given. */
  const account = async (deviceId) => {
    seq += 1;
    const email = `${prefix}-${seq}@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: PASSWORD, ...(deviceId ? { deviceId } : {}) },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    return {
      id: body.user.id,
      email,
      workspace: body.workspace,
      refreshToken: body.tokens.refreshToken,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  };

  /** A second sign-in of the same account, bound to `deviceId`. */
  const signIn = async (user, deviceId) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: user.email, password: PASSWORD, ...(deviceId ? { deviceId } : {}) },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    return {
      id: body.user.id,
      email: user.email,
      refreshToken: body.tokens.refreshToken,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  };

  const put = async (session, deviceId, platform = 'android') => {
    const res = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: session.headers,
      payload: { platform },
    });
    expect([200, 201]).toContain(res.statusCode);
  };

  const remove = (session, deviceId) =>
    app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: session.headers,
    });

  const refresh = (refreshToken) =>
    app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken } });

  const liveRows = (userId) =>
    app
      .db('refresh_tokens')
      .where({ user_id: userId })
      .whereNull('revoked_at')
      .whereNull('rotated_at')
      .select('family_id', 'device_id');

  const deviceRow = (deviceId) => app.db('notification_devices').where({ id: deviceId }).first();

  it('deleting a device revokes every live family bound to it and removes the row', async () => {
    const mine = newId();
    const phone = newId();
    const me = await account(mine);
    await put(me, mine, 'ios');
    // The phone signed in twice (a reinstall that kept its install id): two
    // live families, both bound to it.
    const phoneA = await signIn(me, phone);
    const phoneB = await signIn(me, phone);
    await put(phoneA, phone);

    const res = await remove(me, phone);
    expect(res.statusCode).toBe(204);

    expect(await deviceRow(phone)).toBeUndefined();
    const live = await liveRows(me.id);
    expect(live.filter((r) => r.device_id === phone)).toHaveLength(0);
    // Every row of both families is stamped, not only the live ones' heads.
    const phoneRows = await app
      .db('refresh_tokens')
      .where({ user_id: me.id, device_id: phone })
      .select('revoked_at');
    expect(phoneRows.length).toBe(2);
    expect(phoneRows.every((r) => r.revoked_at !== null)).toBe(true);
    // The caller's own family is untouched.
    expect(live.filter((r) => r.device_id === mine)).toHaveLength(1);
    // Neither of the phone's sign-ins can come back.
    expect((await refresh(phoneA.refreshToken)).statusCode).toBe(401);
    expect((await refresh(phoneB.refreshToken)).statusCode).toBe(401);
  });

  it('the removed device can no longer refresh', async () => {
    const mine = newId();
    const phone = newId();
    const me = await account(mine);
    await put(me, mine, 'ios');
    const other = await signIn(me, phone);
    await put(other, phone);

    // Before: the phone's session works.
    const before = await refresh(other.refreshToken);
    expect(before.statusCode).toBe(200);
    other.refreshToken = before.json().tokens.refreshToken;

    expect((await remove(me, phone)).statusCode).toBe(204);

    const after = await refresh(other.refreshToken);
    expect(after.statusCode).toBe(401);
  });

  it('deleting another device leaves the caller own session alive', async () => {
    const mine = newId();
    const laptop = newId();
    const me = await account(mine);
    await put(me, mine, 'ios');
    const other = await signIn(me, laptop);
    await put(other, laptop, 'macos');

    expect((await remove(me, laptop)).statusCode).toBe(204);

    expect(await deviceRow(mine)).toBeDefined();
    const res = await refresh(me.refreshToken);
    expect(res.statusCode).toBe(200);
    // And the removed one's session is gone.
    expect((await refresh(other.refreshToken)).statusCode).toBe(401);
  });

  it('deleting a device of another user revokes nothing and still answers 204', async () => {
    const theirs = newId();
    const them = await account(theirs);
    await put(them, theirs);
    const me = await account(newId());
    const before = await liveRows(them.id);

    const res = await remove(me, theirs);
    expect(res.statusCode).toBe(204);
    // A missing id answers the same.
    expect((await remove(me, newId())).statusCode).toBe(204);

    expect(await deviceRow(theirs)).toBeDefined();
    expect(await liveRows(them.id)).toEqual(before);
    expect((await refresh(them.refreshToken)).statusCode).toBe(200);
  });

  it('a device with no bound family is removed and nothing is revoked', async () => {
    const me = await account(); // an older client: no deviceId on sign-in
    const legacy = newId();
    await put(me, legacy, 'web');
    const before = await app
      .db('refresh_tokens')
      .where({ user_id: me.id })
      .whereNotNull('revoked_at')
      .count('* as n');

    expect((await remove(me, legacy)).statusCode).toBe(204);

    expect(await deviceRow(legacy)).toBeUndefined();
    const after = await app
      .db('refresh_tokens')
      .where({ user_id: me.id })
      .whereNotNull('revoked_at')
      .count('* as n');
    expect(after).toEqual(before);
    expect((await refresh(me.refreshToken)).statusCode).toBe(200);
  });

  it('deleting the caller own device during sign-out still lets logout succeed', async () => {
    // The app's own sign-out: DELETE its device, then /auth/logout with the
    // refresh token that DELETE has just revoked.
    const mine = newId();
    const me = await account(mine);
    await put(me, mine, 'ios');

    expect((await remove(me, mine)).statusCode).toBe(204);

    const logout = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: me.refreshToken },
    });
    expect(logout.statusCode).toBe(204);
    const logoutAll = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout?all=true',
      payload: { refreshToken: me.refreshToken },
    });
    expect(logoutAll.statusCode).toBe(204);

    expect(await deviceRow(mine)).toBeUndefined();
    expect((await refresh(me.refreshToken)).statusCode).toBe(401);
  });

  it('GET reports hasSession per device', async () => {
    const mine = newId();
    const unbound = newId();
    const revoked = newId();
    const me = await account(mine);
    await put(me, mine, 'ios');
    await put(me, unbound, 'web');
    const gone = await signIn(me, revoked);
    await put(gone, revoked, 'macos');
    // That session ends by itself (a plain logout), so its row stays without
    // a live family behind it.
    const out = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: gone.refreshToken },
    });
    expect(out.statusCode).toBe(204);

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/notification-devices',
      headers: me.headers,
    });
    expect(res.statusCode).toBe(200);
    const byId = Object.fromEntries(res.json().items.map((d) => [d.id, d.hasSession]));
    expect(byId).toEqual({ [mine]: true, [unbound]: false, [revoked]: false });
  });

  it('device removal is closed to API keys', async () => {
    const mine = newId();
    const me = await account(mine);
    await put(me, mine, 'ios');
    const minted = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${me.workspace.id}/api-keys`,
      headers: me.headers,
      payload: { name: 'script' },
    });
    expect(minted.statusCode).toBe(201);
    const key = { headers: { authorization: `Bearer ${minted.json().key}` } };

    const res = await remove(key, mine);
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('AUTH_APIKEY_FORBIDDEN');

    expect(await deviceRow(mine)).toBeDefined();
    expect((await refresh(me.refreshToken)).statusCode).toBe(200);
  });
});
