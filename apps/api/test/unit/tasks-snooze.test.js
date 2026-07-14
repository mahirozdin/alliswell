import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { zonedWallTimeToUtc, nextMorningIn } from '../../src/lib/time.js';

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const REMIND_AT = '2026-07-20T08:30:00.000Z';

const createTask = async (payload) => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
    headers: owner.headers,
    payload,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
};

const snooze = (taskId, payload) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/tasks/${taskId}/snooze`,
    headers: owner.headers,
    payload,
  });

const wallClockIn = (iso, timeZone) =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone,
    hourCycle: 'h23',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

describe('lib/time (OPH-035)', () => {
  it('converts wall-clock times to UTC instants (fixed and DST zones)', () => {
    // Istanbul is UTC+3 year-round.
    expect(
      zonedWallTimeToUtc(
        { year: 2026, month: 7, day: 15, hour: 9 },
        'Europe/Istanbul',
      ).toISOString(),
    ).toBe('2026-07-15T06:00:00.000Z');
    // New York in July is EDT (UTC-4).
    expect(
      zonedWallTimeToUtc(
        { year: 2026, month: 7, day: 15, hour: 9 },
        'America/New_York',
      ).toISOString(),
    ).toBe('2026-07-15T13:00:00.000Z');
  });

  it('nextMorningIn lands on 09:00 tomorrow on that zone wall clock', () => {
    const from = new Date('2026-07-14T22:30:00.000Z'); // 01:30 (Jul 15) in Istanbul
    const morning = nextMorningIn('Europe/Istanbul', from);
    expect(morning.toISOString()).toBe('2026-07-16T06:00:00.000Z'); // 09:00 Jul 16 TRT
  });
});

describe('POST /tasks/:id/snooze (OPH-035)', () => {
  it('preset 5_min snoozes the task AND its live reminder', async () => {
    const task = await createTask({ title: 'Alarmlı', remindAt: REMIND_AT });
    const before = Date.now();

    const res = await snooze(task.id, { preset: '5_min' });
    expect(res.statusCode).toBe(200);

    const until = new Date(res.json().snoozedUntil).getTime();
    expect(until).toBeGreaterThanOrEqual(before + 5 * 60 * 1000 - 1000);
    expect(until).toBeLessThanOrEqual(Date.now() + 5 * 60 * 1000 + 1000);

    const reminder = tables.reminders[0];
    expect(reminder.status).toBe('snoozed');
    expect(new Date(reminder.snoozed_until).getTime()).toBe(until);
    // Both entities logged their own sync revision.
    const ops = tables.sync_revisions.slice(-2).map((r) => r.entity_type);
    expect(ops.sort()).toEqual(['reminder', 'task']);
  });

  it('tomorrow_morning computes 09:00 on the TASK timezone wall clock', async () => {
    const task = await createTask({
      title: 'NY görevi',
      remindAt: REMIND_AT,
      timezone: 'America/New_York',
    });

    const res = await snooze(task.id, { preset: 'tomorrow_morning' });
    expect(res.statusCode).toBe(200);
    expect(wallClockIn(res.json().snoozedUntil, 'America/New_York')).toBe('09:00');
    // And it is strictly in the future.
    expect(new Date(res.json().snoozedUntil).getTime()).toBeGreaterThan(Date.now());
  });

  it('accepts an explicit future snoozeUntil, rejects past and ambiguous bodies', async () => {
    const task = await createTask({ title: 'Elle' });
    const future = new Date(Date.now() + 45 * 60 * 1000).toISOString();

    const ok = await snooze(task.id, { snoozeUntil: future });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().snoozedUntil).toBe(future);

    const past = await snooze(task.id, { snoozeUntil: '2020-01-01T00:00:00.000Z' });
    expect(past.statusCode).toBe(400);
    expect(past.json()).toMatchObject({ code: 'TASK_SNOOZE_IN_PAST' });

    expect((await snooze(task.id, {})).statusCode).toBe(400);
    expect((await snooze(task.id, { preset: '5_min', snoozeUntil: future })).statusCode).toBe(400);
    expect((await snooze(task.id, { preset: '2_days' })).statusCode).toBe(400);
  });

  it('snoozing works without a reminder and refuses terminal tasks', async () => {
    const bare = await createTask({ title: 'Alarmsız' });
    expect((await snooze(bare.id, { preset: '30_min' })).statusCode).toBe(200);
    expect(tables.reminders).toHaveLength(0);

    await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${bare.id}/complete`,
      headers: owner.headers,
    });
    const done = await snooze(bare.id, { preset: '5_min' });
    expect(done.statusCode).toBe(409);
    expect(done.json()).toMatchObject({ code: 'TASK_INVALID_TRANSITION' });
  });

  it('a title patch preserves the snooze; moving remindAt re-arms', async () => {
    const task = await createTask({ title: 'Uykucu', remindAt: REMIND_AT });
    await snooze(task.id, { preset: '1_hour' });
    expect(tables.reminders[0].status).toBe('snoozed');

    await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
      payload: { title: 'Hâlâ uykuda' },
    });
    expect(tables.reminders[0].status).toBe('snoozed'); // regression guard

    await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
      payload: { remindAt: '2026-07-21T10:00:00.000Z' },
    });
    expect(tables.reminders[0].status).toBe('scheduled');
    expect(tables.reminders[0].snoozed_until).toBeNull();
  });
});
