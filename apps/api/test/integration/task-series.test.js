import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';

/**
 * OPH-205 — task series over REAL MySQL (ADR-0020).
 *
 * The in-memory suite cannot prove the two things that only a real server
 * knows: that `rule`/`template` survive a JSON column round trip, and that
 * `uq_tasks_series_occurrence` actually stops a duplicate occurrence while
 * leaving ordinary tasks (NULL in both columns) alone.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('task series integration (OPH-205, ADR-0020)', () => {
  let app;
  let headers;
  let workspaceId;

  const today = () => new Date().toISOString().slice(0, 10);

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, NODE_ENV: 'test' });
    app = await buildApp({ config });
    const email = `series-int-${Date.now()}@example.com`;
    const register = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'sifre-12345' },
    });
    const body = register.json();
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    workspaceId = body.workspace.id;
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  const createSeries = (over = {}) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/task-series`,
      headers,
      payload: {
        rule: {
          freq: 'monthly',
          interval: 1,
          byWeekday: [{ day: 'MO', ordinal: null }],
          byMonthDay: [23, 24, 25, 26, 27, 28, 29],
        },
        template: { title: 'Aylık rapor', priority: 'high', tagIds: [] },
        timezone: 'Europe/Istanbul',
        anchorAt: `${today()}T09:00:00.000Z`,
        ...over,
      },
    });

  it('round-trips the rule through the JSON column, nesting intact', async () => {
    const res = await createSeries();
    expect(res.statusCode).toBe(201);
    const { series, created } = res.json();
    expect(created).toBeGreaterThan(0);

    const fetched = (
      await app.inject({ method: 'GET', url: `/api/v1/task-series/${series.id}`, headers })
    ).json();
    expect(fetched.rule.byWeekday).toEqual([{ day: 'MO', ordinal: null }]);
    expect(fetched.rule.byMonthDay).toEqual([23, 24, 25, 26, 27, 28, 29]);
    expect(fetched.template.title).toBe('Aylık rapor');
  });

  it('stores occurrence_date as a real DATE and reads back the same day', async () => {
    const { series } = (await createSeries()).json();
    const rows = await app
      .db('tasks')
      .where({ series_id: series.id })
      .orderBy('occurrence_date', 'asc')
      .select('id', 'occurrence_date', 'due_at');
    expect(rows.length).toBeGreaterThan(0);

    // Every occurrence is a Monday between the 23rd and the 29th — the day the
    // engine chose, not a day a timezone conversion shifted.
    for (const row of rows) {
      const day = new Date(row.occurrence_date);
      expect(day.getUTCDate()).toBeGreaterThanOrEqual(23);
      expect(day.getUTCDate()).toBeLessThanOrEqual(29);
      expect(day.getUTCDay()).toBe(1); // Monday
    }

    const listed = (
      await app.inject({
        method: 'GET',
        url: `/api/v1/tasks/${rows[0].id}`,
        headers,
      })
    ).json();
    expect(listed.occurrenceDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(listed.seriesId).toBe(series.id);
  });

  it('the unique index refuses a duplicate occurrence but not ordinary tasks', async () => {
    const { series } = (await createSeries()).json();
    const first = await app
      .db('tasks')
      .where({ series_id: series.id })
      .first('id', 'occurrence_date', 'workspace_id');

    await expect(
      app.db('tasks').insert({
        id: '01JQTASKSERIESDUPLICATE00',
        workspace_id: first.workspace_id,
        title: 'Kopya',
        series_id: series.id,
        occurrence_date: first.occurrence_date,
      }),
    ).rejects.toThrow(/Duplicate|uq_tasks_series_occurrence/i);

    // Two plain tasks (NULL, NULL) coexist happily — MySQL skips NULL tuples.
    for (const title of ['Sıradan 1', 'Sıradan 2']) {
      const res = await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${workspaceId}/tasks`,
        headers,
        payload: { title },
      });
      expect(res.statusCode).toBe(201);
    }
  });

  it('rolls the window forward against the real database', async () => {
    const { series } = (await createSeries()).json();
    const before = await app.db('tasks').where({ series_id: series.id }).count({ n: '*' }).first();

    const created = await app.seriesGc.sweep(new Date(Date.now() + 60 * 86400000));
    expect(created).toBeGreaterThan(0);

    const after = await app.db('tasks').where({ series_id: series.id }).count({ n: '*' }).first();
    expect(Number(after.n)).toBeGreaterThan(Number(before.n));

    // …and running it twice more changes nothing (idempotent).
    await app.seriesGc.sweep(new Date(Date.now() + 60 * 86400000));
    const again = await app.db('tasks').where({ series_id: series.id }).count({ n: '*' }).first();
    expect(Number(again.n)).toBe(Number(after.n));
  });
});
