import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

/**
 * OPH-371 over real MySQL: moving in from Todoist and TickTick.
 *
 * The unit suite proves the parsing, the schema and the plan on the fake db.
 * Only real infrastructure proves the rest: the ledger's unique index under two
 * requests at once, the item transaction rolling back with its ledger row,
 * the series materializing real occurrences, /sync/pull carrying the rows,
 * a real API key, and the workspace cascade that account deletion relies on.
 */
const enabled = process.env.INTEGRATION === '1';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../fixtures/importers');
const file = (sub, name) => ({ name, content: fs.readFileSync(path.join(dir, sub, name), 'utf8') });
const todoistFiles = () => [
  file('todoist', 'Inbox [2203306141].csv'),
  file('todoist', 'Ev İşleri [2203306142].csv'),
];
const tickFiles = () => [file('ticktick', 'backup-2026-10.csv')];

const emailPrefix = `oph371-${Date.now()}`;
const PASSWORD = 'integration-pw-371';

describe.runIf(enabled)('integration: import from Todoist / TickTick (OPH-371)', () => {
  let app;

  const register = async (suffix) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-${suffix}@example.com`, password: PASSWORD },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    return {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  };

  const run = (who, payload, headers = who.headers) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${who.workspace.id}/import/apps`,
      headers,
      payload,
    });

  const countRows = async (ws) => {
    const n = async (table) =>
      Number((await app.db(table).where({ workspace_id: ws }).count({ c: '*' }))[0].c);
    return {
      tasks: await n('tasks'),
      projects: await n('projects'),
      tags: await n('tags'),
      notes: await n('notes'),
      series: await n('task_series'),
      ledger: await n('import_ledger'),
    };
  };

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
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

  it('dryRun writes nothing; the import writes real rows that sync', async () => {
    const me = await register('todoist');
    const ws = me.workspace.id;
    // An existing project with the same name (folded) is reused, not doubled.
    await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/projects`,
      headers: me.headers,
      payload: { name: 'ev işleri' },
    });
    const before = await countRows(ws);
    const preview = await run(me, { source: 'todoist', files: todoistFiles(), dryRun: true });
    expect(preview.statusCode).toBe(200);
    expect(preview.json().projects).toEqual({ new: 0, existing: 1 });
    expect(await countRows(ws)).toEqual(before);

    const revision = Number(
      (await app.db('workspaces').where({ id: ws }).first('revision')).revision,
    );
    const res = await run(me, {
      source: 'todoist',
      files: todoistFiles(),
      options: { timezone: 'Europe/Istanbul', locale: 'tr' },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.errors).toEqual([]);
    expect(body.created).toMatchObject({ projects: 0, tasks: 10, series: 2, checklistItems: 3 });

    const after = await countRows(ws);
    expect(after.projects).toBe(before.projects);
    const ali = await app
      .db('tasks')
      .where({ workspace_id: ws, title: "Ali'ye yaz ali@example.com" })
      .first();
    expect(ali.priority).toBe('medium');
    expect(new Date(ali.due_at).toISOString()).toBe('2026-10-20T11:00:00.000Z');
    expect(ali.estimated_minutes).toBe(30);
    expect(ali.is_urgent).toBeFalsy();

    // The series round-trips and its occurrences exist as ordinary tasks.
    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ws}/task-series`,
      headers: me.headers,
    });
    const daily = list.json().series.find((s) => s.template.title === 'Bulaşık makinesini boşalt');
    expect(daily.rule).toMatchObject({ freq: 'daily', interval: 1 });
    expect(daily.template.isUrgent).toBe(false);
    const occurrences = await app.db('tasks').where({ series_id: daily.id }).count({ c: '*' });
    expect(Number(occurrences[0].c)).toBeGreaterThan(300);

    // Every device converges through the ordinary pull (paged: the series
    // materialized hundreds of occurrences).
    const changes = [];
    let since = revision;
    for (let page = 0; page < 50; page += 1) {
      const pull = await app.inject({
        method: 'GET',
        url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=${since}&limit=500`,
        headers: me.headers,
      });
      expect(pull.statusCode).toBe(200);
      changes.push(...pull.json().changes);
      since = pull.json().toRevision;
      if (!pull.json().hasMore) break;
    }
    expect(changes.some((c) => c.entityType === 'task' && c.entityId === ali.id)).toBe(true);
    expect(changes.some((c) => c.entityType === 'task_series')).toBe(true);
    expect(changes.some((c) => c.entityType === 'checklist_item')).toBe(true);

    // Re-running creates nothing.
    const again = await run(me, { source: 'todoist', files: todoistFiles() });
    expect(again.json()).toMatchObject({ alreadyImported: 12, remaining: 0 });
    expect(await countRows(ws)).toEqual(after);

    // A task deleted after the import is NOT brought back.
    await app.inject({ method: 'DELETE', url: `/api/v1/tasks/${ali.id}`, headers: me.headers });
    const third = await run(me, { source: 'todoist', files: todoistFiles() });
    expect(third.json().created.tasks).toBe(0);
    const alive = await app
      .db('tasks')
      .where({ workspace_id: ws, title: "Ali'ye yaz ali@example.com" })
      .whereNull('deleted_at');
    expect(alive).toHaveLength(0);
  });

  it('TickTick: batches until done, completed opt-in, reminders only from the source', async () => {
    const me = await register('ticktick');
    const ws = me.workspace.id;
    let remaining = Infinity;
    let calls = 0;
    while (remaining > 0 && calls < 10) {
      const res = await run(me, {
        source: 'ticktick',
        files: tickFiles(),
        options: { maxItems: 3, includeCompleted: true, timezone: 'Europe/Istanbul' },
      });
      expect(res.statusCode).toBe(200);
      expect(res.json().errors).toEqual([]);
      remaining = res.json().remaining;
      calls += 1;
    }
    expect(calls).toBe(4); // 11 items incl. 2 completed
    const ledger = await app.db('import_ledger').where({ workspace_id: ws }).select();
    expect(new Set(ledger.map((l) => l.external_key)).size).toBe(ledger.length);

    const market = await app.db('tasks').where({ workspace_id: ws, title: 'Market' }).first();
    const ticks = await app
      .db('checklist_items')
      .where({ task_id: market.id })
      .orderBy('sort_order')
      .select('title', 'is_done');
    expect(ticks.map((t) => [t.title, Boolean(t.is_done)])).toEqual([
      ['Süt', false],
      ['Ekmek', true],
      ['Yumurta', false],
    ]);
    const done = await app.db('tasks').where({ workspace_id: ws, title: 'Eski görev' }).first();
    expect(done.status).toBe('completed');
    expect(new Date(done.completed_at).toISOString()).toBe('2026-10-01T10:00:00.000Z');
    const report = await app.db('tasks').where({ workspace_id: ws, title: 'Rapor yaz' }).first();
    expect(new Date(report.remind_at).toISOString()).toBe('2030-11-02T08:45:00.000Z');
    expect(new Date(report.scheduled_start_at).toISOString()).toBe('2030-11-02T07:00:00.000Z');
    const plain = await app
      .db('tasks')
      .where({ workspace_id: ws, title: 'Yetim alt görev' })
      .first();
    expect(plain.remind_at).toBeNull();
    const urgent = await app.db('tasks').where({ workspace_id: ws, is_urgent: true }).select('id');
    expect(urgent).toHaveLength(0);
    const note = await app.db('notes').where({ workspace_id: ws, title: 'Fikir defteri' }).first();
    expect(note.content_markdown).toBe('# Başlık\nmetin');
    expect(await app.db('note_tags').where({ note_id: note.id })).toHaveLength(1);
  });

  it('two identical requests at once leave every ledger key once', async () => {
    const me = await register('race');
    const ws = me.workspace.id;
    const payload = { source: 'todoist', files: todoistFiles() };
    const [a, b] = await Promise.all([run(me, payload), run(me, payload)]);
    expect(a.statusCode).toBe(200);
    expect(b.statusCode).toBe(200);
    const ledger = await app.db('import_ledger').where({ workspace_id: ws }).select('external_key');
    expect(new Set(ledger.map((l) => l.external_key)).size).toBe(ledger.length);
    const titles = await app
      .db('tasks')
      .where({ workspace_id: ws, title: 'Kitap oku' })
      .whereNull('deleted_at');
    expect(titles).toHaveLength(1);
    const series = await app.db('task_series').where({ workspace_id: ws });
    expect(series).toHaveLength(2);
    expect(a.json().created.tasks + b.json().created.tasks).toBe(10);
  });

  it('an API key drives the same call, and the workspace cascade removes the ledger', async () => {
    const me = await register('key');
    const ws = me.workspace.id;
    const minted = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/api-keys`,
      headers: me.headers,
      payload: { name: 'mover' },
    });
    expect(minted.statusCode).toBe(201);
    const keyHeaders = { authorization: `Bearer ${minted.json().key}` };
    const res = await run(me, { source: 'ticktick', files: tickFiles() }, keyHeaders);
    expect(res.statusCode).toBe(200);
    expect(res.json().created.tasks).toBeGreaterThan(0);
    expect((await countRows(ws)).ledger).toBeGreaterThan(0);

    await app.db('workspaces').where({ id: ws }).delete();
    const left = await app.db('import_ledger').where({ workspace_id: ws }).count({ c: '*' });
    expect(Number(left[0].c)).toBe(0);
  });
});
