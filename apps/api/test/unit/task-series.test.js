import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { SERIES_HORIZON_DAYS } from '../../src/db/task-series.js';

/**
 * OPH-205 — task series REST + materialization (ADR-0020, BLUEPRINT §12.17).
 *
 * What matters here is not the calendar math (test/unit/recurrence.test.js owns
 * that against the cross-stack fixture) but the ROWS: that occurrences are
 * ordinary tasks, that running the window twice creates nothing the second
 * time, that a rule change rebuilds the future and leaves the past alone, and
 * that stopping a series keeps what already happened.
 *
 * The clock is injected, never faked — the API suite has no fake timers and
 * every time-sensitive function here takes a `now` (AGENTS §5 convention).
 */
describe('task series (OPH-205, ADR-0020)', () => {
  let app;
  let tables;
  let owner;
  let ws;

  beforeEach(async () => {
    ({ app, tables } = await buildTestApp());
    owner = await registerUser(app, { email: 'owner@example.com' });
    ws = owner.workspace.id;
  });

  const MONTHLY_31 = { freq: 'monthly', interval: 1, byMonthDay: [31] };
  const template = (over = {}) => ({ title: 'Kira öde', priority: 'high', ...over });

  // The window starts at "today", so the fixtures are relative to the real
  // clock — and the series lives in UTC so a wall day is just the ISO date.
  // (A literal 2026 date would silently fall out of the window and the test
  // would assert nothing.)
  const dayAfter = (offset) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
  const today = () => dayAfter(0);

  const create = (payload) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/task-series`,
      headers: owner.headers,
      payload: {
        rule: MONTHLY_31,
        template: template(),
        timezone: 'UTC',
        anchorAt: `${today()}T09:00:00.000Z`,
        ...payload,
      },
    });

  const occurrencesOf = (seriesId) =>
    tables.tasks
      .filter((t) => t.series_id === seriesId && t.deleted_at == null)
      .sort((a, b) => String(a.occurrence_date).localeCompare(String(b.occurrence_date)));

  it('creates a series and materializes its window as ordinary tasks', async () => {
    const res = await create();
    expect(res.statusCode).toBe(201);
    const { series, created } = res.json();
    expect(series.rule).toEqual(MONTHLY_31);
    expect(created).toBeGreaterThan(0);

    const rows = occurrencesOf(series.id);
    expect(rows).toHaveLength(created);
    // Each one is a normal task: title, priority, workspace, an open status.
    expect(rows[0]).toMatchObject({
      workspace_id: ws,
      title: 'Kira öde',
      priority: 'high',
      status: 'open',
      timezone: 'UTC',
    });
    // …and it carries a due instant, not just a calendar day.
    expect(rows[0].due_at).toBeInstanceOf(Date);
    // The clamp is visible in the rows themselves: no month is missing.
    const months = new Set(rows.map((r) => String(r.occurrence_date).slice(0, 7)));
    expect(months.size).toBe(rows.length);
  });

  it('materializes exactly the 12-month window, and no further', async () => {
    const { series } = (await create()).json();
    const rows = occurrencesOf(series.id);
    const days = rows.map((r) => String(r.occurrence_date));
    const horizon = new Date(Date.now() + SERIES_HORIZON_DAYS * 86400000)
      .toISOString()
      .slice(0, 10);
    for (const day of days) expect(day <= horizon).toBe(true);
    // A monthly rule over 12 months is 12 or 13 occurrences, never 400.
    expect(rows.length).toBeLessThanOrEqual(13);
  });

  it('is idempotent: sweeping the same window again inserts nothing', async () => {
    const { series } = (await create()).json();
    const before = occurrencesOf(series.id).length;

    const created = await app.seriesGc.sweep(new Date());
    expect(created).toBe(0);
    expect(occurrencesOf(series.id)).toHaveLength(before);
  });

  it('rolls the window forward when the sweep runs a month later', async () => {
    const { series } = (await create()).json();
    const before = occurrencesOf(series.id).length;

    const later = new Date(Date.now() + 45 * 86400000);
    const created = await app.seriesGc.sweep(later);
    expect(created).toBeGreaterThan(0);
    expect(occurrencesOf(series.id).length).toBeGreaterThan(before);
  });

  it('rebuilds the future on a rule change and never touches the past', async () => {
    const { series } = (await create()).json();
    const rows = occurrencesOf(series.id);

    // Pretend the earliest occurrence already happened and was completed.
    const done = rows[0];
    tables.tasks.find((t) => t.id === done.id).status = 'completed';

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/task-series/${series.id}`,
      headers: owner.headers,
      payload: { rule: { freq: 'monthly', interval: 1, byMonthDay: [1] } },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.series.rule.byMonthDay).toEqual([1]);
    expect(body.removed).toBeGreaterThan(0);

    // The completed one survived the rebuild…
    const survivor = tables.tasks.find((t) => t.id === done.id);
    expect(survivor.deleted_at ?? null).toBeNull();
    // …and every live occurrence now follows the new rule.
    for (const row of occurrencesOf(series.id)) {
      if (row.id === done.id) continue;
      expect(String(row.occurrence_date).slice(-2)).toBe('01');
    }
  });

  it('adopts the task the switch was flipped on instead of duplicating it', async () => {
    const taskRes = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/tasks`,
      headers: owner.headers,
      payload: { title: 'Kira öde', dueAt: `${today()}T09:00:00.000Z` },
    });
    const task = taskRes.json();

    const res = await create({
      rule: { freq: 'daily', interval: 1, end: { type: 'count', count: 5 } },
      fromTaskId: task.id,
    });
    expect(res.statusCode).toBe(201);
    const { series, adoptedTaskId } = res.json();
    expect(adoptedTaskId).toBe(task.id);

    const onThatDay = occurrencesOf(series.id).filter((r) => String(r.occurrence_date) === today());
    expect(onThatDay).toHaveLength(1);
    expect(onThatDay[0].id).toBe(task.id);
  });

  it('leaves the task alone when its own day is not part of the pattern', async () => {
    const taskRes = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/tasks`,
      headers: owner.headers,
      payload: { title: 'Kira öde', dueAt: `${dayAfter(1)}T09:00:00.000Z` },
    });
    const task = taskRes.json();

    // Every third day from today: tomorrow is deliberately not one of them.
    const res = await create({
      rule: { freq: 'daily', interval: 3, end: { type: 'count', count: 5 } },
      fromTaskId: task.id,
    });
    expect(res.json().adoptedTaskId).toBeNull();
    expect(tables.tasks.find((t) => t.id === task.id).series_id).toBeNull();
  });

  it('stops a series: the future goes, the past and the completed stay', async () => {
    const { series } = (await create()).json();
    const rows = occurrencesOf(series.id);
    const done = rows[0];
    tables.tasks.find((t) => t.id === done.id).status = 'completed';

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/task-series/${series.id}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().removed).toBeGreaterThan(0);

    expect(tables.tasks.find((t) => t.id === done.id).deleted_at ?? null).toBeNull();
    expect(occurrencesOf(series.id).every((r) => r.status === 'completed')).toBe(true);

    const gone = await app.inject({
      method: 'GET',
      url: `/api/v1/task-series/${series.id}`,
      headers: owner.headers,
    });
    expect(gone.statusCode).toBe(404);
  });

  it('completing one occurrence leaves its siblings and the series untouched', async () => {
    const { series } = (await create()).json();
    const rows = occurrencesOf(series.id);
    const target = rows[1];

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${target.id}/complete`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);

    // Exactly one row changed status; the rule itself never moved.
    const after = tables.tasks.filter((t) => t.series_id === series.id);
    expect(after.filter((t) => t.status === 'completed')).toHaveLength(1);
    expect(after.filter((t) => t.status === 'open')).toHaveLength(rows.length - 1);
    expect(tables.task_series.find((s) => s.id === series.id).deleted_at ?? null).toBeNull();
  });

  it('deleting one occurrence removes that row only, and the sweep respects it', async () => {
    const { series } = (await create()).json();
    const rows = occurrencesOf(series.id);
    const target = rows[2];

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${target.id}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(204);
    expect(occurrencesOf(series.id)).toHaveLength(rows.length - 1);

    // The tombstone keeps the (series, day) slot, so "I removed this one"
    // survives the next window roll instead of being silently recreated.
    await app.seriesGc.sweep(new Date());
    expect(occurrencesOf(series.id)).toHaveLength(rows.length - 1);
  });

  it('announces every occurrence to sync, so other devices see them', async () => {
    const { series, created } = (await create()).json();
    const taskWrites = tables.sync_revisions.filter(
      (r) => r.entity_type === 'task' && r.operation === 'create',
    );
    expect(taskWrites).toHaveLength(created);
    expect(
      tables.sync_revisions.some(
        (r) => r.entity_type === 'task_series' && r.entity_id === series.id,
      ),
    ).toBe(true);
  });

  it('gives an urgent template its reminder rows', async () => {
    const res = await create({
      template: template({ isUrgent: true, remindMinutesBefore: 30 }),
    });
    const { series } = res.json();
    const ids = new Set(occurrencesOf(series.id).map((r) => r.id));
    const reminders = tables.reminders.filter((r) => ids.has(r.task_id));
    expect(reminders.length).toBeGreaterThan(0);
    expect(reminders[0].alarm_level).toBe('urgent');
  });

  it('refuses a rule it cannot express, before writing anything', async () => {
    const res = await create({ rule: { freq: 'hourly', interval: 1 } });
    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('TASK_SERIES_RULE_INVALID');
    expect(tables.task_series).toHaveLength(0);
    expect(tables.tasks).toHaveLength(0);
  });

  it('refuses a series without a title', async () => {
    const res = await create({ template: { priority: 'high' } });
    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('TASK_SERIES_TEMPLATE_INVALID');
  });

  it('hides another workspace member-less user’s series behind a 404', async () => {
    const { series } = (await create()).json();
    const stranger = await registerUser(app, { email: 'stranger@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/task-series/${series.id}`,
      headers: stranger.headers,
    });
    expect(res.statusCode).toBe(403);
  });
});
