import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeGoogle, fakeGoogleEnv } from '../helpers/fakegoogle.js';
import { blockForTask, desiredEventForTask } from '../../src/lib/mirror.js';
import { readFileSync } from 'node:fs';
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

  it('never derives a backwards block from an end left behind by a moved start', () => {
    // Google rejects end <= start with a 400 the queue can never retry away,
    // so a stale scheduled_end_at falls back to the default slot.
    const event = desiredEventForTask({
      ...base,
      scheduled_start_at: '2030-06-01T14:00:00.000Z',
      scheduled_end_at: '2030-06-01T10:00:00.000Z',
    });
    expect(event.start.dateTime).toBe('2030-06-01T14:00:00.000Z');
    expect(event.end.dateTime).toBe('2030-06-01T14:30:00.000Z');
  });

  it('gives a dated task a 30-minute block, opt-in or not (round 12)', () => {
    const due = desiredEventForTask({ ...base, due_at: '2030-06-01T12:00:00.000Z' });
    expect(due.start.dateTime).toBe('2030-06-01T12:00:00.000Z');
    expect(due.end.dateTime).toBe('2030-06-01T12:30:00.000Z');

    // The switch is gone: a task nobody opted in still mirrors (ADR-0021 §1).
    const notOptedIn = desiredEventForTask({
      ...base,
      calendar_mirror_enabled: false,
      due_at: '2030-06-01T12:00:00.000Z',
    });
    expect(notOptedIn.start.dateTime).toBe('2030-06-01T12:00:00.000Z');
  });

  it('clamps a block that would cross midnight (23:59 → 23:29–23:59)', () => {
    const event = desiredEventForTask({
      ...base,
      timezone: 'UTC',
      due_at: '2030-06-01T23:59:00.000Z',
    });
    expect(event.start.dateTime).toBe('2030-06-01T23:29:00.000Z');
    expect(event.end.dateTime).toBe('2030-06-01T23:59:00.000Z');
  });

  it('puts an UNDATED task on the day it was created', () => {
    const event = desiredEventForTask({
      ...base,
      timezone: 'UTC',
      created_at: '2030-05-20T09:15:00.000Z',
    });
    expect(event.start.dateTime).toBe('2030-05-20T09:15:00.000Z');
    expect(event.end.dateTime).toBe('2030-05-20T09:45:00.000Z');
  });

  it('keeps a completed task’s block and marks it (ADR-0021 §2)', () => {
    const event = desiredEventForTask({
      ...base,
      status: 'completed',
      due_at: '2030-06-01T12:00:00.000Z',
    });
    expect(event.summary).toBe('✓ [Task] Sunum hazırla');
    expect(event.start.dateTime).toBe('2030-06-01T12:00:00.000Z');
  });

  it('matches the Apple mirror block rule, case by case (ADR-0021)', () => {
    // The same fixture apps/app/test/features/calendar/apple_mirror_test.dart
    // asserts. Two mirrors that disagree in front of the user is what DESIGN
    // §17 D1 forbids, so neither side may change this arithmetic alone.
    const fixture = JSON.parse(
      readFileSync(
        new URL('../../../app/test/fixtures/calendar_block_parity.json', import.meta.url),
        'utf8',
      ),
    );
    const wall = (date) => date.toISOString().slice(0, 16);
    for (const testCase of fixture.cases) {
      const block = blockForTask(
        { ...base, timezone: 'UTC', due_at: `${testCase.at}:00.000Z` },
        'UTC',
      );
      expect(wall(block.start), testCase.name).toBe(testCase.start);
      expect(wall(block.end), testCase.name).toBe(testCase.end);
    }
  });

  it('wants no event for withdrawn work, a deleted task, or a suppressed one', () => {
    for (const status of ['cancelled', 'archived']) {
      expect(
        desiredEventForTask({ ...base, status, due_at: '2030-06-01T12:00:00.000Z' }),
      ).toBeNull();
    }
    expect(
      desiredEventForTask({ ...base, deleted_at: new Date(), due_at: '2030-06-01T12:00:00.000Z' }),
    ).toBeNull();
    // The user deleted our event in Google; we do not put it back (§3).
    expect(
      desiredEventForTask({
        ...base,
        calendar_mirror_suppressed_at: new Date(),
        due_at: '2030-06-01T12:00:00.000Z',
      }),
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

    // Round 12 (ADR-0021 §2): completing KEEPS the block and marks it — the
    // calendar is where "what did I actually do that week" gets answered. This
    // used to assert the event and its link disappeared.
    await api('POST', `/api/v1/tasks/${taskId}/complete`);
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(1);
    expect(primaryEvents()[0].summary).toBe('✓ [Task] Takvimli iş v2');
    expect(tables.calendar_event_links).toHaveLength(1);

    // Reopening drops the mark, on the same event.
    await api('POST', `/api/v1/tasks/${taskId}/reopen`);
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(1);
    expect(primaryEvents()[0].summary).toBe('[Task] Takvimli iş v2');

    // Cancelling is different: work withdrawn loses its block.
    await api('PATCH', `/api/v1/tasks/${taskId}`, { status: 'cancelled' });
    await app.mirror.idle();
    expect(primaryEvents()).toHaveLength(0);
    expect(tables.calendar_event_links).toHaveLength(0);
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

    // Round 12 (ADR-0021 §1): a plain task with no opt-in reaches Google too —
    // that is the whole change. This used to assert the opposite.
    await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Sade iş',
      dueAt: '2030-06-01T15:00:00.000Z',
    });
    await app.mirror.idle();
    expect(google.state.eventsIn('primary').size).toBe(2);
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
