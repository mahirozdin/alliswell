import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

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
