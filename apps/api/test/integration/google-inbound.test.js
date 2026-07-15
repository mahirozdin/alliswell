import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { startFakeGoogle, fakeGoogleEnv, FAKE_WEBHOOK_URL } from '../helpers/fakegoogle.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis: this is the BullMQ path of the inbound vertical
// (OPH-074/075/076) end to end — webhook → dirty → queue → worker → task.
// The fake Google rides an ephemeral local port either way.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph074-${Date.now()}`;
const KEY = 'd'.repeat(64);
const WEBHOOK = '/api/v1/integrations/google/webhook';

describe.runIf(enabled)('integration: google inbound sync over BullMQ', () => {
  let google;
  let app;
  let owner;
  let accountId;

  const account = () => app.db('calendar_accounts').where({ id: accountId }).first();

  beforeAll(async () => {
    google = await startFakeGoogle();
    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '100',
        CALENDAR_TOKEN_KEY: KEY,
        GOOGLE_WEBHOOK_URL: FAKE_WEBHOOK_URL,
        // Test files run in parallel against one Redis. Without its own
        // keyspace this app's worker and the mirror suite's worker consume
        // the same queue — and a job that lands on the wrong worker talks to
        // the wrong fake Google (an access token it never issued → 401).
        REDIS_KEY_PREFIX: emailPrefix,
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

    const accessToken = 'at-integration-inbound';
    google.state.issuedTokens.add(accessToken);
    accountId = newId();
    await app.db('calendar_accounts').insert({
      id: accountId,
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
        // calendar_accounts / event links cascade from the workspace.
        await app.db('workspaces').whereIn('owner_id', ids).delete();
        await app.db('users').whereIn('id', ids).delete();
      }
      await app.close();
    }
    await google?.app.close();
  });

  it('a webhook drives an incremental sync that moves the task', async () => {
    // 1. A mirrored task, and the event the outbound queue created for it.
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: {
        title: 'Gelen senkron',
        calendarMirrorEnabled: true,
        scheduledStartAt: '2030-06-01T09:00:00.000Z',
        scheduledEndAt: '2030-06-01T10:00:00.000Z',
      },
    });
    expect(created.statusCode).toBe(201);
    const taskId = created.json().id;

    await vi.waitFor(
      async () => {
        expect(
          await app.db('calendar_event_links').where({ task_id: taskId }).first(),
        ).toBeTruthy();
      },
      { timeout: 8000, interval: 100 },
    );
    const link = await app.db('calendar_event_links').where({ task_id: taskId }).first();
    const eventId = link.provider_event_id;

    // 2. First full sync stores the cursor (§7.2 steps 4-5).
    app.calendarSync.enqueueSync(accountId);
    await vi.waitFor(
      async () => {
        expect((await account()).sync_token).toBeTruthy();
      },
      { timeout: 8000, interval: 100 },
    );

    // 3. The push channel opens against our (never-called) https address.
    app.calendarSync.enqueueWatch(accountId);
    await vi.waitFor(
      async () => {
        expect((await account()).webhook_channel_id).toBeTruthy();
      },
      { timeout: 8000, interval: 100 },
    );
    const channel = google.state.channels.get((await account()).webhook_channel_id);
    expect(channel.address).toBe(FAKE_WEBHOOK_URL);

    // 4. The user drags the event in Google, and Google tells us about it.
    google.state.userEdits('primary', eventId, {
      start: { dateTime: '2030-06-07T15:00:00.000Z' },
      end: { dateTime: '2030-06-07T16:00:00.000Z' },
      updated: '2035-01-01T00:00:00.000Z',
    });
    const notified = await app.inject({
      method: 'POST',
      url: WEBHOOK,
      headers: {
        'x-goog-channel-id': channel.id,
        'x-goog-channel-token': channel.token,
        'x-goog-resource-id': channel.resourceId,
        'x-goog-resource-state': 'exists',
        'x-goog-message-number': '2',
      },
    });
    expect(notified.statusCode).toBe(200);

    // 5. The queue carries it: incremental fetch → reconcile → task write.
    await vi.waitFor(
      async () => {
        const task = await app.db('tasks').where({ id: taskId }).first();
        expect(new Date(task.scheduled_start_at).toISOString()).toBe('2030-06-07T15:00:00.000Z');
        expect(new Date(task.scheduled_end_at).toISOString()).toBe('2030-06-07T16:00:00.000Z');
      },
      { timeout: 10000, interval: 100 },
    );

    // The dirty marker is consumed, and the change is a sync revision like any
    // other — every replica of this workspace will pull it (§6.2).
    await vi.waitFor(
      async () => {
        expect((await account()).sync_dirty_at).toBeNull();
      },
      { timeout: 8000, interval: 100 },
    );
    const revisions = await app
      .db('sync_revisions')
      .where({ workspace_id: owner.workspace.id, entity_type: 'task', entity_id: taskId })
      .select();
    expect(revisions.length).toBeGreaterThan(1);

    // And it settles: the mirror pass our own write triggered leaves the event
    // where the user dropped it, and the link records no conflict.
    await vi.waitFor(
      async () => {
        const fresh = await app.db('calendar_event_links').where({ task_id: taskId }).first();
        expect(fresh.conflict_status).toBe('none');
      },
      { timeout: 8000, interval: 100 },
    );
    expect(google.state.eventsIn('primary').get(eventId).start.dateTime).toBe(
      '2030-06-07T15:00:00.000Z',
    );
  });

  it('a user deleting the event stops the mirror instead of resurrecting it', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: {
        title: 'Takvimden silinen',
        calendarMirrorEnabled: true,
        dueAt: '2030-07-01T12:00:00.000Z',
      },
    });
    const taskId = created.json().id;
    await vi.waitFor(
      async () => {
        expect(
          await app.db('calendar_event_links').where({ task_id: taskId }).first(),
        ).toBeTruthy();
      },
      { timeout: 8000, interval: 100 },
    );
    const link = await app.db('calendar_event_links').where({ task_id: taskId }).first();

    google.state.userDeletes('primary', link.provider_event_id);
    app.calendarSync.enqueueSync(accountId);

    await vi.waitFor(
      async () => {
        const task = await app.db('tasks').where({ id: taskId }).first();
        expect(Boolean(task.calendar_mirror_enabled)).toBe(false);
      },
      { timeout: 10000, interval: 100 },
    );

    // The flagged link survives as the record of why we stopped — and nothing
    // recreated the event the user deliberately deleted.
    const tombstone = await app.db('calendar_event_links').where({ task_id: taskId }).first();
    expect(tombstone.conflict_status).toBe('provider_deleted_local_exists');
    expect(google.state.eventsIn('primary').has(link.provider_event_id)).toBe(false);
  });
});
