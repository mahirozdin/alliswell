import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-206 — the scope question: this / this and future / all (ADR-0020,
 * DESIGN §25 R8).
 *
 * The three answers are three different promises, and each one is pinned here:
 * "just this" must not leak into the siblings AND must not free its slot for
 * the next sweep; "this and future" splits the series while keeping the row the
 * user is looking at; "all" rewrites the template and every live occurrence but
 * never touches what was already finished.
 */
describe('series editing scope (OPH-206)', () => {
  let app;
  let tables;
  let owner;
  let ws;

  beforeEach(async () => {
    ({ app, tables } = await buildTestApp());
    owner = await registerUser(app, { email: 'owner@example.com' });
    ws = owner.workspace.id;
  });

  const dayAfter = (offset) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);

  const createSeries = async (over = {}) => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/task-series`,
      headers: owner.headers,
      payload: {
        rule: { freq: 'daily', interval: 1, end: { type: 'count', count: 10 } },
        template: { title: 'Sabah koşusu', priority: 'medium' },
        timezone: 'UTC',
        anchorAt: `${dayAfter(0)}T09:00:00.000Z`,
        ...over,
      },
    });
    expect(res.statusCode).toBe(201);
    return res.json().series;
  };

  const occurrences = (seriesId) =>
    tables.tasks
      .filter((t) => t.series_id === seriesId && t.deleted_at == null)
      .sort((a, b) => String(a.occurrence_date).localeCompare(String(b.occurrence_date)));

  const patch = (taskId, body) =>
    app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${taskId}`,
      headers: owner.headers,
      payload: body,
    });

  it('“just this” changes one row and leaves every sibling alone', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);
    const target = rows[2];

    const res = await patch(target.id, { title: 'Akşam koşusu', seriesScope: 'this' });
    expect(res.statusCode).toBe(200);

    const after = occurrences(series.id);
    expect(after.filter((t) => t.title === 'Akşam koşusu')).toHaveLength(1);
    expect(after.filter((t) => t.title === 'Sabah koşusu')).toHaveLength(rows.length - 1);
    // The template is untouched, so tomorrow's sweep keeps making the old one.
    expect(JSON.parse(tables.task_series.find((s) => s.id === series.id).template).title).toBe(
      'Sabah koşusu',
    );
  });

  it('“just this” keeps the series link, so the sweep cannot duplicate the day', async () => {
    const series = await createSeries();
    const target = occurrences(series.id)[2];
    const day = String(target.occurrence_date);

    await patch(target.id, { title: 'Akşam koşusu', seriesScope: 'this' });
    expect(tables.tasks.find((t) => t.id === target.id).series_id).toBe(series.id);

    await app.seriesGc.sweep(new Date());
    const sameDay = occurrences(series.id).filter((t) => String(t.occurrence_date) === day);
    expect(sameDay).toHaveLength(1);
    expect(sameDay[0].title).toBe('Akşam koşusu');
  });

  it('a bare edit with no scope behaves exactly like “just this”', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);

    await patch(rows[1].id, { priority: 'urgent' });

    const after = occurrences(series.id);
    expect(after.filter((t) => t.priority === 'urgent')).toHaveLength(1);
  });

  it('“this and future” splits the series and keeps the edited row’s id', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);
    const pivot = rows[3];
    const pivotDay = String(pivot.occurrence_date);

    const res = await patch(pivot.id, { title: 'Yüzme', seriesScope: 'future' });
    expect(res.statusCode).toBe(200);

    // The old series stops the day before the pivot…
    const oldSeries = tables.task_series.find((s) => s.id === series.id);
    expect(JSON.parse(oldSeries.rule).end).toEqual({
      type: 'until',
      until: new Date(Date.parse(`${pivotDay}T00:00:00Z`) - 86400000).toISOString().slice(0, 10),
    });

    // …a second series exists, and the row the user edited belongs to it now,
    // with the SAME id it had before (no swap under the user's cursor).
    expect(tables.task_series).toHaveLength(2);
    const next = tables.task_series.find((s) => s.id !== series.id);
    const moved = tables.tasks.find((t) => t.id === pivot.id);
    expect(moved.series_id).toBe(next.id);
    expect(moved.title).toBe('Yüzme');

    // Everything before the pivot kept the old title and the old series.
    for (const row of occurrences(series.id)) {
      expect(String(row.occurrence_date) < pivotDay).toBe(true);
      expect(row.title).toBe('Sabah koşusu');
    }
    // Everything from the pivot on carries the new one.
    for (const row of occurrences(next.id)) {
      expect(String(row.occurrence_date) >= pivotDay).toBe(true);
      expect(row.title).toBe('Yüzme');
    }
  });

  it('after a split the two series sweep independently', async () => {
    // A rule with no end, so the window is the only thing bounding it.
    const series = await createSeries({ rule: { freq: 'daily', interval: 1 } });
    const pivot = occurrences(series.id)[3];
    await patch(pivot.id, { title: 'Yüzme', seriesScope: 'future' });
    const next = tables.task_series.find((s) => s.id !== series.id);

    const oldBefore = occurrences(series.id).length;
    const newBefore = occurrences(next.id).length;

    await app.seriesGc.sweep(new Date(Date.now() + 30 * 86400000));

    // The old series ended at the pivot, so a later window gives it nothing…
    expect(occurrences(series.id)).toHaveLength(oldBefore);
    // …while the new one keeps producing, on its own anchor and rule.
    expect(occurrences(next.id).length).toBeGreaterThan(newBefore);
    expect(occurrences(next.id).every((t) => t.title === 'Yüzme')).toBe(true);
  });

  it('“this and future” never disturbs a finished occurrence', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);
    tables.tasks.find((t) => t.id === rows[1].id).status = 'completed';

    await patch(rows[3].id, { title: 'Yüzme', seriesScope: 'future' });

    const finished = tables.tasks.find((t) => t.id === rows[1].id);
    expect(finished.deleted_at ?? null).toBeNull();
    expect(finished.title).toBe('Sabah koşusu');
    expect(finished.series_id).toBe(series.id);
  });

  it('“all” rewrites the template and every live occurrence', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);

    const res = await patch(rows[2].id, { title: 'Yürüyüş', priority: 'low', seriesScope: 'all' });
    expect(res.statusCode).toBe(200);

    for (const row of occurrences(series.id)) {
      expect(row.title).toBe('Yürüyüş');
      expect(row.priority).toBe('low');
    }
    const template = JSON.parse(tables.task_series.find((s) => s.id === series.id).template);
    expect(template).toMatchObject({ title: 'Yürüyüş', priority: 'low' });
    // One series, still — "all" edits, it does not split.
    expect(tables.task_series).toHaveLength(1);
  });

  it('“all” leaves a completed occurrence’s status and completion alone', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);
    const done = tables.tasks.find((t) => t.id === rows[0].id);
    done.status = 'completed';
    done.completed_at = new Date();

    await patch(rows[2].id, { title: 'Yürüyüş', seriesScope: 'all' });

    const after = tables.tasks.find((t) => t.id === rows[0].id);
    expect(after.status).toBe('completed');
    expect(after.completed_at).toBeTruthy();
    // Its title stayed too: a finished row is history, and this edit is not.
    expect(after.title).toBe('Sabah koşusu');
  });

  it('a scoped date edit moves the TIME of day, not the pattern', async () => {
    const series = await createSeries();
    const rows = occurrences(series.id);
    const target = rows[2];
    const day = String(target.occurrence_date);

    await patch(target.id, { dueAt: `${day}T18:30:00.000Z`, seriesScope: 'all' });

    // Days still come from the rule — one occurrence per day, unchanged…
    const after = occurrences(series.id);
    expect(after).toHaveLength(rows.length);
    expect(after.map((t) => String(t.occurrence_date))).toEqual(
      rows.map((t) => String(t.occurrence_date)),
    );
    // …and every live one now happens at 18:30.
    for (const row of after) {
      expect(new Date(row.due_at).getUTCHours()).toBe(18);
      expect(new Date(row.due_at).getUTCMinutes()).toBe(30);
    }
    // The anchor moved with them, so tomorrow's new occurrences agree.
    const anchor = new Date(tables.task_series.find((s) => s.id === series.id).anchor_at);
    expect(anchor.getUTCHours()).toBe(18);
  });

  it('moving a date with a wide scope moves the PATTERN too (round 13 #6)', async () => {
    // The owner's report: a "13th of every month" task, moved to another date,
    // kept saying "every month on the 13th". Technically what §25 R8 promised,
    // and wrong — they had just told us which day they wanted.
    const series = await createSeries({
      rule: { freq: 'monthly', interval: 1, byMonthDay: [13] },
      anchorAt: `${dayAfter(0)}T09:00:00.000Z`,
    });
    const target = occurrences(series.id)[0];
    const movedTo = `${String(target.occurrence_date).slice(0, 8)}20`;

    await patch(target.id, {
      dueAt: `${movedTo}T09:00:00.000Z`,
      seriesScope: 'all',
    });

    const rule = JSON.parse(tables.task_series.find((s) => s.id === series.id).rule);
    expect(rule.byMonthDay).toEqual([20]);
    // …and the occurrences followed, without leaving a duplicate behind.
    const days = occurrences(series.id).map((t) => String(t.occurrence_date));
    expect(days.every((d) => d.endsWith('-20'))).toBe(true);
    expect(new Set(days).size).toBe(days.length);
  });

  it('“the 2nd Tuesday” follows to whatever the new date is', async () => {
    const series = await createSeries({
      rule: {
        freq: 'monthly',
        interval: 1,
        byWeekday: [{ day: 'TU', ordinal: 2 }],
      },
    });
    const target = occurrences(series.id)[0];
    const day = String(target.occurrence_date);
    // The 1st of that month — whatever weekday it is, it is the FIRST of them.
    const first = `${day.slice(0, 8)}01`;

    await patch(target.id, {
      dueAt: `${first}T09:00:00.000Z`,
      seriesScope: 'future',
    });

    const next = tables.task_series.find((s) => s.id !== series.id);
    const rule = JSON.parse(next.rule);
    expect(rule.byWeekday.single ?? rule.byWeekday[0]).toMatchObject({ ordinal: 1 });
  });

  it('an ambiguous pattern keeps its days and only takes the new time', async () => {
    // Two days a month: there is no single day to move, so §25 R8 still holds.
    const series = await createSeries({
      rule: { freq: 'monthly', interval: 1, byMonthDay: [5, 20] },
    });
    const target = occurrences(series.id)[0];
    const day = String(target.occurrence_date);

    await patch(target.id, {
      dueAt: `${day.slice(0, 8)}11T18:30:00.000Z`,
      seriesScope: 'all',
    });

    const rule = JSON.parse(tables.task_series.find((s) => s.id === series.id).rule);
    expect(rule.byMonthDay).toEqual([5, 20]);
  });

  it('a scope on a task that is not part of a series does nothing at all', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/tasks`,
      headers: owner.headers,
      payload: { title: 'Tek görev' },
    });
    const task = created.json();

    const res = await patch(task.id, { title: 'Yine tek', seriesScope: 'all' });
    expect(res.statusCode).toBe(200);
    expect(res.json().title).toBe('Yine tek');
    expect(tables.task_series).toHaveLength(0);
  });

  it('rejects a scope value the protocol does not know', async () => {
    const series = await createSeries();
    const target = occurrences(series.id)[0];
    const res = await patch(target.id, { title: 'X', seriesScope: 'everything' });
    expect(res.statusCode).toBe(400);
  });

  it('carries the scope through an offline sync push', async () => {
    const series = await createSeries();
    const target = occurrences(series.id)[2];

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId: newId(),
        workspaceId: ws,
        // The series materialization already advanced the workspace; pushing
        // from revision 0 would (correctly) lose LWW against those writes.
        baseRevision: Number(tables.workspaces.find((w) => w.id === ws).revision),
        mutations: [
          {
            clientMutationId: newId(),
            operation: 'update',
            entityType: 'task',
            entityId: target.id,
            patch: { title: 'Yürüyüş', seriesScope: 'all' },
          },
        ],
      },
    });
    expect(res.json().results[0].status).toBe('applied');
    for (const row of occurrences(series.id)) expect(row.title).toBe('Yürüyüş');
  });
});
