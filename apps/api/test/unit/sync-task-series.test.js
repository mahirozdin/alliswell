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

  // OPH-299 — the body the app ACTUALLY sends. `SeriesStore.create` always puts
  // `fromTaskId` in the patch (`series_store.dart:112`) and both UI entry points
  // fill it (`task_create_sheet.dart:246`, `repeat_row.dart:101`), so a payload
  // built without it proves nothing about the product. `seriesPatch()` above was
  // exactly such a payload, which is how recurrence stayed broken from v0.8.0.
  it('adopts the task named in `fromTaskId` rather than twinning its day', async () => {
    const taskId = newId();
    const seriesId = newId();

    // What the create sheet does: save the task, then start the series on it.
    const res = await push([
      {
        clientMutationId: newId(),
        operation: 'create',
        entityType: 'task',
        entityId: taskId,
        patch: { title: 'Günlük rapor', dueAt: `${today()}T09:00:00.000Z` },
      },
      {
        clientMutationId: newId(),
        operation: 'create',
        entityType: 'task_series',
        entityId: seriesId,
        patch: seriesPatch({
          rule: { freq: 'daily', interval: 1 },
          template: { title: 'Günlük rapor', priority: 'medium' },
          fromTaskId: taskId,
        }),
      },
    ]);

    expect(res.json().results.map((r) => r.status)).toEqual(['applied', 'applied']);

    // The row the user was looking at joins the series...
    expect(tables.tasks.find((t) => t.id === taskId).series_id).toBe(seriesId);

    // ...and no day carries two tasks. Accepting the field without adopting the
    // task would leave the origin beside a freshly materialized twin.
    const days = tables.tasks
      .filter((t) => t.series_id === seriesId)
      .map((t) => String(t.occurrence_date).slice(0, 10));
    expect(days).toContain(today());
    expect(new Set(days).size).toBe(days.length);
  });

  // OPH-299 — the other half of `createOnly`. A series adopts at birth; nothing
  // acts on a later `fromTaskId` (`afterUpdate` rebuilds the future, it does not
  // adopt), so accepting one would report `applied` for an instruction the server
  // silently dropped. A refusal the client can see beats a lie it cannot.
  it('refuses `fromTaskId` on an update — a series adopts at birth, never again', async () => {
    const { id } = await createSeries(newId(), { rule: { freq: 'daily', interval: 1 } });

    const res = await push([
      {
        clientMutationId: newId(),
        operation: 'update',
        entityType: 'task_series',
        entityId: id,
        patch: { fromTaskId: newId() },
      },
    ]);

    expect(res.json().results[0].status).toBe('rejected');
    expect(res.json().results[0].errorCode).toBe('SYNC_UNKNOWN_FIELD');
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

describe('sync push — repeat after completion, offline (OPH-375, ADR-0056)', () => {
  const DAY = 86400000;
  const nineOn = (ms) => `${new Date(ms).toISOString().slice(0, 10)}T09:00:00.000Z`;

  /** A task in an after-completion series of `interval` days, created 10 days ago. */
  async function completionTask(interval = 4) {
    const taskRes = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/tasks`,
      headers: owner.headers,
      payload: { title: 'Filtre', dueAt: nineOn(Date.now() - 5 * DAY), timezone: 'UTC' },
    });
    const task = taskRes.json();
    tables.tasks.find((t) => t.id === task.id).created_at = new Date(Date.now() - 10 * DAY);
    const seriesId = newId();
    await push([
      {
        clientMutationId: newId(),
        operation: 'create',
        entityType: 'task_series',
        entityId: seriesId,
        patch: seriesPatch({
          rule: { freq: 'daily', interval, basis: 'completion' },
          template: { title: 'Filtre' },
          anchorAt: nineOn(Date.now() - 5 * DAY),
          fromTaskId: task.id,
        }),
      },
    ]);
    expect(tables.tasks.find((t) => t.id === task.id).series_id).toBe(seriesId);
    return { taskId: task.id, seriesId };
  }

  // A device that has pulled since the repeat was set up — the realistic base.
  const pulledRevision = () => Number(tables.workspaces.find((w) => w.id === ws).revision);

  const completeOffline = (taskId, localUpdatedAt, opts = { baseRevision: pulledRevision() }) =>
    push(
      [
        {
          clientMutationId: newId(),
          operation: 'update',
          entityType: 'task',
          entityId: taskId,
          patch: { status: 'completed' },
          localUpdatedAt,
        },
      ],
      opts,
    );

  const spawned = (taskId) =>
    tables.tasks.filter((t) => t.spawned_from_task_id === taskId && t.deleted_at == null);

  it('counts from when the user completed it offline, not from when the push landed', async () => {
    const { taskId } = await completionTask(4);
    const tapped = new Date(Date.now() - 3 * DAY);
    const res = await completeOffline(taskId, tapped.toISOString());
    expect(res.json().results[0].status).toBe('applied');

    const row = tables.tasks.find((t) => t.id === taskId);
    expect(new Date(row.completed_at).toISOString()).toBe(tapped.toISOString());
    const [next] = spawned(taskId);
    expect(new Date(next.due_at).toISOString()).toBe(nineOn(tapped.getTime() + 4 * DAY));
  });

  it('a device clock in the future is clamped to now', async () => {
    const { taskId } = await completionTask(2);
    const before = Date.now();
    await completeOffline(taskId, new Date(Date.now() + 30 * DAY).toISOString());
    const completedAt = new Date(tables.tasks.find((t) => t.id === taskId).completed_at).getTime();
    expect(completedAt).toBeGreaterThanOrEqual(before);
    expect(completedAt).toBeLessThanOrEqual(Date.now());
    expect(new Date(spawned(taskId)[0].due_at).toISOString()).toBe(nineOn(Date.now() + 2 * DAY));
  });

  it('a completion that loses last-write-wins spawns nothing', async () => {
    const { taskId } = await completionTask(2);
    const base = Number(tables.workspaces.find((w) => w.id === ws).revision);
    // Someone else moved the status after this client's base…
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${taskId}`,
      headers: owner.headers,
      payload: { status: 'in_progress' },
    });
    // …and this device's completion is older than that edit.
    const res = await completeOffline(taskId, new Date(Date.now() - DAY).toISOString(), {
      baseRevision: base,
    });
    expect(res.json().results[0].status).toBe('conflict');
    expect(tables.tasks.find((t) => t.id === taskId).status).toBe('in_progress');
    expect(spawned(taskId)).toHaveLength(0);
  });

  it('the same completion pushed from two devices spawns once', async () => {
    const { taskId, seriesId } = await completionTask(3);
    await completeOffline(taskId, new Date(Date.now() - DAY).toISOString());
    await completeOffline(taskId, new Date().toISOString(), {
      clientId: newId(),
      baseRevision: pulledRevision(),
    });
    expect(spawned(taskId)).toHaveLength(1);
    expect(
      tables.tasks.filter((t) => t.series_id === seriesId && t.deleted_at == null),
    ).toHaveLength(2);
  });

  it('an offline reopen withdraws the occurrence the completion created', async () => {
    const { taskId } = await completionTask(3);
    await completeOffline(taskId, new Date().toISOString());
    const [next] = spawned(taskId);
    expect(next).toBeTruthy();
    await push(
      [
        {
          clientMutationId: newId(),
          operation: 'update',
          entityType: 'task',
          entityId: taskId,
          patch: { status: 'open' },
          localUpdatedAt: new Date(Date.now() + 1000).toISOString(),
        },
      ],
      { baseRevision: pulledRevision() },
    );
    const gone = tables.tasks.find((t) => t.id === next.id);
    expect(gone.deleted_at).toBeTruthy();
    expect(gone.occurrence_date).toBeNull();
  });
});
