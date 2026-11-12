import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph060-${Date.now()}`;

describe.runIf(enabled)('integration: notification device registry', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-8' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    owner = { headers: { authorization: `Bearer ${body.tokens.accessToken}` } };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      // notification_devices cascades from users; workspaces cascade the rest.
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('registers, heartbeats, lists and unregisters against real MySQL', async () => {
    const deviceId = newId();

    const created = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: owner.headers,
      payload: { platform: 'macos', deviceName: 'Integration Mac' },
    });
    expect(created.statusCode).toBe(201);

    const heartbeat = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: owner.headers,
      payload: { platform: 'macos', pushToken: 'tok-123' },
    });
    expect(heartbeat.statusCode).toBe(200);
    expect(heartbeat.json().pushToken).toBe('tok-123');
    expect(heartbeat.json().deviceName).toBe('Integration Mac');

    const listed = await app.inject({
      method: 'GET',
      url: '/api/v1/notification-devices',
      headers: owner.headers,
    });
    expect(listed.json().items.map((d) => d.id)).toContain(deviceId);

    const removed = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: owner.headers,
    });
    expect(removed.statusCode).toBe(204);
    const after = await app.inject({
      method: 'GET',
      url: '/api/v1/notification-devices',
      headers: owner.headers,
    });
    expect(after.json().items.map((d) => d.id)).not.toContain(deviceId);
  });
});

/**
 * OPH-433 (#48, ADR-0069 #2) — which device rings urgent alarms, decided by
 * the server on insert or takeover with the user's row locked. Every test
 * gets fresh accounts so the rule always starts from "no ringing device".
 */
describe.runIf(enabled)('integration: urgent-alarm device rule (OPH-433)', () => {
  let app;
  let seq = 0;
  const prefix = `oph433-${Date.now()}`;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '200' }),
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

  const account = async () => {
    seq += 1;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${prefix}-${seq}@example.com`, password: 'integration-pw-433' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    return {
      id: body.user.id,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  };

  const put = (user, deviceId, platform) =>
    app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: user.headers,
      payload: { platform },
    });

  const patch = (user, deviceId, payload) =>
    app.inject({
      method: 'PATCH',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: user.headers,
      payload,
    });

  const remove = (user, deviceId) =>
    app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: user.headers,
    });

  const ringing = async (user) =>
    (
      await app
        .db('notification_devices')
        .where({ user_id: user.id })
        .orderBy('id')
        .select('id', 'rings_urgent')
    )
      .filter((row) => Number(row.rings_urgent) === 1)
      .map((row) => row.id);

  const row = (deviceId) => app.db('notification_devices').where({ id: deviceId }).first();

  it('web first then a phone leaves exactly one ringing device, the phone', async () => {
    const user = await account();
    const web = newId();
    const phone = newId();

    const first = await put(user, web, 'web');
    expect(first.statusCode).toBe(201);
    expect(first.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'auto' });

    const second = await put(user, phone, 'ios');
    expect(second.statusCode).toBe(201);
    expect(second.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'auto' });

    expect(await ringing(user)).toEqual([phone]);
    const listed = await app.inject({
      method: 'GET',
      url: '/api/v1/notification-devices',
      headers: user.headers,
    });
    const byId = Object.fromEntries(listed.json().items.map((d) => [d.id, d]));
    expect(byId[web]).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'auto' });
    expect(byId[phone]).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'auto' });
  });

  it('a second phone joins off when the first one rings', async () => {
    const user = await account();
    const ios = newId();
    const android = newId();
    await put(user, ios, 'ios');
    const joined = await put(user, android, 'android');
    expect(joined.json()).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'auto' });
    // A web tab that comes later starts off as well.
    const web = await put(user, newId(), 'web');
    expect(web.json()).toMatchObject({ ringsUrgent: false });
    expect(await ringing(user)).toEqual([ios]);
  });

  it('a web-only account rings on web', async () => {
    const user = await account();
    const web = newId();
    const res = await put(user, web, 'web');
    expect(res.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'auto' });
    // A second tab of the same account does not ring as well.
    const tab = await put(user, newId(), 'web');
    expect(tab.json()).toMatchObject({ ringsUrgent: false });
    expect(await ringing(user)).toEqual([web]);
  });

  it('a web device the user switched on is not handed over', async () => {
    const user = await account();
    const web = newId();
    await put(user, web, 'web');
    const chosen = await patch(user, web, { ringsUrgent: true });
    expect(chosen.statusCode).toBe(200);
    expect(chosen.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'user' });

    const phone = newId();
    const res = await put(user, phone, 'android');
    expect(res.json()).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'auto' });
    expect(await ringing(user)).toEqual([web]);
  });

  it('a backfilled web row is handed over like an automatic one', async () => {
    const user = await account();
    const web = newId();
    await put(user, web, 'web');
    await app
      .db('notification_devices')
      .where({ id: web })
      .update({ rings_urgent_source: 'backfill' });
    const desktop = newId();
    const res = await put(user, desktop, 'macos');
    expect(res.json()).toMatchObject({ ringsUrgent: true });
    expect(await ringing(user)).toEqual([desktop]);
  });

  it('two concurrent first registrations leave exactly one ringing device', async () => {
    for (let round = 0; round < 3; round += 1) {
      const user = await account();
      const results = await Promise.all([
        put(user, newId(), 'ios'),
        put(user, newId(), 'android'),
        put(user, newId(), 'macos'),
      ]);
      expect(results.map((r) => r.statusCode)).toEqual([201, 201, 201]);
      expect(results.filter((r) => r.json().ringsUrgent)).toHaveLength(1);
      expect(await ringing(user)).toHaveLength(1);
    }
  });

  it('heartbeat never changes ringsUrgent', async () => {
    const user = await account();
    const first = newId();
    const second = newId();
    await put(user, first, 'ios');
    await put(user, second, 'android');

    const beat = await put(user, second, 'android');
    expect(beat.statusCode).toBe(200);
    expect(beat.json()).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'auto' });

    // The user switched the only ringing device off: a heartbeat does not
    // re-run the first-device rule and switch it back on.
    await patch(user, first, { ringsUrgent: false });
    const again = await put(user, first, 'ios');
    expect(again.json()).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'user' });
    expect(await ringing(user)).toEqual([]);
  });

  it('taking over a device from another account recomputes ringsUrgent', async () => {
    const previous = await account();
    const next = await account();
    const shared = newId();
    const previousWeb = newId();
    await put(previous, shared, 'android');
    await put(previous, previousWeb, 'web');
    const nextPhone = newId();
    await put(next, nextPhone, 'ios');

    // The new owner already has a ringing phone, so the taken-over install
    // joins off instead of keeping the previous account's "on".
    const takeover = await put(next, shared, 'android');
    expect(takeover.statusCode).toBe(200);
    expect(takeover.json()).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'auto' });
    expect(await ringing(next)).toEqual([nextPhone]);

    // The previous account lost its ringing device: like a delete, the
    // remaining device is promoted so it is not left silent.
    expect(await ringing(previous)).toEqual([previousWeb]);

    // An account with no device takes over and the install rings for it.
    const fresh = await account();
    const claimed = await put(fresh, shared, 'android');
    expect(claimed.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'auto' });
  });

  it('deleting the ringing device promotes the most recently seen non-web device', async () => {
    const user = await account();
    const ringer = newId();
    const olderPhone = newId();
    const recentPhone = newId();
    const web = newId();
    await put(user, ringer, 'ios');
    await put(user, olderPhone, 'android');
    await put(user, recentPhone, 'linux');
    await put(user, web, 'web');
    const seen = (id, at) =>
      app
        .db('notification_devices')
        .where({ id })
        .update({ last_seen_at: new Date(at) });
    await seen(olderPhone, '2026-11-01T00:00:00.000Z');
    await seen(recentPhone, '2026-11-05T00:00:00.000Z');
    await seen(web, '2026-11-10T00:00:00.000Z'); // most recent of all, but web

    const res = await remove(user, ringer);
    expect(res.statusCode).toBe(204);
    expect(await ringing(user)).toEqual([recentPhone]);
    expect(await row(recentPhone)).toMatchObject({ rings_urgent_source: 'auto' });

    // Deleting a device that did not ring promotes nothing.
    await remove(user, olderPhone);
    expect(await ringing(user)).toEqual([recentPhone]);

    // Only web is left after the ringer goes: web is promoted.
    await remove(user, recentPhone);
    expect(await ringing(user)).toEqual([web]);
  });

  it('deleting the ringing device keeps a user choice of none elsewhere', async () => {
    const user = await account();
    const a = newId();
    const b = newId();
    await put(user, a, 'ios');
    await put(user, b, 'android');
    await patch(user, b, { ringsUrgent: true });
    // b still rings after a goes: nothing is promoted on top of it.
    await remove(user, a);
    expect(await ringing(user)).toEqual([b]);
    expect(await row(b)).toMatchObject({ rings_urgent_source: 'user' });
  });

  it('PATCH ringsUrgent false on the last ringing device warns NO_URGENT_DEVICE', async () => {
    const user = await account();
    const first = newId();
    const second = newId();
    await put(user, first, 'ios');
    await put(user, second, 'android');

    const on = await patch(user, second, { ringsUrgent: true });
    expect(on.statusCode).toBe(200);
    expect(on.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'user', warnings: [] });
    expect((await ringing(user)).sort()).toEqual([first, second].sort());

    const offOne = await patch(user, first, { ringsUrgent: false });
    expect(offOne.json()).toMatchObject({ ringsUrgent: false, warnings: [] });

    // Allowed, never blocked — the client warns.
    const offLast = await patch(user, second, { ringsUrgent: false });
    expect(offLast.statusCode).toBe(200);
    expect(offLast.json()).toMatchObject({
      ringsUrgent: false,
      ringsUrgentSource: 'user',
      warnings: ['NO_URGENT_DEVICE'],
    });
    expect(await ringing(user)).toEqual([]);
  });

  it('PATCH renames, and a blank name falls back to the platform label', async () => {
    const user = await account();
    const phone = newId();
    await put(user, phone, 'ios');
    const named = await patch(user, phone, { deviceName: '  Kitchen iPhone ' });
    expect(named.json()).toMatchObject({ deviceName: 'Kitchen iPhone', ringsUrgent: true });
    expect(named.json().ringsUrgentSource).toBe('auto'); // a rename is not a ringing choice
    const blank = await patch(user, phone, { deviceName: '   ' });
    expect(blank.json()).toMatchObject({ deviceName: 'iPhone' });
    const cleared = await patch(user, phone, { deviceName: null });
    expect(cleared.json()).toMatchObject({ deviceName: 'iPhone' });
  });

  /** The device ids a user's session family is bound to, across all its rows. */
  const boundTo = async (familyId) =>
    [
      ...new Set(
        (await app.db('refresh_tokens').where({ family_id: familyId }).select('device_id')).map(
          (r) => r.device_id,
        ),
      ),
    ].sort();

  const login = async (email, extra = {}) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email, password: 'integration-pw-433', ...extra },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    const family = await app
      .db('refresh_tokens')
      .where({
        token_hash: hashRefreshToken(body.tokens.refreshToken, app.config.auth.refreshSecret),
      })
      .first('family_id');
    return {
      id: body.user.id,
      family: family.family_id,
      refreshToken: body.tokens.refreshToken,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  };

  it('registration binds the caller unbound live family to the device it registers', async () => {
    await account();
    const session = await login(`${prefix}-${seq}@example.com`);
    const device = newId();
    expect(await boundTo(session.family)).toEqual([null]);
    expect((await put(session, device, 'ios')).statusCode).toBe(201);
    expect(await boundTo(session.family)).toEqual([device]);
    const listed = await app.inject({
      method: 'GET',
      url: '/api/v1/notification-devices',
      headers: session.headers,
    });
    expect(listed.json().items.find((d) => d.id === device).hasSession).toBe(true);
  });

  it('registration never rebinds a family bound to another device', async () => {
    await account();
    const email = `${prefix}-${seq}@example.com`;
    const phone = newId();
    const laptop = newId();
    const session = await login(email, { deviceId: phone });
    expect((await put(session, phone, 'ios')).statusCode).toBe(201);
    expect(await boundTo(session.family)).toEqual([phone]);

    // The same session registers another install's id (a broken or hostile
    // client): the row is written, the family keeps its device.
    expect((await put(session, laptop, 'macos')).statusCode).toBe(201);
    expect((await put(session, laptop, 'macos')).statusCode).toBe(200);
    expect(await boundTo(session.family)).toEqual([phone]);
    const listed = await app.inject({
      method: 'GET',
      url: '/api/v1/notification-devices',
      headers: session.headers,
    });
    const has = Object.fromEntries(listed.json().items.map((d) => [d.id, d.hasSession]));
    expect(has).toEqual({ [phone]: true, [laptop]: false });

    // A family bound at registration is never moved by a later one either.
    const fresh = await login(email);
    expect((await put(fresh, laptop, 'macos')).statusCode).toBe(200);
    expect(await boundTo(fresh.family)).toEqual([laptop]);
    expect((await put(fresh, phone, 'ios')).statusCode).toBe(200);
    expect(await boundTo(fresh.family)).toEqual([laptop]);
    expect(await boundTo(session.family)).toEqual([phone]);

    // A session that has ended binds nothing with the access token it holds.
    const ended = await login(email);
    const out = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: ended.refreshToken },
    });
    expect(out.statusCode).toBe(204);
    const tablet = newId();
    expect((await put(ended, tablet, 'ios')).statusCode).toBe(201);
    expect(await boundTo(ended.family)).toEqual([null]);
  });

  it('an access token without sid binds nothing', async () => {
    const user = await account();
    const email = `${prefix}-${seq}@example.com`;
    const session = await login(email);
    // An access token signed before tokens named their session (or by any
    // path that names none): the user is known, the session is not.
    const nameless = {
      headers: {
        authorization: `Bearer ${app.signAccessToken({ id: user.id, email })}`,
      },
    };
    const device = newId();
    expect((await put(nameless, device, 'ios')).statusCode).toBe(201);
    expect((await put(nameless, device, 'ios')).statusCode).toBe(200);
    const bound = await app
      .db('refresh_tokens')
      .where({ user_id: user.id })
      .whereNotNull('device_id')
      .select('id');
    expect(bound).toEqual([]);
    expect(await boundTo(session.family)).toEqual([null]);
  });

  it('PATCH only touches the caller own device', async () => {
    const owner = await account();
    const stranger = await account();
    const device = newId();
    await put(owner, device, 'android');

    const foreign = await patch(stranger, device, { ringsUrgent: false, deviceName: 'mine now' });
    expect(foreign.statusCode).toBe(404);
    expect(foreign.json()).toMatchObject({ code: 'DEVICE_NOT_FOUND' });
    expect(await row(device)).toMatchObject({ user_id: owner.id, rings_urgent_source: 'auto' });
    expect(Number((await row(device)).rings_urgent)).toBe(1);
    expect((await row(device)).device_name).not.toBe('mine now');

    const missing = await patch(owner, newId(), { ringsUrgent: true });
    expect(missing.statusCode).toBe(404);
    expect(missing.json()).toMatchObject({ code: 'DEVICE_NOT_FOUND' });
  });
});
