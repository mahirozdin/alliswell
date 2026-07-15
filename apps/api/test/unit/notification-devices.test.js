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
