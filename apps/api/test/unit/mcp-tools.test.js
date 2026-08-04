import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fullDance, callTool, rpc } from '../helpers/mcpdance.js';

/**
 * OPH-218 — the seven tools against a seeded workspace: fold search, caps,
 * two-user isolation byte for byte, domain-layer writes with revision
 * bookkeeping, idempotency, and the honest project-ambiguity refusal.
 */

let app;
let tables;
let owner;
let access;

async function seed(headers, workspaceId, path, payload) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${workspaceId}/${path}`,
    headers,
    payload,
  });
  expect([200, 201]).toContain(res.statusCode);
  return res.json();
}

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'mcp-tools@example.com' });
  const { tokens } = await fullDance(app, { email: 'mcp-tools@example.com' });
  access = tokens.access_token;
});

describe('read tools', () => {
  it('search folds Turkish on titles and finds body-only matches at tier 2', async () => {
    await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Işık faturasını öde' });
    await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Alakasız başlık',
      description: 'içinde ışık kelimesi geçen açıklama',
    });
    await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Işıklandırma projesi' });

    const result = await callTool(app, access, 'search', { query: 'isik' });
    expect(result.isError).toBeFalsy();
    const results = result.structuredContent.results;
    const titles = results.map((r) => r.title);
    expect(titles).toContain('Işık faturasını öde');
    expect(titles).toContain('Işıklandırma projesi');
    // The body-only match arrives too — ranked behind the title hits.
    expect(titles).toContain('Alakasız başlık');
    const bodyHit = results.findIndex((r) => r.title === 'Alakasız başlık');
    const titleHit = results.findIndex((r) => r.title === 'Işık faturasını öde');
    expect(bodyHit).toBeGreaterThan(titleHit);
  });

  it('search respects the limit and reports truncation', async () => {
    for (let i = 0; i < 6; i += 1) {
      await seed(owner.headers, owner.workspace.id, 'tasks', { title: `Rapor ${i}` });
    }
    const result = await callTool(app, access, 'search', { query: 'rapor', limit: 3 });
    expect(result.structuredContent.results).toHaveLength(3);
    expect(result.structuredContent.truncated).toBe(true);
  });

  it('list_tasks today/overdue use the owner timezone; plain list filters', async () => {
    // Pin the owner's wall clock to ~midday for THIS run. The registration
    // default is Europe/Istanbul, so a CI run between 22:00 and 00:00 Istanbul
    // pushed `now + 2 h` across midnight and the today view rightly answered
    // [] — a daily two-hour red window that blocked a release gate for real
    // (2026-08-04 20:57Z). Etc/GMT naming is POSIX-inverted: Etc/GMT-5 means
    // UTC+5. The view still resolves bounds through the owner's timezone —
    // that behavior stays exercised, just at a safe local hour.
    const offset = Math.max(-12, Math.min(12, 12 - new Date().getUTCHours()));
    const middayTz = offset >= 0 ? `Etc/GMT-${offset}` : `Etc/GMT+${-offset}`;
    await app.db('users').where({ id: owner.user.id }).update({ timezone: middayTz });

    const past = new Date(Date.now() - 86400000).toISOString();
    const inTwoHours = new Date(Date.now() + 2 * 3600000).toISOString();
    await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Geciken', dueAt: past });
    await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Bugünkü', dueAt: inTwoHours });
    await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Tarihsiz' });

    const overdue = await callTool(app, access, 'list_tasks', { overdue: true });
    expect(overdue.structuredContent.tasks.map((t) => t.title)).toEqual(['Geciken']);

    const today = await callTool(app, access, 'list_tasks', { today: true });
    expect(today.structuredContent.tasks.map((t) => t.title)).toContain('Bugünkü');
    expect(today.structuredContent.tasks.map((t) => t.title)).not.toContain('Geciken');

    const open = await callTool(app, access, 'list_tasks', { status: ['open'], limit: 50 });
    expect(open.structuredContent.tasks.length).toBeGreaterThanOrEqual(3);
  });

  it('get_task carries checklist, tag names and project name', async () => {
    const project = await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Ev' });
    const tag = await seed(owner.headers, owner.workspace.id, 'tags', { name: 'fatura' });
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Detaylı görev',
      projectId: project.id,
      tagIds: [tag.id],
    });
    await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/checklist`,
      headers: owner.headers,
      payload: { title: 'alt madde' },
    });

    const result = await callTool(app, access, 'get_task', { taskId: task.id });
    const got = result.structuredContent.task;
    expect(got.projectName).toBe('Ev');
    expect(got.tags).toEqual(['fatura']);
    expect(got.checklist.map((c) => c.title)).toEqual(['alt madde']);
  });

  it('resources/read serves the today and overdue views as JSON', async () => {
    await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Dünkü iş',
      dueAt: new Date(Date.now() - 86400000).toISOString(),
    });
    const res = await rpc(app, access, 'resources/read', { uri: 'alliswell://views/overdue' });
    const contents = res.json().result.contents;
    expect(contents[0].mimeType).toBe('application/json');
    const payload = JSON.parse(contents[0].text);
    expect(payload.view).toBe('overdue');
    expect(payload.tasks.map((t) => t.title)).toEqual(['Dünkü iş']);
  });
});

describe('two-user isolation', () => {
  it('another account’s token sees NOTHING of the owner’s workspace', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Gizli iş' });
    const outsider = await registerUser(app, { email: 'mcp-outsider@example.com' });
    const { tokens } = await fullDance(app, { email: 'mcp-outsider@example.com' });
    void outsider;

    const search = await callTool(app, tokens.access_token, 'search', { query: 'gizli' });
    expect(search.structuredContent.results).toEqual([]);

    const get = await callTool(app, tokens.access_token, 'get_task', { taskId: task.id });
    expect(get.isError).toBe(true);
    expect(get.structuredContent.code).toBe('NOT_FOUND');

    const complete = await callTool(app, tokens.access_token, 'complete_task', {
      taskId: task.id,
    });
    expect(complete.isError).toBe(true);
    // …and the owner's task is untouched.
    expect(tables.tasks.find((t) => t.id === task.id).status).toBe('open');
  });
});

describe('create_task', () => {
  it('creates through the domain layer: revision, sync row, tags, reminder', async () => {
    await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Ev işleri' });
    await seed(owner.headers, owner.workspace.id, 'tags', { name: 'Fatura' });
    const remindAt = new Date(Date.now() + 3600000).toISOString();

    const result = await callTool(app, access, 'create_task', {
      title: 'Elektrik faturası',
      projectName: 'ev isleri', // folded match
      reminderAt: remindAt,
      tags: ['fatura', 'bilinmeyen-etiket'],
      checklist: ['IBAN kontrol', 'dekont sakla'],
      idempotencyKey: 'host-key-0001',
    });
    expect(result.isError).toBeFalsy();
    const payload = result.structuredContent;
    expect(payload.created).toBe(true);
    expect(payload.unmatchedTags).toEqual(['bilinmeyen-etiket']);

    const row = tables.tasks.find((t) => t.id === payload.task.id);
    expect(row.project_id).not.toBeNull();
    expect(Number(row.revision)).toBeGreaterThan(0);
    expect(
      tables.sync_revisions.some(
        (r) => r.entity_id === row.id && r.entity_type === 'task' && r.operation === 'create',
      ),
    ).toBe(true);
    expect(tables.task_tags.filter((t) => t.task_id === row.id)).toHaveLength(1);
    expect(tables.reminders.filter((r) => r.task_id === row.id)).toHaveLength(1);
    expect(tables.checklist_items.filter((c) => c.task_id === row.id)).toHaveLength(2);
    const log = tables.ai_action_log.find((l) => l.source === 'mcp');
    expect(log.accepted).toBe(true);
    expect(JSON.parse(log.entity_refs)[0]).toEqual({ type: 'task', id: row.id });
  });

  it('the same idempotencyKey replays the SAME task, creating nothing', async () => {
    const first = await callTool(app, access, 'create_task', {
      title: 'Bir kere',
      idempotencyKey: 'host-key-0002',
    });
    const second = await callTool(app, access, 'create_task', {
      title: 'Bir kere',
      idempotencyKey: 'host-key-0002',
    });
    expect(second.structuredContent.replayed).toBe(true);
    expect(second.structuredContent.task.id).toBe(first.structuredContent.task.id);
    expect(tables.tasks.filter((t) => t.title === 'Bir kere')).toHaveLength(1);
  });

  it('an ambiguous or unknown project creates NOTHING and returns candidates', async () => {
    await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Okul' });
    await seed(owner.headers, owner.workspace.id, 'projects', { name: 'okuma listesi' });
    const before = tables.tasks.length;

    const ambiguous = await callTool(app, access, 'create_task', {
      title: 'Kitap al',
      projectName: 'ok',
    });
    expect(ambiguous.structuredContent.created).toBe(false);
    expect(ambiguous.structuredContent.reason).toBe('PROJECT_AMBIGUOUS');
    expect(ambiguous.structuredContent.candidates.map((c) => c.name)).toEqual([
      'Okul',
      'okuma listesi',
    ]);

    const unknown = await callTool(app, access, 'create_task', {
      title: 'Kitap al',
      projectName: 'muhasebe',
    });
    expect(unknown.structuredContent.reason).toBe('PROJECT_NOT_FOUND');
    expect(tables.tasks.length).toBe(before);
  });

  it('invalid arguments come back as a model-correctable tool error', async () => {
    const result = await callTool(app, access, 'create_task', { title: '' });
    expect(result.isError).toBe(true);
    expect(result.structuredContent.code).toBe('INVALID_ARGUMENTS');
  });
});

describe('complete_task and scopes', () => {
  it('completes idempotently through the domain layer', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Bitecek iş' });
    const first = await callTool(app, access, 'complete_task', { taskId: task.id });
    expect(first.structuredContent.task.status).toBe('completed');
    expect(first.structuredContent.alreadyCompleted).toBe(false);

    const again = await callTool(app, access, 'complete_task', { taskId: task.id });
    expect(again.structuredContent.alreadyCompleted).toBe(true);
    // The repeat burned no extra revision (REST semantics).
    const revisions = tables.sync_revisions.filter((r) => r.entity_id === task.id);
    expect(revisions).toHaveLength(2); // create + one completion
  });

  it('a read-only token is refused by the write tools', async () => {
    await registerUser(app, { email: 'mcp-readonly@example.com' });
    const { tokens } = await fullDance(app, {
      email: 'mcp-readonly@example.com',
      scope: 'mcp:read',
    });
    const result = await callTool(app, tokens.access_token, 'create_task', { title: 'Yazamam' });
    expect(result.isError).toBe(true);
    expect(result.structuredContent.code).toBe('MCP_SCOPE_REQUIRED');

    const read = await callTool(app, tokens.access_token, 'list_tasks', {});
    expect(read.isError).toBeFalsy();
  });
});
