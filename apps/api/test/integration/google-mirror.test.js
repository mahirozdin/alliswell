import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { startFakeGoogle, fakeGoogleEnv } from '../helpers/fakegoogle.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis (BullMQ worker path) — the fake Google rides an
// ephemeral local port either way.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph072-${Date.now()}`;
const KEY = 'd'.repeat(64);

describe.runIf(enabled)('integration: calendar mirror over BullMQ', () => {
  let google;
  let app;
  let owner;

  beforeAll(async () => {
    google = await startFakeGoogle();
    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '100',
        CALENDAR_TOKEN_KEY: KEY,
        ...fakeGoogleEnv(google.url),
      }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-9' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    owner = {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };

    const accessToken = 'at-integration';
    google.state.issuedTokens.add(accessToken);
    await app.db('calendar_accounts').insert({
      id: newId(),
      user_id: owner.user.id,
      workspace_id: owner.workspace.id,
      provider: 'google',
      provider_account_id: `${emailPrefix}@example.com`,
      encrypted_access_token: encryptSecret(accessToken, KEY),
      encrypted_refresh_token: encryptSecret('rt-1', KEY),
      token_expires_at: new Date(Date.now() + 3600_000),
      default_calendar_id: 'primary',
      status: 'active',
    });
  });

  afterAll(async () => {
    if (app) {
      const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
      const ids = users.map((u) => u.id);
      if (ids.length > 0) {
        await app.db('workspaces').whereIn('owner_id', ids).delete();
        await app.db('users').whereIn('id', ids).delete();
      }
      await app.close();
    }
    await google?.app.close();
  });

  it('a committed task write flows through the queue into a Google event', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: {
        title: 'BullMQ ile aynalanan',
        calendarMirrorEnabled: true,
        scheduledStartAt: '2030-06-01T09:00:00.000Z',
        scheduledEndAt: '2030-06-01T10:00:00.000Z',
      },
    });
    expect(created.statusCode).toBe(201);
    const taskId = created.json().id;

    // The worker is asynchronous — wait for convergence.
    await vi.waitFor(
      async () => {
        const link = await app.db('calendar_event_links').where({ task_id: taskId }).first();
        expect(link).toBeTruthy();
      },
      { timeout: 8000, interval: 100 },
    );

    const events = [...google.state.eventsIn('primary').values()];
    const event = events.find((e) => e.extendedProperties?.private?.alliswell_task_id === taskId);
    expect(event).toBeTruthy();
    expect(event.summary).toBe('[Task] BullMQ ile aynalanan');

    // Completing drains back out through the same queue.
    await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${taskId}/complete`,
      headers: owner.headers,
    });
    await vi.waitFor(
      async () => {
        const link = await app.db('calendar_event_links').where({ task_id: taskId }).first();
        expect(link).toBeFalsy();
      },
      { timeout: 8000, interval: 100 },
    );
    expect(
      [...google.state.eventsIn('primary').values()].filter(
        (e) => e.extendedProperties?.private?.alliswell_task_id === taskId,
      ),
    ).toHaveLength(0);
  });
});
