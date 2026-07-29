import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-205 — `task_series` in the sync protocol (ADR-0020).
 *
 * The property this file pins: a series pushed offline arrives WITH its
 * occurrences. Materialization runs inside the mutation's own transaction, so
 * a client that creates a repeating task on a plane and lands sees real task
 * rows on its next pull — not a rule that nothing has expanded yet.
 */
let app;
let tables;
let owner;
let ws;

const CLIENT = newId();

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
  ws = owner.workspace.id;
});

afterEach(async () => {
  await app.close();
});

const today = () => new Date().toISOString().slice(0, 10);

const push = (mutations, { baseRevision = 0, clientId = CLIENT } = {}) =>
  app.inject({
    method: 'POST',
    url: '/api/v1/sync/push',
    headers: owner.headers,
    payload: { clientId, workspaceId: ws, baseRevision, mutations },
  });

const pull = (since) =>
  app.inject({
    method: 'GET',
    url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=${since}`,
    headers: owner.headers,
  });

const seriesPatch = (over = {}) => ({
  rule: { freq: 'weekly', interval: 1, byWeekday: [{ day: 'MO', ordinal: null }] },
  template: { title: 'Haftalık rapor', priority: 'medium' },
  timezone: 'UTC',
  anchorAt: `${today()}T09:00:00.000Z`,
  ...over,
});

const createSeries = async (id = newId(), over = {}) => {
  const res = await push([
    {
      clientMutationId: newId(),
      operation: 'create',
      entityType: 'task_series',
      entityId: id,
      patch: seriesPatch(over),
    },
  ]);
  expect(res.statusCode).toBe(200);
  return { id, body: res.json() };
};

describe('sync push — task_series (OPH-205, ADR-0020)', () => {
  it('creates the series AND its occurrences in one mutation', async () => {
    const { id, body } = await createSeries();
    expect(body.results[0].status).toBe('applied');

    const stored = tables.task_series.find((s) => s.id === id);
    expect(stored).toBeTruthy();
    expect(JSON.parse(stored.rule).freq).toBe('weekly');

    const occurrences = tables.tasks.filter((t) => t.series_id === id);
    expect(occurrences.length).toBeGreaterThan(40); // ~52 Mondays in 12 months
    expect(occurrences.every((t) => t.title === 'Haftalık rapor')).toBe(true);
  });

  it('hands the rule and every occurrence to the next pull', async () => {
    const before = Number(tables.workspaces.find((w) => w.id === ws).revision);
    const { id } = await createSeries();

    const changes = (await pull(before)).json().changes;
    const series = changes.filter((c) => c.entityType === 'task_series');
    expect(series).toHaveLength(1);
    expect(series[0].data.rule.freq).toBe('weekly');
    expect(series[0].data.template.title).toBe('Haftalık rapor');

    const tasks = changes.filter((c) => c.entityType === 'task');
    expect(tasks.length).toBeGreaterThan(0);
    // The occurrence tells the client which series it belongs to, so the row
    // can wear its ↻ badge without a second request.
    expect(tasks[0].data.seriesId).toBe(id);
    expect(tasks[0].data.occurrenceDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('rejects an impossible rule as a rejected mutation, not a 500', async () => {
    const res = await push([
      {
        clientMutationId: newId(),
        operation: 'create',
        entityType: 'task_series',
        entityId: newId(),
        patch: seriesPatch({ rule: { freq: 'monthly', interval: 1, byMonthDay: [99] } }),
      },
    ]);
    expect(res.statusCode).toBe(200);
    expect(res.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'TASK_SERIES_RULE_INVALID',
    });
    expect(tables.task_series).toHaveLength(0);
  });

  it('rebuilds the future when the rule is updated offline', async () => {
    const { id } = await createSeries();
    const mondays = tables.tasks.filter((t) => t.series_id === id).length;

    const res = await push([
      {
        clientMutationId: newId(),
        operation: 'update',
        entityType: 'task_series',
        entityId: id,
        patch: { rule: { freq: 'monthly', interval: 1, byMonthDay: [1] } },
      },
    ]);
    expect(res.json().results[0].status).toBe('applied');

    const live = tables.tasks.filter((t) => t.series_id === id && t.deleted_at == null);
    expect(live.length).toBeLessThan(mondays);
    expect(live.every((t) => String(t.occurrence_date).endsWith('-01'))).toBe(true);
  });

  it('stops the series on delete and keeps completed occurrences', async () => {
    const { id } = await createSeries();
    const first = tables.tasks.filter((t) => t.series_id === id)[0];
    first.status = 'completed';

    const res = await push([
      {
        clientMutationId: newId(),
        operation: 'delete',
        entityType: 'task_series',
        entityId: id,
      },
    ]);
    expect(res.json().results[0].status).toBe('applied');

    expect(tables.task_series.find((s) => s.id === id).deleted_at).toBeTruthy();
    expect(tables.tasks.find((t) => t.id === first.id).deleted_at ?? null).toBeNull();
    const live = tables.tasks.filter((t) => t.series_id === id && t.deleted_at == null);
    expect(live).toHaveLength(1);
  });

  it('replays idempotently — a re-pushed mutation creates nothing twice', async () => {
    const id = newId();
    const clientMutationId = newId();
    const mutation = {
      clientMutationId,
      operation: 'create',
      entityType: 'task_series',
      entityId: id,
      patch: seriesPatch(),
    };
    await push([mutation]);
    const after = tables.tasks.filter((t) => t.series_id === id).length;

    const again = await push([mutation]);
    expect(again.json().results[0].status).toBe('applied');
    expect(tables.tasks.filter((t) => t.series_id === id)).toHaveLength(after);
  });
});

describe('sync push — the frozen repeat_rule (OPH-205, ADR-0020 §7)', () => {
  it('no longer accepts repeatRule on a task', async () => {
    const taskRes = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/tasks`,
      headers: owner.headers,
      payload: { title: 'Sıradan görev' },
    });
    const task = taskRes.json();
    expect(task.repeatRule).toBeNull();

    const res = await push([
      {
        clientMutationId: newId(),
        operation: 'update',
        entityType: 'task',
        entityId: task.id,
        patch: { repeatRule: 'FREQ=DAILY' },
      },
    ]);
    expect(res.json().results[0]).toMatchObject({ status: 'rejected' });
    expect(tables.tasks.find((t) => t.id === task.id).repeat_rule ?? null).toBeNull();
  });
});
