import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { spawnAfterCompletion } from '../../src/db/task-series.js';

/**
 * OPH-375 — repeat N days/weeks/months after completion (ADR-0056).
 *
 * The property this file pins: completing the open occurrence of an
 * after-completion series makes the SERVER create the next one, counted from
 * the moment it was completed — late or early — at the same time of day, and
 * uncompleting withdraws it again. Calendar series are untouched.
 *
 * The clock is injected where the code takes one; the completion moment is the
 * row's own `completed_at`, which the direct-call tests set by hand.
 */
const DAY = 86400000;
const isoDay = (ms) => new Date(ms).toISOString().slice(0, 10);
const dayAfter = (offset) => isoDay(Date.now() + offset * DAY);
const at = (offset, time = '09:00') => `${dayAfter(offset)}T${time}:00.000Z`;

let app;
let tables;
let owner;
let ws;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
  ws = owner.workspace.id;
});

afterEach(async () => {
  await app.close();
});

const inject = (method, url, payload) =>
  app.inject({ method, url: `/api/v1${url}`, headers: owner.headers, payload });

async function createTask(body) {
  const res = await inject('POST', `/workspaces/${ws}/tasks`, { timezone: 'UTC', ...body });
  expect(res.statusCode).toBe(201);
  return res.json().id;
}

async function repeat(taskId, rule, { timezone = 'UTC', anchorAt } = {}) {
  const row = tables.tasks.find((t) => t.id === taskId);
  const res = await inject('POST', `/workspaces/${ws}/task-series`, {
    rule,
    template: { title: row.title },
    timezone,
    anchorAt: anchorAt ?? new Date(row.due_at ?? row.start_at ?? Date.now()).toISOString(),
    fromTaskId: taskId,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

const complete = (id) => inject('POST', `/tasks/${id}/complete`);
const reopen = (id) => inject('POST', `/tasks/${id}/reopen`);

const liveRows = (seriesId) =>
  tables.tasks.filter((t) => t.series_id === seriesId && t.deleted_at == null);
const spawnOf = (id) => tables.tasks.find((t) => t.spawned_from_task_id === id && !t.deleted_at);
const openRows = (seriesId) =>
  liveRows(seriesId).filter((t) => !['completed', 'cancelled'].includes(t.status));

const DAILY = (interval, extra = {}) => ({
  freq: 'daily',
  interval,
  basis: 'completion',
  ...extra,
});

/** Marks a row completed at `completedAt` and runs the spawn directly. */
async function spawnAt(taskId, completedAt) {
  const row = tables.tasks.find((t) => t.id === taskId);
  row.status = 'completed';
  row.completed_at = new Date(completedAt);
  return spawnAfterCompletion(app.db, { workspaceId: ws, task: { ...row } });
}

describe('after-completion series — birth (OPH-375)', () => {
  it('adopts the task and builds no 12-month window; the sweep adds nothing', async () => {
    const taskId = await createTask({ title: 'Su filtresi', dueAt: at(3) });
    const { series, adoptedTaskId, created } = await repeat(taskId, DAILY(90));
    expect(adoptedTaskId).toBe(taskId);
    expect(created).toBe(0);
    expect(series.rule.basis).toBe('completion');
    expect(liveRows(series.id).map((t) => t.id)).toEqual([taskId]);

    expect(await app.seriesGc.sweep(new Date(Date.now() + 2 * DAY))).toBe(0);
    expect(liveRows(series.id)).toHaveLength(1);
  });

  it('adopts a task on any day — there is no pattern for it to miss', async () => {
    const taskId = await createTask({ title: 'Kombi bakımı', dueAt: at(-40) });
    const { adoptedTaskId } = await repeat(taskId, { ...DAILY(1), freq: 'monthly' });
    expect(adoptedTaskId).toBe(taskId);
  });

  it('without a task to adopt, creates exactly one occurrence on the anchor', async () => {
    const res = await inject('POST', `/workspaces/${ws}/task-series`, {
      rule: DAILY(7),
      template: { title: 'Bitkileri sula' },
      timezone: 'UTC',
      anchorAt: at(1),
    });
    expect(res.statusCode).toBe(201);
    const { series, created } = res.json();
    expect(created).toBe(1);
    const rows = liveRows(series.id);
    expect(rows).toHaveLength(1);
    expect(rows[0].due_at.toISOString()).toBe(at(1));
  });

  it('refuses yearly and pattern selectors after completion', async () => {
    const taskId = await createTask({ title: 'Yıllık', dueAt: at(1) });
    for (const rule of [
      { freq: 'yearly', interval: 1, basis: 'completion' },
      { ...DAILY(1), freq: 'weekly', byWeekday: [{ day: 'MO', ordinal: null }] },
      { ...DAILY(1), basis: 'due' },
    ]) {
      const res = await inject('POST', `/workspaces/${ws}/task-series`, {
        rule,
        template: { title: 'Yıllık' },
        timezone: 'UTC',
        anchorAt: at(1),
        fromTaskId: taskId,
      });
      expect(res.statusCode).toBe(400);
      expect(res.json().code).toBe('TASK_SERIES_RULE_INVALID');
    }
  });
});

describe('after-completion series — completing (OPH-375)', () => {
  it('completing LATE counts from today, not from the old due date', async () => {
    const tag = (await inject('POST', `/workspaces/${ws}/tags`, { name: 'ev' })).json();
    const taskId = await createTask({
      title: 'Filtreyi değiştir',
      dueAt: at(-10),
      priority: 'high',
      description: 'mutfak',
      estimatedMinutes: 15,
      tagIds: [tag.id],
    });
    await repeat(taskId, DAILY(3));
    expect((await complete(taskId)).statusCode).toBe(200);

    const next = spawnOf(taskId);
    expect(next).toBeTruthy();
    expect(next.status).toBe('open');
    expect(new Date(next.due_at).toISOString()).toBe(at(3)); // today + 3, 09:00
    expect(new Date(next.due_at).toISOString()).not.toBe(at(-7)); // not due + 3
    expect(next).toMatchObject({
      title: 'Filtreyi değiştir',
      priority: 'high',
      description: 'mutfak',
      estimated_minutes: 15,
    });
    expect(tables.task_tags.filter((t) => t.task_id === next.id).map((t) => t.tag_id)).toEqual([
      tag.id,
    ]);
  });

  it('completing EARLY counts from today too, and bumps the slot it collides with', async () => {
    const taskId = await createTask({ title: 'Günlük', dueAt: at(1) });
    const { series } = await repeat(taskId, DAILY(1));
    expect((await complete(taskId)).statusCode).toBe(200);

    const next = spawnOf(taskId);
    // Due tomorrow 09:00 — the same day the completed one held.
    expect(new Date(next.due_at).toISOString()).toBe(at(1));
    expect(next.occurrence_date).toBe(dayAfter(2));
    expect(openRows(series.id)).toHaveLength(1);
  });

  it('uncompleting withdraws the spawned occurrence and its alarm; re-completing spawns once', async () => {
    const taskId = await createTask({
      title: 'Hap',
      dueAt: at(0, '20:00'),
      remindAt: at(0, '19:30'),
    });
    const { series } = await repeat(taskId, DAILY(2));
    await complete(taskId);
    const first = spawnOf(taskId);
    expect(new Date(first.remind_at).toISOString()).toBe(at(2, '19:30'));
    const alarm = tables.reminders.find((r) => r.task_id === first.id);
    expect(alarm?.status).toBe('scheduled');

    expect((await reopen(taskId)).statusCode).toBe(200);
    const withdrawn = tables.tasks.find((t) => t.id === first.id);
    expect(withdrawn.deleted_at).toBeTruthy();
    expect(withdrawn.occurrence_date).toBeNull(); // the slot is free again
    expect(tables.reminders.find((r) => r.id === alarm.id).status).toBe('cancelled');
    expect(openRows(series.id).map((t) => t.id)).toEqual([taskId]);

    expect((await complete(taskId)).statusCode).toBe(200);
    const second = spawnOf(taskId);
    expect(second.id).not.toBe(first.id);
    expect(second.occurrence_date).toBe(dayAfter(2));
    expect(openRows(series.id)).toHaveLength(1);
  });

  it('reopening an old occurrence never withdraws a successor that is already done', async () => {
    const taskId = await createTask({ title: 'Haftalık', dueAt: at(0) });
    const { series } = await repeat(taskId, DAILY(7));
    await complete(taskId);
    const second = spawnOf(taskId);
    await complete(second.id);
    const third = spawnOf(second.id);

    await reopen(taskId);
    expect(tables.tasks.find((t) => t.id === second.id).deleted_at).toBeFalsy();
    expect(tables.tasks.find((t) => t.id === third.id).deleted_at).toBeFalsy();
    // Completing the old one again finds its successor and spawns nothing.
    await complete(taskId);
    expect(liveRows(series.id)).toHaveLength(3);
  });

  it('a second completion of the same occurrence spawns nothing more', async () => {
    const taskId = await createTask({ title: 'İki kere', dueAt: at(0) });
    const { series } = await repeat(taskId, DAILY(5));
    const patch = (body) => inject('PATCH', `/tasks/${taskId}`, body);
    expect((await patch({ status: 'completed' })).statusCode).toBe(200);
    expect((await patch({ status: 'completed', title: 'İki kere!' })).statusCode).toBe(200);
    expect(liveRows(series.id)).toHaveLength(2);
    // And the direct path agrees: a successor already exists.
    const row = tables.tasks.find((t) => t.id === taskId);
    expect(await spawnAfterCompletion(app.db, { workspaceId: ws, task: row })).toBeNull();
  });

  it('cancelling does not advance the series', async () => {
    const taskId = await createTask({ title: 'İptal', dueAt: at(0) });
    const { series } = await repeat(taskId, DAILY(5));
    await inject('PATCH', `/tasks/${taskId}`, { status: 'cancelled' });
    expect(liveRows(series.id)).toHaveLength(1);
  });

  it('copies an edit made to the open occurrence forward', async () => {
    const taskId = await createTask({ title: 'Eski ad', dueAt: at(0) });
    await repeat(taskId, DAILY(1));
    await inject('PATCH', `/tasks/${taskId}`, { title: 'Yeni ad', priority: 'low' });
    await complete(taskId);
    expect(spawnOf(taskId)).toMatchObject({ title: 'Yeni ad', priority: 'low' });
  });
});

describe('after-completion series — calendar math on the row (OPH-375)', () => {
  it('a month after Jan 31 is Feb 28, at the original time', async () => {
    const taskId = await createTask({ title: 'Ay sonu', dueAt: '2027-01-31T15:45:00.000Z' });
    await repeat(taskId, { ...DAILY(1), freq: 'monthly' });
    const next = await spawnAt(taskId, '2027-01-31T12:00:00.000Z');
    expect(new Date(next.due_at).toISOString()).toBe('2027-02-28T15:45:00.000Z');
    expect(next.occurrence_date).toBe('2027-02-28');
  });

  it('keeps 09:00 local across the October DST change (Europe/Berlin)', async () => {
    // Due Fri 23 Oct 2026 09:00 CEST (07:00Z); completed Sat 24 Oct.
    const taskId = await createTask({
      title: 'Berlin',
      dueAt: '2026-10-23T07:00:00.000Z',
      timezone: 'Europe/Berlin',
    });
    await repeat(taskId, DAILY(2), { timezone: 'Europe/Berlin' });
    const next = await spawnAt(taskId, '2026-10-24T10:00:00.000Z');
    // Mon 26 Oct 09:00 CET is 08:00Z — the wall clock held, the offset moved.
    expect(new Date(next.due_at).toISOString()).toBe('2026-10-26T08:00:00.000Z');
    expect(next.timezone).toBe('Europe/Berlin');
  });

  it('reads the completion day on the series clock, not in UTC', async () => {
    const taskId = await createTask({
      title: 'Gece yarısı',
      dueAt: '2026-10-24T07:00:00.000Z',
      timezone: 'Europe/Berlin',
    });
    await repeat(taskId, DAILY(1), { timezone: 'Europe/Berlin' });
    // 22:30Z on Oct 24 is 00:30 on Oct 25 in Berlin.
    const next = await spawnAt(taskId, '2026-10-24T22:30:00.000Z');
    expect(next.occurrence_date).toBe('2026-10-26');
    expect(new Date(next.due_at).toISOString()).toBe('2026-10-26T08:00:00.000Z');
  });

  it('keeps the day gap between When and the due date', async () => {
    const taskId = await createTask({
      title: 'Hazırlık',
      startAt: '2026-10-20T00:00:00.000Z',
      dueAt: '2026-10-22T17:00:00.000Z',
    });
    await repeat(taskId, DAILY(10));
    const next = await spawnAt(taskId, '2026-10-21T08:00:00.000Z');
    expect(new Date(next.due_at).toISOString()).toBe('2026-10-31T17:00:00.000Z');
    expect(new Date(next.start_at).toISOString()).toBe('2026-10-29T00:00:00.000Z');
  });

  it('moves a When-only task by its When day and invents no deadline', async () => {
    const taskId = await createTask({ title: 'Ne zaman', startAt: '2026-10-20T00:00:00.000Z' });
    await repeat(taskId, DAILY(7));
    const next = await spawnAt(taskId, '2026-10-21T08:00:00.000Z');
    expect(next.due_at).toBeNull();
    expect(new Date(next.start_at).toISOString()).toBe('2026-10-28T00:00:00.000Z');
  });

  it('keeps the alarm offset from the due time', async () => {
    const taskId = await createTask({
      title: 'Alarm',
      dueAt: '2026-10-22T17:00:00.000Z',
      remindAt: '2026-10-22T15:30:00.000Z',
    });
    await repeat(taskId, DAILY(1));
    const next = await spawnAt(taskId, '2026-10-22T18:00:00.000Z');
    expect(new Date(next.remind_at).toISOString()).toBe('2026-10-23T15:30:00.000Z');
    expect(tables.reminders.some((r) => r.task_id === next.id && r.status === 'scheduled')).toBe(
      true,
    );
  });

  it('stops at end.count and at end.until', async () => {
    const counted = await createTask({ title: 'İki kez', dueAt: '2026-10-20T09:00:00.000Z' });
    await repeat(counted, DAILY(1, { end: { type: 'count', count: 2 } }));
    const second = await spawnAt(counted, '2026-10-20T10:00:00.000Z');
    expect(second).toBeTruthy();
    expect(await spawnAt(second.id, '2026-10-21T10:00:00.000Z')).toBeNull();

    const until = await createTask({ title: 'Sona kadar', dueAt: '2026-10-20T09:00:00.000Z' });
    await repeat(until, DAILY(5, { end: { type: 'until', until: '2026-10-24' } }));
    expect(await spawnAt(until, '2026-10-20T10:00:00.000Z')).toBeNull();
  });
});

describe('after-completion series — the rest of the series model (OPH-375)', () => {
  it('a deleted head is never resurrected by the sweep', async () => {
    const taskId = await createTask({ title: 'Silinecek', dueAt: at(1) });
    const { series } = await repeat(taskId, DAILY(1));
    expect((await inject('DELETE', `/tasks/${taskId}`)).statusCode).toBe(204);
    expect(await app.seriesGc.sweep(new Date(Date.now() + 3 * DAY))).toBe(0);
    expect(liveRows(series.id)).toHaveLength(0);
  });

  it('stopping the repeat keeps the open occurrence as an ordinary task', async () => {
    const taskId = await createTask({ title: 'Filtre', dueAt: at(3) });
    const { series } = await repeat(taskId, DAILY(90));
    const stopped = await inject('DELETE', `/task-series/${series.id}`);
    expect(stopped.statusCode).toBe(200);
    expect(stopped.json().removed).toBe(0);
    const row = tables.tasks.find((t) => t.id === taskId);
    expect(row.deleted_at ?? null).toBeNull();
    // Detached: the Repeat switch reads off and the slot is gone.
    expect(row.series_id).toBeNull();
    expect(row.occurrence_date).toBeNull();
    // Completing it now creates nothing: the series is gone.
    await complete(taskId);
    expect(spawnOf(taskId)).toBeUndefined();

    // An explicit fromDay (the app deleting the head and stopping in one
    // commit) still reaches the open occurrence.
    const other = await createTask({ title: 'Silinip durdurulan', dueAt: at(3) });
    const second = await repeat(other, DAILY(90));
    const res = await inject('DELETE', `/task-series/${second.series.id}?fromDay=${dayAfter(3)}`);
    expect(res.json().removed).toBe(1);
  });

  it('leaves a calendar series exactly as it was: completing spawns nothing', async () => {
    const res = await inject('POST', `/workspaces/${ws}/task-series`, {
      rule: { freq: 'monthly', interval: 1, byMonthDay: [31] },
      template: { title: 'Kira' },
      timezone: 'UTC',
      anchorAt: at(0),
    });
    const { series } = res.json();
    const before = tables.tasks.length;
    const first = liveRows(series.id)[0];
    await complete(first.id);
    expect(tables.tasks.length).toBe(before);
    expect(tables.tasks.some((t) => t.spawned_from_task_id)).toBe(false);
  });

  it('switching a calendar series to after-completion keeps exactly one open occurrence', async () => {
    const res = await inject('POST', `/workspaces/${ws}/task-series`, {
      rule: { freq: 'weekly', interval: 1 },
      template: { title: 'Haftalık' },
      timezone: 'UTC',
      anchorAt: at(1),
    });
    const { series } = res.json();
    expect(openRows(series.id).length).toBeGreaterThan(40);

    const patched = await inject('PATCH', `/task-series/${series.id}`, {
      rule: { freq: 'weekly', interval: 1, basis: 'completion' },
    });
    expect(patched.statusCode).toBe(200);
    const open = openRows(series.id);
    expect(open).toHaveLength(1);
    expect(open[0].occurrence_date).toBe(dayAfter(1));

    await complete(open[0].id);
    expect(new Date(spawnOf(open[0].id).due_at).toISOString()).toBe(at(7));
    expect(await app.seriesGc.sweep(new Date(Date.now() + 2 * DAY))).toBe(0);
  });

  it('a scoped "all" edit never rewrites an after-completion rule', async () => {
    const taskId = await createTask({ title: 'Kapsam', dueAt: at(1) });
    const { series } = await repeat(taskId, DAILY(4));
    const res = await inject('PATCH', `/tasks/${taskId}`, {
      dueAt: at(3, '10:00'),
      seriesScope: 'all',
    });
    expect(res.statusCode).toBe(200);
    const stored = tables.task_series.find((s) => s.id === series.id);
    expect(JSON.parse(stored.rule)).toEqual(DAILY(4));
  });
});
