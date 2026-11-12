import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const prefix = `oph458-${Date.now()}`;
const PASSWORD = 'integration-pw-458';
const PROBE = '/__test/widget-probe';

/**
 * OPH-458 (#50, ADR-0070) — the read-only `aww_` widget token.
 *
 * A session mints one per notification device (`POST /widget-tokens`); only
 * `app.authenticateWidget` opens it, and it dies with its device, its minting
 * session family, a password change, or its own 90 days.
 *
 * `GET /widget/snapshot` is OPH-460's route, so this suite opens the decorator
 * through a probe route registered by the `instrument` hook (it runs before
 * the auth plugin, so the probe resolves `app.authenticateWidget` per request).
 * The probe stands in for the snapshot here; `widget-snapshot.test.js` covers
 * the real one. Everything else in the API is the real thing.
 */
describe.runIf(enabled)('integration: widget tokens (OPH-458)', () => {
  let app;
  let seq = 0;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '500' }),
      instrument: async (root) => {
        root.get(
          PROBE,
          { onRequest: (request) => root.authenticateWidget(request) },
          (request) => ({
            userId: request.user.id,
            deviceId: request.widgetAuth.deviceId,
          }),
        );
      },
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

  const bearer = (token) => ({ authorization: `Bearer ${token}` });

  /** A fresh account whose first session is bound to `deviceId`, with the device registered. */
  const account = async (deviceId = newId()) => {
    seq += 1;
    const email = `${prefix}-${seq}@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: PASSWORD, deviceId },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    const me = {
      id: body.user.id,
      email,
      deviceId,
      workspace: body.workspace,
      refreshToken: body.tokens.refreshToken,
      headers: bearer(body.tokens.accessToken),
    };
    await put(me, deviceId);
    return me;
  };

  /** Another sign-in of the same account, bound to `deviceId`, its device registered. */
  const signIn = async (user, deviceId = newId()) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: user.email, password: PASSWORD, deviceId },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    const session = {
      id: body.user.id,
      email: user.email,
      deviceId,
      refreshToken: body.tokens.refreshToken,
      headers: bearer(body.tokens.accessToken),
    };
    await put(session, deviceId);
    return session;
  };

  async function put(session, deviceId) {
    const res = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers: session.headers,
      payload: { platform: 'ios' },
    });
    expect([200, 201]).toContain(res.statusCode);
  }

  const mintRaw = (session, deviceId = session.deviceId, headers = session.headers) =>
    app.inject({ method: 'POST', url: '/api/v1/widget-tokens', headers, payload: { deviceId } });

  const mint = async (session, deviceId) => {
    const res = await mintRaw(session, deviceId);
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const probe = (token) => app.inject({ method: 'GET', url: PROBE, headers: bearer(token) });

  const expectDead = async (token) => {
    const res = await probe(token);
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('AUTH_WIDGET_TOKEN_INVALID');
  };

  it('mints an aww_ token once, stores only its digest, and the token opens the widget door', async () => {
    const me = await account();
    const minted = await mint(me);
    expect(minted.token).toMatch(/^aww_[A-Za-z0-9_-]{43}$/);
    expect(minted.deviceId).toBe(me.deviceId);
    const days = (new Date(minted.expiresAt).getTime() - Date.now()) / 86400000;
    expect(days).toBeGreaterThan(89.9);
    expect(days).toBeLessThanOrEqual(90);

    const row = await app.db('widget_tokens').where({ user_id: me.id }).first();
    expect(row.device_id).toBe(me.deviceId);
    expect(row.token_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(row)).not.toContain(minted.token.slice(4));
    const family = await app
      .db('refresh_tokens')
      .where({ user_id: me.id, device_id: me.deviceId })
      .first('family_id');
    expect(row.session_family_id).toBe(family.family_id);

    const res = await probe(minted.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ userId: me.id, deviceId: me.deviceId });
  });

  it('a first sign-in can mint a widget token right after registering its device', async () => {
    // PR2-06: the app names its device on a sign-in only once it knows the
    // server takes `deviceId`, so a fresh sign-in starts an unbound family.
    // Its own registration binds it, and the mint that follows succeeds at
    // once instead of after the first refresh 15 minutes later.
    const me = await account();
    const phone = newId();
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: me.email, password: PASSWORD },
    });
    expect(res.statusCode).toBe(200);
    const fresh = {
      id: me.id,
      deviceId: phone,
      refreshToken: res.json().tokens.refreshToken,
      headers: bearer(res.json().tokens.accessToken),
    };
    const familyOf = async (session) =>
      (
        await app
          .db('refresh_tokens')
          .where({
            token_hash: hashRefreshToken(session.refreshToken, app.config.auth.refreshSecret),
          })
          .first('family_id')
      ).family_id;
    const family = await familyOf(fresh);

    await put(fresh, phone);
    const minted = await mint(fresh);
    expect(minted.deviceId).toBe(phone);
    const row = await app.db('widget_tokens').where({ device_id: phone }).first();
    expect(row.session_family_id).toBe(family);
    const rows = await app.db('refresh_tokens').where({ family_id: family }).select('device_id');
    expect(rows.map((r) => r.device_id)).toEqual(rows.map(() => phone));
    expect((await probe(minted.token)).statusCode).toBe(200);

    // A rotation keeps the binding, and the widget keeps working.
    const rotated = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: fresh.refreshToken },
    });
    expect(rotated.statusCode).toBe(200);
    expect((await probe(minted.token)).statusCode).toBe(200);

    // The same holds when the install's device row is already there (a
    // heartbeat, not an insert): a row left by an earlier sign-in on it.
    const tablet = newId();
    await app.db('notification_devices').insert({
      id: tablet,
      user_id: me.id,
      platform: 'ios',
      rings_urgent: false,
      rings_urgent_source: 'auto',
      last_seen_at: new Date(),
      created_at: new Date(),
      updated_at: new Date(),
    });
    const again = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: me.email, password: PASSWORD },
    });
    const second = {
      id: me.id,
      deviceId: tablet,
      headers: bearer(again.json().tokens.accessToken),
    };
    const beat = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${tablet}`,
      headers: second.headers,
      payload: { platform: 'ios' },
    });
    expect(beat.statusCode).toBe(200);
    expect((await mintRaw(second)).statusCode).toBe(201);

    // Removing the device now signs that session out, as for any bound one.
    const removed = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${phone}`,
      headers: me.headers,
    });
    expect(removed.statusCode).toBe(204);
    await expectDead(minted.token);
    const refused = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: rotated.json().tokens.refreshToken },
    });
    expect(refused.statusCode).toBe(401);
  });

  it('a widget token reads only the snapshot and is refused everywhere else', async () => {
    const me = await account();
    const { token } = await mint(me);
    expect((await probe(token)).statusCode).toBe(200);

    const doors = [
      ['GET', '/api/v1/me'],
      ['GET', `/api/v1/workspaces/${me.workspace.id}/tasks`],
      ['POST', `/api/v1/workspaces/${me.workspace.id}/tasks`, { title: 'leak' }],
      ['GET', '/api/v1/sync/pull'],
      ['GET', '/api/v1/notification-devices'],
      ['DELETE', `/api/v1/notification-devices/${me.deviceId}`],
      ['POST', '/api/v1/widget-tokens', { deviceId: me.deviceId }],
      ['GET', '/api/v1/auth/sessions'],
      ['POST', '/api/v1/auth/sessions/revoke-others', {}],
      ['GET', `/api/v1/workspaces/${me.workspace.id}/api-keys`],
    ];
    for (const [method, url, payload] of doors) {
      const res = await app.inject({ method, url, headers: bearer(token), payload });
      expect(res.statusCode, `${method} ${url}`).toBe(401);
      expect(res.json().code, `${method} ${url}`).toBe('AUTH_INVALID_TOKEN');
    }
    // MCP has its own bearer check; a widget token is not one of its tokens.
    const mcp = await app.inject({
      method: 'POST',
      url: '/mcp',
      headers: { ...bearer(token), accept: 'application/json, text/event-stream' },
      payload: { jsonrpc: '2.0', id: 1, method: 'tools/list' },
    });
    expect([401, 404]).toContain(mcp.statusCode);

    // Nothing the token touched was written or removed.
    expect(await app.db('notification_devices').where({ id: me.deviceId }).first()).toBeDefined();
    expect(await app.db('tasks').where({ workspace_id: me.workspace.id, title: 'leak' })).toEqual(
      [],
    );
    // And the token still works: being refused elsewhere does not burn it.
    expect((await probe(token)).statusCode).toBe(200);
  });

  it('api keys cannot mint widget tokens', async () => {
    const me = await account();
    const key = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${me.workspace.id}/api-keys`,
      headers: me.headers,
      payload: { name: 'script' },
    });
    expect(key.statusCode).toBe(201);
    const res = await mintRaw(me, me.deviceId, bearer(key.json().key));
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('AUTH_APIKEY_FORBIDDEN');
    expect(await app.db('widget_tokens').where({ user_id: me.id })).toEqual([]);

    // No bearer at all is a 401, and so is a widget token minting another.
    const anonymous = await app.inject({
      method: 'POST',
      url: '/api/v1/widget-tokens',
      payload: { deviceId: me.deviceId },
    });
    expect(anonymous.statusCode).toBe(401);
  });

  it("a device that is not the caller's is 404 DEVICE_NOT_FOUND", async () => {
    const me = await account();
    const other = await account();
    for (const deviceId of [other.deviceId, newId()]) {
      const res = await mintRaw(me, deviceId);
      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('DEVICE_NOT_FOUND');
    }
    expect(await app.db('widget_tokens').whereIn('user_id', [me.id, other.id])).toEqual([]);
  });

  it('app.authenticate rejects an aww_ bearer with AUTH_INVALID_TOKEN', async () => {
    const me = await account();
    const { token } = await mint(me);
    const res = await app.inject({ method: 'GET', url: '/api/v1/me', headers: bearer(token) });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('AUTH_INVALID_TOKEN');
    // The reverse holds too: the widget door takes nothing but a widget token.
    for (const headers of [me.headers, {}, bearer('aww_not-a-real-token')]) {
      const other = await app.inject({ method: 'GET', url: PROBE, headers });
      expect(other.statusCode).toBe(401);
      expect(other.json().code).toBe('AUTH_WIDGET_TOKEN_INVALID');
    }
  });

  it('presenting a widget token to /auth/refresh is invalid and never revokes the family', async () => {
    const me = await account();
    const { token } = await mint(me);
    for (const url of ['/api/v1/auth/refresh', '/api/v1/auth/logout?all=true']) {
      const res = await app.inject({ method: 'POST', url, payload: { refreshToken: token } });
      if (url.includes('refresh')) {
        expect(res.statusCode).toBe(401);
        expect(res.json().code).toBe('AUTH_INVALID_REFRESH_TOKEN');
      } else {
        expect(res.statusCode).toBe(204);
      }
    }
    const live = await app
      .db('refresh_tokens')
      .where({ user_id: me.id })
      .whereNull('revoked_at')
      .whereNull('rotated_at');
    expect(live).toHaveLength(1);
    // The app's own session and the widget both carry on.
    const refreshed = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: me.refreshToken },
    });
    expect(refreshed.statusCode).toBe(200);
    expect((await probe(token)).statusCode).toBe(200);
  });

  it('removing the device revokes its widget token', async () => {
    const me = await account();
    const phone = await signIn(me);
    const { token } = await mint(phone);
    const mine = await mint(me);
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${phone.deviceId}`,
      headers: me.headers,
    });
    expect(res.statusCode).toBe(204);
    await expectDead(token);
    const row = await app.db('widget_tokens').where({ device_id: phone.deviceId }).first();
    expect(row.revoked_at).not.toBeNull();
    // The other device's widget is untouched.
    expect((await probe(mine.token)).statusCode).toBe(200);
  });

  it('a removed session cannot mint a lasting widget token with the access token it still holds', async () => {
    // Device A (`phone`) is removed while device B (`me`) stays signed in.
    // A's access JWT verifies for up to 15 more minutes; a token minted with
    // it for B would outlive that window for as long as B's session lives.
    const me = await account();
    const phone = await signIn(me);
    const removed = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${phone.deviceId}`,
      headers: me.headers,
    });
    expect(removed.statusCode).toBe(204);
    // Still a working access token for everything stateless…
    expect(
      (await app.inject({ method: 'GET', url: '/api/v1/me', headers: phone.headers })).statusCode,
    ).toBe(200);
    // …but no widget token, for any device.
    for (const deviceId of [me.deviceId, phone.deviceId]) {
      const res = await mintRaw(phone, deviceId);
      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('DEVICE_NOT_FOUND');
    }
    expect(await app.db('widget_tokens').where({ user_id: me.id })).toEqual([]);

    // A live session mints only for the device it runs on, and an access
    // token that names no session at all (one signed before sessions were
    // named in it) mints nothing.
    const tablet = await signIn(me);
    const crossed = await mintRaw(tablet, me.deviceId);
    expect(crossed.statusCode).toBe(404);
    expect(crossed.json().code).toBe('DEVICE_NOT_FOUND');
    const nameless = bearer(app.signAccessToken({ id: me.id, email: me.email }));
    const old = await mintRaw(me, me.deviceId, nameless);
    expect(old.statusCode).toBe(404);
    expect(old.json().code).toBe('DEVICE_NOT_FOUND');
    expect(await app.db('widget_tokens').where({ user_id: me.id })).toEqual([]);

    // The device's own session still mints, tied to its own family.
    const own = await mint(me);
    const family = await app
      .db('refresh_tokens')
      .where({ user_id: me.id, device_id: me.deviceId })
      .first('family_id');
    const row = await app.db('widget_tokens').where({ user_id: me.id }).first();
    expect(row.session_family_id).toBe(family.family_id);
    expect((await probe(own.token)).statusCode).toBe(200);
  });

  it('a password change revokes widget tokens', async () => {
    const me = await account();
    const phone = await signIn(me);
    const tokens = [(await mint(me)).token, (await mint(phone)).token];
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/password',
      headers: me.headers,
      payload: { currentPassword: PASSWORD, newPassword: 'a-new-password-458' },
    });
    expect(res.statusCode).toBe(204);
    for (const token of tokens) await expectDead(token);
    const rows = await app.db('widget_tokens').where({ user_id: me.id });
    expect(rows).toHaveLength(2);
    expect(rows.every((r) => r.revoked_at !== null)).toBe(true);
  });

  it('revoking the minting session family kills the widget token', async () => {
    // Closing the session from the sessions screen.
    const me = await account();
    const phone = await signIn(me);
    const closed = await mint(phone);
    const family = await app
      .db('refresh_tokens')
      .where({ user_id: me.id, device_id: phone.deviceId })
      .first('family_id');
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/auth/sessions/${family.family_id}`,
      headers: me.headers,
    });
    expect(res.statusCode).toBe(204);
    await expectDead(closed.token);

    // Signing out (logout?all) on the device.
    const tablet = await signIn(me);
    const out = await mint(tablet);
    const logout = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout?all=true',
      payload: { refreshToken: tablet.refreshToken },
    });
    expect(logout.statusCode).toBe(204);
    await expectDead(out.token);

    // A plain logout of the live token leaves the family with no live row.
    const laptop = await signIn(me);
    const plain = await mint(laptop);
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: laptop.refreshToken },
    });
    await expectDead(plain.token);

    // Refresh reuse burns the family, and the widget with it.
    const watch = await signIn(me);
    const reused = await mint(watch);
    const first = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: watch.refreshToken },
    });
    expect(first.statusCode).toBe(200);
    // A rotation keeps the family, so the widget keeps working…
    expect((await probe(reused.token)).statusCode).toBe(200);
    const again = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: watch.refreshToken },
    });
    expect(again.json().code).toBe('AUTH_REFRESH_REUSED');
    // …and reuse ends it.
    await expectDead(reused.token);

    // The caller's own widget lived through all of it.
    const mine = await mint(me);
    expect((await probe(mine.token)).statusCode).toBe(200);
  });

  it('re-minting for the same device revokes the previous widget token', async () => {
    const me = await account();
    const first = await mint(me);
    const second = await mint(me);
    expect(second.token).not.toBe(first.token);
    await expectDead(first.token);
    expect((await probe(second.token)).statusCode).toBe(200);
    expect(await app.db('widget_tokens').where({ user_id: me.id })).toHaveLength(1);
  });

  it('an expired widget token answers 401', async () => {
    const me = await account();
    const { token } = await mint(me);
    await app
      .db('widget_tokens')
      .where({ user_id: me.id })
      .update({ expires_at: new Date(Date.now() - 1000) });
    await expectDead(token);
  });

  it('stamps last_used_at at most once a minute', async () => {
    const me = await account();
    const { token } = await mint(me);
    const stamp = async () =>
      (await app.db('widget_tokens').where({ user_id: me.id }).first('last_used_at')).last_used_at;
    expect(await stamp()).toBeNull();
    expect((await probe(token)).statusCode).toBe(200);
    // Fire-and-forget: give the write a moment.
    let first = null;
    for (let i = 0; i < 20 && !first; i += 1) {
      await new Promise((r) => setTimeout(r, 25));
      first = await stamp();
    }
    expect(first).not.toBeNull();
    expect((await probe(token)).statusCode).toBe(200);
    await new Promise((r) => setTimeout(r, 100));
    expect(new Date(await stamp()).getTime()).toBe(new Date(first).getTime());
  });
});
