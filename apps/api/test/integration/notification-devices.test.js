import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

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
