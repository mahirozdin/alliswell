import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL + Redis with migrations applied — exercises the real
// reminders enum columns and DATETIME(3) round-trips.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph034-${Date.now()}`;

describe.runIf(enabled)('integration: reminder lifecycle follows the task', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-7' },
    });
    const body = res.json();
    owner = {
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('spawns, re-arms, completes and re-creates the reminder with the task', async () => {
    const remindAt = '2026-07-22T06:45:00.000Z';
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: { title: 'Alarmlı entegrasyon', remindAt, isUrgent: true },
    });
    expect(created.statusCode).toBe(201);
    const task = created.json();
    expect(task.requiresAcknowledgement).toBe(true); // urgent default

    let reminder = await app.db('reminders').where({ task_id: task.id }).first();
    expect(reminder.status).toBe('scheduled');
    expect(reminder.alarm_level).toBe('urgent');
    expect(new Date(reminder.remind_at).toISOString()).toBe(remindAt);

    // Completing the task closes the alarm.
    await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/complete`,
      headers: owner.headers,
    });
    reminder = await app.db('reminders').where({ id: reminder.id }).first();
    expect(reminder.status).toBe('completed');

    // Reopening re-arms (remind_at survived on the task).
    await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/reopen`,
      headers: owner.headers,
    });
    const active = await app
      .db('reminders')
      .where({ task_id: task.id, status: 'scheduled' })
      .select();
    expect(active).toHaveLength(1);
  });

  it('snooze presets update the task and the reminder row together (OPH-035)', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: { title: 'Ertele beni', remindAt: '2026-07-23T05:00:00.000Z' },
    });
    const task = created.json();

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/snooze`,
      headers: owner.headers,
      payload: { preset: 'tomorrow_morning' },
    });
    expect(res.statusCode).toBe(200);
    const until = new Date(res.json().snoozedUntil);
    expect(until.getTime()).toBeGreaterThan(Date.now());

    const reminder = await app.db('reminders').where({ task_id: task.id }).first();
    expect(reminder.status).toBe('snoozed');
    expect(new Date(reminder.snoozed_until).getTime()).toBe(until.getTime());

    const row = await app.db('tasks').where({ id: task.id }).first('snoozed_until', 'timezone');
    expect(new Date(row.snoozed_until).getTime()).toBe(until.getTime());
    // 09:00 on the task's wall clock (default Europe/Istanbul = UTC+3).
    expect(until.toISOString()).toMatch(/T06:00:00/);
  });

  // OPH-175 (round 9): against real MySQL — the enum column, the backfill's
  // shape and the two independent rows. Unit tests prove the logic on fakedb;
  // this proves the SCHEMA (enum values, no unique index in the way).
  it('an urgent task with both times owns two reminder rows, and sync carries the kind', async () => {
    const remindAt = '2026-07-24T18:42:00.000Z';
    const dueAt = '2026-07-24T18:45:00.000Z';
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: { title: 'İki alarmlı entegrasyon', remindAt, dueAt, isUrgent: true },
    });
    expect(created.statusCode).toBe(201);
    const task = created.json();

    const rows = await app.db('reminders').where({ task_id: task.id }).select();
    // Sorted in JS on purpose: MySQL orders an ENUM by its DECLARATION index
    // (remind, due), not alphabetically — a real-schema detail fakedb cannot show.
    expect(rows.map((r) => r.kind).sort()).toEqual(['due', 'remind']);
    const byKind = Object.fromEntries(rows.map((r) => [r.kind, r]));
    expect(new Date(byKind.remind.remind_at).toISOString()).toBe(remindAt);
    expect(new Date(byKind.due.remind_at).toISOString()).toBe(dueAt);
    expect(byKind.due.alarm_level).toBe('urgent');

    // The replica has to be able to tell them apart.
    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=0&limit=500`,
      headers: owner.headers,
    });
    expect(pull.statusCode).toBe(200);
    const kinds = pull
      .json()
      .changes.filter((c) => c.entityType === 'reminder' && c.data?.taskId === task.id)
      .map((c) => c.data.kind)
      .sort();
    expect(kinds).toEqual(['due', 'remind']);

    // Snoozing the task silences BOTH; naming one silences only it.
    const snoozed = await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/snooze`,
      headers: owner.headers,
      payload: { preset: '30_min' },
    });
    expect(snoozed.statusCode).toBe(200);
    const afterSnooze = await app.db('reminders').where({ task_id: task.id }).select();
    expect(afterSnooze.every((r) => r.status === 'snoozed')).toBe(true);
  });
});
