import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { IMPORT_SOURCES } from '../../src/lib/importers/index.js';

/**
 * OPH-371 — POST /workspaces/:id/import/apps over the fake db: the schema,
 * the closed doors, the refusals, preview = import, and the ledger.
 * Real MySQL (rollback, the race, cascades) is in test/integration.
 */
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../fixtures/importers');
const file = (sub, name) => ({ name, content: fs.readFileSync(path.join(dir, sub, name), 'utf8') });
const todoistFiles = () => [
  file('todoist', 'Inbox [2203306141].csv'),
  file('todoist', 'Ev İşleri [2203306142].csv'),
];
const tickFiles = () => [file('ticktick', 'backup-2026-10.csv')];

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'mover@example.com' });
});

const url = () => `/api/v1/workspaces/${owner.workspace.id}/import/apps`;
const post = (payload, headers = owner.headers) =>
  app.inject({ method: 'POST', url: url(), headers, payload });

const WRITE_TABLES = [
  'projects',
  'tags',
  'tasks',
  'checklist_items',
  'notes',
  'task_series',
  'import_ledger',
];
const counts = () => Object.fromEntries(WRITE_TABLES.map((t) => [t, tables[t].length]));

describe('import/apps: doors and schema', () => {
  it('pins the source vocabulary', () => {
    expect(IMPORT_SOURCES).toEqual(['todoist', 'ticktick']);
  });

  it('401 without auth, 403 for a stranger', async () => {
    const anon = await app.inject({ method: 'POST', url: url(), payload: {} });
    expect(anon.statusCode).toBe(401);
    const stranger = await registerUser(app, { email: 'stranger@example.com' });
    const res = await post({ source: 'todoist', files: todoistFiles() }, stranger.headers);
    expect(res.statusCode).toBe(403);
  });

  // Unknown body keys are STRIPPED by Fastify's Ajv, not refused (LESSONS
  // api-db), so the shape cases here are the ones Ajv can actually refuse.
  it('400 for a bad source, a file without content, a bad time and maxItems 0', async () => {
    const files = todoistFiles();
    for (const payload of [
      { source: 'apple-reminders', files },
      { source: 'todoist', files: [{ name: 'a.csv' }] },
      { source: 'todoist', files, options: { defaultTaskTime: '24:00' } },
      { source: 'todoist', files, options: { maxItems: 0 } },
      { source: 'todoist', files: [] },
    ]) {
      const res = await post(payload);
      expect(res.statusCode, JSON.stringify(Object.keys(payload))).toBe(400);
    }
  });

  it('422 for garbage, and a mismatch names the detected source', async () => {
    const garbage = await post({ source: 'todoist', files: [{ name: 'x.csv', content: 'hello' }] });
    expect(garbage.statusCode).toBe(422);
    expect(garbage.json().code).toBe('IMPORT_FORMAT_UNRECOGNIZED');
    const wrong = await post({ source: 'todoist', files: tickFiles() });
    expect(wrong.statusCode).toBe(422);
    expect(wrong.json()).toMatchObject({ code: 'IMPORT_SOURCE_MISMATCH', detected: 'ticktick' });
    const tz = await post({
      source: 'todoist',
      files: todoistFiles(),
      options: { timezone: 'Mars/Olympus' },
    });
    expect(tz.json().code).toBe('IMPORT_INVALID_TIMEZONE');
  });

  it('413 above 10 MB', async () => {
    const big = 'x'.repeat(10 * 1024 * 1024 + 10);
    const res = await post({ source: 'todoist', files: [{ name: 'big.csv', content: big }] });
    expect(res.statusCode).toBe(413);
  });
});

describe('import/apps: preview and import', () => {
  it('dryRun writes nothing and reports the plan', async () => {
    const before = counts();
    const res = await post({ source: 'todoist', files: todoistFiles(), dryRun: true });
    expect(res.statusCode).toBe(200);
    expect(counts()).toEqual(before);
    const body = res.json();
    expect(body).toMatchObject({
      source: 'todoist',
      dryRun: true,
      projects: { new: 1, existing: 0 },
      tasks: 10,
      series: 2,
      checklistItems: 3,
      notes: 0,
      alreadyImported: 0,
      total: 12,
      remaining: 12,
      googleMirror: { connected: false },
    });
    expect(body.mapping.priority[0]).toEqual({ from: 'p1', to: 'high' });
    const deep = body.warnings.find((w) => w.code === 'IMPORT_DEEP_SUBTASK_FLATTENED');
    expect(deep).toMatchObject({ count: 1 });
    expect(deep.examples[0]).toMatchObject({ file: 'Ev İşleri [2203306142].csv', row: 12 });
  });

  it('imports through the domain: tasks, checklist, series, tags — no urgent alarms', async () => {
    const res = await post({ source: 'todoist', files: todoistFiles() });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.errors).toEqual([]);
    expect(body.created).toMatchObject({ projects: 1, tasks: 10, series: 2, checklistItems: 3 });
    expect(body.remaining).toBe(0);

    const project = tables.projects.find((p) => p.name === 'Ev İşleri');
    const market = tables.tasks.find((t) => t.title === 'Market alışverişi');
    expect(market.project_id).toBe(project.id);
    expect(market.priority).toBe('low');
    expect(tables.checklist_items.filter((c) => c.task_id === market.id)).toHaveLength(3);
    expect(tables.tasks.every((t) => t.is_urgent === false)).toBe(true);
    expect(tables.task_series).toHaveLength(2);
    expect(tables.tags.map((t) => t.slug).sort()).toEqual(
      ['acil', 'bahce', 'ev', 'is', 'is-yeri', 'mutfak', 'saglik'].sort(),
    );
    expect(tables.sync_revisions.some((r) => r.entity_id === market.id)).toBe(true);
    expect(tables.import_ledger.every((l) => l.entity_id)).toBe(true);
  });

  it('a second run creates nothing and counts everything as already imported', async () => {
    await post({ source: 'todoist', files: todoistFiles() });
    const before = counts();
    const again = await post({ source: 'todoist', files: todoistFiles() });
    expect(again.json()).toMatchObject({ alreadyImported: 12, total: 0, remaining: 0 });
    expect(again.json().created).toMatchObject({ projects: 0, tasks: 0, series: 0 });
    expect(counts()).toEqual(before);
  });

  it('maxItems batches until nothing remains, without duplicates', async () => {
    let remaining = Infinity;
    let calls = 0;
    while (remaining > 0 && calls < 10) {
      const res = await post({ source: 'ticktick', files: tickFiles(), options: { maxItems: 3 } });
      remaining = res.json().remaining;
      calls += 1;
    }
    expect(calls).toBe(3); // 9 open items; the 2 completed ones are skipped by default
    expect(tables.import_ledger.filter((l) => l.entity_type !== 'project')).toHaveLength(9);
    const keys = tables.import_ledger.map((l) => l.external_key);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('TickTick: completed tasks are opt-in, notes become notes, reminders only from the source', async () => {
    const preview = (await post({ source: 'ticktick', files: tickFiles(), dryRun: true })).json();
    expect(preview.completed).toEqual({ included: 0, skipped: 2 });
    const res = await post({
      source: 'ticktick',
      files: tickFiles(),
      options: { includeCompleted: true },
    });
    const body = res.json();
    expect(body.errors).toEqual([]);
    expect(body.created).toMatchObject({ notes: 1, series: 1 });
    const done = tables.tasks.find((t) => t.title === 'Eski görev');
    expect(done.status).toBe('completed');
    expect(done.completed_at.toISOString()).toBe('2026-10-01T10:00:00.000Z');
    const market = tables.tasks.find((t) => t.title === 'Market');
    const ticks = tables.checklist_items.filter((c) => c.task_id === market.id);
    expect(ticks.map((c) => c.is_done)).toEqual([false, true, false]);
    expect(tables.notes.find((n) => n.title === 'Fikir defteri')).toBeDefined();
    expect(tables.note_tags).toHaveLength(1);
    const report = tables.tasks.find((t) => t.title === 'Rapor yaz');
    expect(report.remind_at.toISOString()).toBe('2030-11-02T08:45:00.000Z');
    expect(tables.tasks.find((t) => t.title === 'Yüzen saat').remind_at ?? null).toBeNull();
    expect(tables.projects.map((p) => p.name).sort()).toEqual([
      'Alışveriş (Ev)',
      'Alışveriş (İş)',
      'Notlar',
      'Proje Alpha',
    ]);
  });

  it('an existing project with the same folded name is reused', async () => {
    await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
      headers: owner.headers,
      payload: { name: 'EV İŞLERİ' },
    });
    const preview = (await post({ source: 'todoist', files: todoistFiles(), dryRun: true })).json();
    expect(preview.projects).toEqual({ new: 0, existing: 1 });
    await post({ source: 'todoist', files: todoistFiles() });
    expect(tables.projects).toHaveLength(1);
  });
});
