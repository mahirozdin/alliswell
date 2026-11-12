import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import {
  decideNewDeviceRinging,
  pickPromotion,
  platformLabel,
} from '../../src/db/notification-devices.js';

let app;
let tables;
let owner;

const DEVICE = '01DEVICEAAAAAAAAAAAAAAAAAA';

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const register = (deviceId, payload, headers = owner.headers) =>
  app.inject({
    method: 'PUT',
    url: `/api/v1/notification-devices/${deviceId}`,
    headers,
    payload,
  });

const list = (headers = owner.headers) =>
  app.inject({ method: 'GET', url: '/api/v1/notification-devices', headers });

describe('notification device registry (OPH-060)', () => {
  it('registers a device, then heartbeats update it in place', async () => {
    const created = await register(DEVICE, {
      platform: 'macos',
      deviceName: 'Mahir MBP',
      appVersion: '0.1.0',
    });
    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({
      id: DEVICE,
      platform: 'macos',
      deviceName: 'Mahir MBP',
      pushToken: null,
    });

    const heartbeat = await register(DEVICE, {
      platform: 'macos',
      pushToken: 'apns-token-1',
      appVersion: '0.2.0',
    });
    expect(heartbeat.statusCode).toBe(200);
    expect(heartbeat.json()).toMatchObject({
      pushToken: 'apns-token-1',
      appVersion: '0.2.0',
      deviceName: 'Mahir MBP', // untouched fields persist
    });
    expect(tables.notification_devices).toHaveLength(1);
  });

  it('lists only my devices, newest-seen first', async () => {
    await register(DEVICE, { platform: 'macos' });
    await register('01DEVICEBBBBBBBBBBBBBBBBBB', { platform: 'web' });
    const other = await registerUser(app, { email: 'other@example.com' });
    await register('01DEVICECCCCCCCCCCCCCCCCCC', { platform: 'ios' }, other.headers);

    const mine = (await list()).json();
    expect(mine.items.map((d) => d.platform).sort()).toEqual(['macos', 'web']);
    const theirs = (await list(other.headers)).json();
    expect(theirs.items.map((d) => d.id)).toEqual(['01DEVICECCCCCCCCCCCCCCCCCC']);
  });

  it('reassigns a device that signs into another account', async () => {
    await register(DEVICE, { platform: 'android' });
    const other = await registerUser(app, { email: 'other@example.com' });

    const takeover = await register(DEVICE, { platform: 'android' }, other.headers);
    expect(takeover.statusCode).toBe(200);

    expect((await list()).json().items).toHaveLength(0);
    expect((await list(other.headers)).json().items.map((d) => d.id)).toEqual([DEVICE]);
    expect(tables.notification_devices).toHaveLength(1);
  });

  it('unregisters idempotently and never touches foreign devices', async () => {
    await register(DEVICE, { platform: 'linux' });
    const other = await registerUser(app, { email: 'other@example.com' });

    // A foreign delete is a no-op 204 — the row stays with its owner.
    const foreign = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${DEVICE}`,
      headers: other.headers,
    });
    expect(foreign.statusCode).toBe(204);
    expect(tables.notification_devices).toHaveLength(1);

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const res = await app.inject({
        method: 'DELETE',
        url: `/api/v1/notification-devices/${DEVICE}`,
        headers: owner.headers,
      });
      expect(res.statusCode).toBe(204);
    }
    expect(tables.notification_devices).toHaveLength(0);
  });

  it('remembers the device locale, and leaves it alone on a heartbeat (OPH-309)', async () => {
    // The visible fallback push picks a fixed string, and the account's locale
    // is not the device's: a phone can be in Turkish while the account is not.
    const created = await register(DEVICE, { platform: 'ios', locale: 'tr' });
    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({ locale: 'tr' });

    const heartbeat = await register(DEVICE, { platform: 'ios' });
    expect(heartbeat.json()).toMatchObject({ locale: 'tr' });

    const changed = await register(DEVICE, { platform: 'ios', locale: 'en' });
    expect(changed.json()).toMatchObject({ locale: 'en' });
  });

  it('names a new device after the request that registered it, once (OPH-309)', async () => {
    // OPH-284's rule, applied to the other device table: store the User-Agent
    // RAW rather than guessing "Chrome on macOS". On INSERT only — a heartbeat
    // must not overwrite a name a client set deliberately.
    const ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15';
    const created = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${DEVICE}`,
      headers: { ...owner.headers, 'user-agent': ua },
      payload: { platform: 'web' },
    });
    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({ deviceName: ua });

    const heartbeat = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${DEVICE}`,
      headers: { ...owner.headers, 'user-agent': 'something-else/1.0' },
      payload: { platform: 'web' },
    });
    expect(heartbeat.statusCode).toBe(200);
    expect(heartbeat.json()).toMatchObject({ deviceName: ua });
  });

  it('an explicit device name beats the User-Agent (OPH-309)', async () => {
    const created = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${DEVICE}`,
      headers: { ...owner.headers, 'user-agent': 'Dart/3.9 (dart:io)' },
      payload: { platform: 'android', deviceName: 'Mahir Pixel' },
    });
    expect(created.json()).toMatchObject({ deviceName: 'Mahir Pixel' });
  });

  it('a browser subscription round-trips, and its keys do not (OPH-311)', async () => {
    // A Web Push subscription is an endpoint plus two keys. `push_token` is 512
    // characters and an FCM registration token; an endpoint alone can be
    // longer, so the subscription gets its own columns.
    const created = await register(DEVICE, {
      platform: 'web',
      pushProvider: 'webpush',
      pushEndpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
      pushP256dh: 'B'.repeat(87),
      pushAuth: 'C'.repeat(22),
    });
    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({
      pushProvider: 'webpush',
      pushEndpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
      invalidAt: null,
      lastPushAt: null,
    });
    // The two keys are what encrypts a payload TO this browser. The client
    // already has them; echoing them buys nothing and widens what a leaked
    // response is worth.
    expect(created.body).not.toContain('C'.repeat(22));
    expect(created.json()).not.toHaveProperty('pushAuth');
  });

  it('refuses half a subscription (OPH-311)', async () => {
    // Same rule as the config block: a half-filled subscription looks
    // registered and cannot be sent to.
    const res = await register(DEVICE, {
      platform: 'web',
      pushProvider: 'webpush',
      pushEndpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
    });
    expect(res.statusCode).toBe(400);
  });

  it('re-subscribing brings a device back from the dead (OPH-311)', async () => {
    await register(DEVICE, { platform: 'web' });
    // The sender marks a device whose endpoint answered 410 Gone.
    tables.notification_devices[0].invalid_at = new Date('2026-09-01T00:00:00Z');

    const again = await register(DEVICE, {
      platform: 'web',
      pushProvider: 'webpush',
      pushEndpoint: 'https://fcm.googleapis.com/fcm/send/fresh',
      pushP256dh: 'B'.repeat(87),
      pushAuth: 'C'.repeat(22),
    });
    expect(again.json()).toMatchObject({ invalidAt: null });
  });

  it('a plain heartbeat leaves a dead subscription dead (OPH-311)', async () => {
    // The other half of the rule above, and the one that matters: a browser
    // that revoked its subscription stays revoked however often the tab is
    // opened. Only NEW credentials say the device is reachable again.
    await register(DEVICE, {
      platform: 'web',
      pushProvider: 'webpush',
      pushEndpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
      pushP256dh: 'B'.repeat(87),
      pushAuth: 'C'.repeat(22),
    });
    const dead = new Date('2026-09-01T00:00:00Z');
    tables.notification_devices[0].invalid_at = dead;

    const heartbeat = await register(DEVICE, { platform: 'web' });
    expect(heartbeat.json().invalidAt).toBe(dead.toISOString());
  });

  it('never lets a client write what the sender owns (OPH-311)', async () => {
    // MEASURED: `additionalProperties: false` here STRIPS rather than refuses —
    // Fastify compiles it with Ajv's removeAdditional. The protection is real
    // either way (the handler never sees the key), and this pins the property
    // rather than the status code, because the status code is not the point.
    const res = await register(DEVICE, {
      platform: 'web',
      invalidAt: '2026-09-01T00:00:00.000Z',
      lastPushAt: '2026-09-01T00:00:00.000Z',
    });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({ invalidAt: null, lastPushAt: null });
  });

  it('validates platform and requires auth', async () => {
    const badPlatform = await register(DEVICE, { platform: 'blackberry' });
    expect(badPlatform.statusCode).toBe(400);

    const unauthenticated = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${DEVICE}`,
      payload: { platform: 'web' },
    });
    expect(unauthenticated.statusCode).toBe(401);
  });
});

describe('urgent-alarm device rule (OPH-433, ADR-0069 #2)', () => {
  const ring = (id, platform, source = 'auto') => ({ id, platform, rings_urgent_source: source });

  it('the first device rings, web included', () => {
    expect(decideNewDeviceRinging([], 'web')).toEqual({ ringsUrgent: true, handOver: [] });
    expect(decideNewDeviceRinging([], 'ios')).toEqual({ ringsUrgent: true, handOver: [] });
  });

  it('a phone or desktop takes over from automatic web rows', () => {
    const rows = [ring('W1', 'web', 'auto'), ring('W2', 'web', 'backfill')];
    expect(decideNewDeviceRinging(rows, 'android')).toEqual({
      ringsUrgent: true,
      handOver: ['W1', 'W2'],
    });
    expect(decideNewDeviceRinging(rows, 'linux').ringsUrgent).toBe(true);
  });

  it('a web row the user chose, a ringing phone, or a new web tab: joins off', () => {
    expect(decideNewDeviceRinging([ring('W', 'web', 'user')], 'ios')).toEqual({
      ringsUrgent: false,
      handOver: [],
    });
    expect(decideNewDeviceRinging([ring('W', 'web'), ring('P', 'ios')], 'android')).toEqual({
      ringsUrgent: false,
      handOver: [],
    });
    expect(decideNewDeviceRinging([ring('W', 'web')], 'web')).toEqual({
      ringsUrgent: false,
      handOver: [],
    });
  });

  it('promotion prefers the most recently seen non-web device, else web', () => {
    const at = (iso) => new Date(iso);
    const rows = [
      { id: 'A', platform: 'web', last_seen_at: at('2026-11-10T00:00:00Z') },
      { id: 'B', platform: 'ios', last_seen_at: at('2026-11-01T00:00:00Z') },
      { id: 'C', platform: 'android', last_seen_at: at('2026-11-05T00:00:00Z') },
    ];
    expect(pickPromotion(rows).id).toBe('C');
    expect(pickPromotion(rows.filter((r) => r.platform === 'web')).id).toBe('A');
    expect(pickPromotion([])).toBeNull();
  });

  it('names every platform', () => {
    expect(['ios', 'android', 'macos', 'windows', 'linux', 'web'].map(platformLabel)).toEqual([
      'iPhone',
      'Android',
      'Mac',
      'Windows',
      'Linux',
      'Web',
    ]);
  });
});

describe('PATCH /notification-devices/:id and ringsUrgent fields (OPH-433)', () => {
  const patch = (deviceId, payload, headers = owner.headers) =>
    app.inject({
      method: 'PATCH',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers,
      payload,
    });

  it('register answers ringsUrgent and its source; old clients only gain fields', async () => {
    const created = await register(DEVICE, { platform: 'ios' });
    expect(created.json()).toMatchObject({ ringsUrgent: true, ringsUrgentSource: 'auto' });
    const second = await register('01DEVICEBBBBBBBBBBBBBBBBBB', { platform: 'android' });
    expect(second.json()).toMatchObject({ ringsUrgent: false, ringsUrgentSource: 'auto' });
    const items = (await list()).json().items;
    expect(items.every((d) => typeof d.ringsUrgent === 'boolean')).toBe(true);
  });

  it('a ringsUrgent key on PUT is ignored: only PATCH chooses', async () => {
    await register(DEVICE, { platform: 'ios' });
    const second = await register('01DEVICEBBBBBBBBBBBBBBBBBB', {
      platform: 'android',
      ringsUrgent: true,
    });
    expect(second.json()).toMatchObject({ ringsUrgent: false });
  });

  it('PATCH writes source user, warns when nothing rings, 404s foreign rows', async () => {
    await register(DEVICE, { platform: 'ios' });
    const off = await patch(DEVICE, { ringsUrgent: false });
    expect(off.statusCode).toBe(200);
    expect(off.json()).toMatchObject({
      ringsUrgent: false,
      ringsUrgentSource: 'user',
      warnings: ['NO_URGENT_DEVICE'],
    });
    const on = await patch(DEVICE, { ringsUrgent: true });
    expect(on.json()).toMatchObject({ ringsUrgent: true, warnings: [] });

    const other = await registerUser(app, { email: 'other@example.com' });
    const foreign = await patch(DEVICE, { ringsUrgent: false }, other.headers);
    expect(foreign.statusCode).toBe(404);
    expect(foreign.json().code).toBe('DEVICE_NOT_FOUND');
    expect(tables.notification_devices[0].rings_urgent).toBe(true);
  });

  it('PATCH validates its body', async () => {
    await register(DEVICE, { platform: 'ios' });
    const bad = await patch(DEVICE, { ringsUrgent: 'yes' });
    expect(bad.statusCode).toBe(400);
    const long = await patch(DEVICE, { deviceName: 'x'.repeat(256) });
    expect(long.statusCode).toBe(400);
  });

  it('a blank name falls back to the platform label', async () => {
    await register(DEVICE, { platform: 'android', deviceName: 'Pixel' });
    const blank = await patch(DEVICE, { deviceName: '  ' });
    expect(blank.json()).toMatchObject({ deviceName: 'Android', ringsUrgentSource: 'auto' });
  });

  it('DELETE of the ringing device promotes the most recent non-web one', async () => {
    await register(DEVICE, { platform: 'ios' });
    await register('01DEVICEBBBBBBBBBBBBBBBBBB', { platform: 'web' });
    await register('01DEVICECCCCCCCCCCCCCCCCCC', { platform: 'android' });
    const byId = (id) => tables.notification_devices.find((r) => r.id === id);
    byId('01DEVICEBBBBBBBBBBBBBBBBBB').last_seen_at = new Date('2026-11-10T00:00:00Z');
    byId('01DEVICECCCCCCCCCCCCCCCCCC').last_seen_at = new Date('2026-11-01T00:00:00Z');
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notification-devices/${DEVICE}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(204);
    expect(byId('01DEVICECCCCCCCCCCCCCCCCCC')).toMatchObject({
      rings_urgent: true,
      rings_urgent_source: 'auto',
    });
    expect(byId('01DEVICEBBBBBBBBBBBBBBBBBB').rings_urgent).toBe(false);
  });

  it('a heartbeat whose device was taken over mid-flight does not leave two ringing devices', async () => {
    const PHONE = DEVICE;
    const TABLET = '01DEVICEEEEEEEEEEEEEEEEEEE';
    await register(PHONE, { platform: 'ios' }); // rings for the owner
    await register(TABLET, { platform: 'android' }); // joins off
    const other = await registerUser(app, { email: 'other@example.com' });

    // Hold the owner's heartbeat right after it has read who owns PHONE.
    const realDb = app.db;
    let reached;
    let release;
    const atPause = new Promise((resolve) => (reached = resolve));
    const resume = new Promise((resolve) => (release = resolve));
    let armed = true;
    const holdFirst = (builder) => {
      const proxy = new Proxy(builder, {
        get(target, prop) {
          const value = Reflect.get(target, prop);
          if (typeof value !== 'function') return value;
          if (prop === 'first') {
            return async (...args) => {
              const result = await value.apply(target, args);
              reached();
              await resume;
              return result;
            };
          }
          return (...args) => {
            const out = value.apply(target, args);
            return out === target ? proxy : out;
          };
        },
      });
      return proxy;
    };
    app.db = new Proxy(realDb, {
      apply(target, thisArg, args) {
        const builder = Reflect.apply(target, thisArg, args);
        if (!armed || args[0] !== 'notification_devices') return builder;
        armed = false;
        return holdFirst(builder);
      },
    });
    try {
      const beat = register(PHONE, { platform: 'ios' });
      await atPause;
      // Meanwhile another account signs in on PHONE: it rings for them, and
      // the owner's TABLET is promoted.
      const takeover = await register(PHONE, { platform: 'ios' }, other.headers);
      expect(takeover.json()).toMatchObject({ ringsUrgent: true });
      release();
      expect((await beat).statusCode).toBe(200);
    } finally {
      app.db = realDb;
    }

    const ringingOf = (userId) =>
      tables.notification_devices
        .filter((r) => r.user_id === userId && Number(r.rings_urgent) === 1)
        .map((r) => r.id);
    // Whoever owns PHONE in the end, each account has exactly one ringer.
    expect(ringingOf(owner.user.id)).toHaveLength(1);
    expect(ringingOf(other.user.id).length).toBeLessThanOrEqual(1);
    const phone = tables.notification_devices.find((r) => r.id === PHONE);
    expect(phone.user_id).toBe(owner.user.id);
    expect(ringingOf(owner.user.id)).toEqual([TABLET]);
  });
});
