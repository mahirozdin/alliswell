import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeGoogle, fakeGoogleEnv } from '../helpers/fakegoogle.js';
import { desiredEventForTask } from '../../src/lib/mirror.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';

const KEY = 'c'.repeat(64);

describe('lib/mirror desiredEventForTask (OPH-072, §7.1)', () => {
  const base = {
    id: 'T'.padEnd(26, '0'),
    workspace_id: 'W'.padEnd(26, '0'),
    project_id: null,
    title: 'Sunum hazırla',
    status: 'open',
    calendar_mirror_enabled: true,
    is_urgent: false,
    revision: 3,
    deleted_at: null,
    scheduled_start_at: null,
    scheduled_end_at: null,
    due_at: null,
    remind_at: null,
  };

  it('mirrors a scheduled block verbatim, with the ADR-0003 mapping keys', () => {
    const event = desiredEventForTask({
      ...base,
      scheduled_start_at: '2030-06-01T09:00:00.000Z',
      scheduled_end_at: '2030-06-01T10:30:00.000Z',
      project_id: 'P'.padEnd(26, '0'),
    });
    expect(event).toMatchObject({
      summary: '[Task] Sunum hazırla',
      start: { dateTime: '2030-06-01T09:00:00.000Z' },
      end: { dateTime: '2030-06-01T10:30:00.000Z' },
    });
    expect(event.extendedProperties.private).toMatchObject({
      alliswell_task_id: base.id,
      alliswell_workspace_id: base.workspace_id,
      alliswell_project_id: 'P'.padEnd(26, '0'),
      alliswell_source: 'alliswell',
      alliswell_revision: '3',
    });
  });

  it('falls back: due slot, then urgent reminder block, both 30 minutes', () => {
    const due = desiredEventForTask({ ...base, due_at: '2030-06-01T12:00:00.000Z' });
    expect(due.start.dateTime).toBe('2030-06-01T12:00:00.000Z');
    expect(due.end.dateTime).toBe('2030-06-01T12:30:00.000Z');

    const urgent = desiredEventForTask({
      ...base,
      is_urgent: true,
      remind_at: '2030-06-01T08:00:00.000Z',
    });
    expect(urgent.start.dateTime).toBe('2030-06-01T08:00:00.000Z');

    // A non-urgent reminder alone is NOT a calendar block (§7.1).
    expect(desiredEventForTask({ ...base, remind_at: '2030-06-01T08:00:00.000Z' })).toBeNull();
  });

  it('wants no event without opt-in, time, or a live task', () => {
    expect(desiredEventForTask({ ...base })).toBeNull(); // no time source
    expect(
      desiredEventForTask({
        ...base,
        calendar_mirror_enabled: false,
        due_at: '2030-06-01T12:00:00.000Z',
      }),
    ).toBeNull();
    for (const status of ['completed', 'cancelled', 'archived']) {
      expect(
        desiredEventForTask({ ...base, status, due_at: '2030-06-01T12:00:00.000Z' }),
      ).toBeNull();
    }
    expect(
      desiredEventForTask({ ...base, deleted_at: new Date(), due_at: '2030-06-01T12:00:00.000Z' }),
    ).toBeNull();
  });
});

describe('mirror worker end to end (OPH-072/073)', () => {
  let google;
  let app;
  let tables;
  let owner;

  beforeEach(async () => {
    google = await startFakeGoogle();
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      CALENDAR_TOKEN_KEY: KEY,
      ...fakeGoogleEnv(google.url),
    });
    ({ app, tables } = await buildTestApp({ config }));
    owner = await registerUser(app, { email: 'owner@example.com' });

    // A connected, calendar-selected account (the OAuth flow has its own suite).
    const accessToken = 'at-seeded';
    google.state.issuedTokens.add(accessToken);
    tables.calendar_accounts.push({
      id: newId(),
      user_id: owner.user.id,
      workspace_id: owner.workspace.id,
      provider: 'google',
      provider_account_id: 'takvim@example.com',
      encrypted_access_token: encryptSecret(accessToken, KEY),
      encrypted_refresh_token: encryptSecret('rt-1', KEY),
      token_expires_at: new Date(Date.now() + 3600_000),
      default_calendar_id: 'primary',
      status: 'active',
      deleted_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    });
  });

  afterEach(async () => {
    await app.close();
    await google.app.close();
  });

  const api = (method, url, payload) =>
    app.inject({ method, url, headers: owner.headers, payload });

  const primaryEvents = () => [...google.state.eventsIn('primary').values()];

  it('creates, updates and removes the event across the task lifecycle', async () => {
    const created = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Takvimli iş',
      calendarMirrorEnabled: true,
      scheduledStartAt: '2030-06-01T09:00:00.000Z',
      scheduledEndAt: '2030-06-01T10:00:00.000Z',
    });
    expect(created.statusCode).toBe(201);
    expect(created.json().calendarMirrorEnabled).toBe(true);
    const taskId = created.json().id;
    await app.mirror.idle();

    expect(primaryEvents()).toHaveLength(1);
    const event = primaryEvents()[0];
    expect(event.summary).toBe('[Task] Takvimli iş');
    expect(event.extendedProperties.private.alliswell_task_id).toBe(taskId);
    const link = tables.calendar_event_links[0];
    expect(link).toMatchObject({
      task_id: taskId,
      provider: 'google',
      provider_calendar_id: 'primary',
      provider_event_id: event.id,
    });

    // Retitle + move → same event id, new content.
    await api('PATCH', `/api/v1/tasks/${taskId}`, {
      title: 'Takvimli iş v2',
      scheduledStartAt: '2030-06-02T09:00:00.000Z',
    });
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(1);
    expect(primaryEvents()[0].id).toBe(event.id);
    expect(primaryEvents()[0].summary).toBe('[Task] Takvimli iş v2');
    expect(primaryEvents()[0].start.dateTime).toBe('2030-06-02T09:00:00.000Z');

    // Completing removes the event and the link.
    await api('POST', `/api/v1/tasks/${taskId}/complete`);
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(0);
    expect(tables.calendar_event_links).toHaveLength(0);

    // Reopening brings it back as a fresh event.
    await api('POST', `/api/v1/tasks/${taskId}/reopen`);
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(1);
  });

  it('re-links to an existing foreign event instead of duplicating (OPH-073)', async () => {
    const created = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Önceden aynalanmış',
      calendarMirrorEnabled: true,
      dueAt: '2030-06-01T12:00:00.000Z',
    });
    const taskId = created.json().id;
    // Simulate a lost link row: the event exists in Google with our task id.
    google.state.eventsIn('primary').set('ev-preexisting', {
      id: 'ev-preexisting',
      etag: '"old"',
      summary: '[Task] Önceden aynalanmış',
      extendedProperties: { private: { alliswell_task_id: taskId } },
    });
    tables.calendar_event_links.length = 0; // drop whatever create produced
    google.state.eventsIn('primary').forEach((v, k) => {
      if (k !== 'ev-preexisting') google.state.eventsIn('primary').delete(k);
    });

    await api('PATCH', `/api/v1/tasks/${taskId}`, { title: 'Önceden aynalanmış v2' });
    await app.mirror.idle();

    expect(primaryEvents()).toHaveLength(1); // adopted, not duplicated
    expect(primaryEvents()[0].id).toBe('ev-preexisting');
    expect(primaryEvents()[0].summary).toBe('[Task] Önceden aynalanmış v2');
    expect(tables.calendar_event_links.at(-1).provider_event_id).toBe('ev-preexisting');
  });

  it('recreates when Google lost the event, and ignores non-mirrored tasks', async () => {
    const created = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Kaybolan etkinlik',
      calendarMirrorEnabled: true,
      dueAt: '2030-06-01T12:00:00.000Z',
    });
    const taskId = created.json().id;
    await app.mirror.idle();
    const firstId = primaryEvents()[0].id;

    google.state.eventsIn('primary').clear(); // deleted on Google's side
    await api('PATCH', `/api/v1/tasks/${taskId}`, { priority: 'high' });
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(1);
    expect(primaryEvents()[0].id).not.toBe(firstId);

    // A plain task (no opt-in) never reaches Google.
    const callsBefore = google.state.seq;
    await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Sade iş',
      dueAt: '2030-06-01T15:00:00.000Z',
    });
    await app.mirror.idle();
    expect(google.state.eventsIn('primary').size).toBe(1);
    expect(google.state.seq).toBe(callsBefore);
  });

  it('choosing a default calendar backfills mirror-enabled tasks (sweep)', async () => {
    const account = tables.calendar_accounts[0];
    account.default_calendar_id = null; // not chosen yet → no mirroring

    const created = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Bekleyen aynalama',
      calendarMirrorEnabled: true,
      dueAt: '2030-06-01T12:00:00.000Z',
    });
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(0);

    const res = await api('PATCH', `/api/v1/integrations/google/accounts/${account.id}`, {
      defaultCalendarId: 'primary',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().defaultCalendarId).toBe('primary');
    await app.mirror.idle();

    expect(primaryEvents()).toHaveLength(1);
    expect(primaryEvents()[0].extendedProperties.private.alliswell_task_id).toBe(created.json().id);
  });
});
