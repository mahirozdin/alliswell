import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fullDance, callTool, rpc } from '../helpers/mcpdance.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-218 — the tools against a seeded workspace: fold search, caps, two-user
 * isolation byte for byte, domain-layer writes with revision bookkeeping,
 * idempotency, and the honest project-ambiguity refusal.
 *
 * OPH-262 widened it with the task write wave (update/reopen/snooze/checklist/
 * acknowledge). Its own contract, tested here: every write tool checks the
 * scope, answers NOT_FOUND for another workspace's ids, and turns a domain
 * refusal into a code the model can read.
 */

// Schema-valid but nonexistent — the scope check must fire before any lookup.
const ABSENT_ULID = '01JZZZZZZZZZZZZZZZZZZZZZZZ';

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

  // OPH-263: the capture box. `inbox` is a STATUS the app's Home deliberately
  // hides (OPH-107) — the view has to mean the same thing here.
  it('the inbox resource holds untriaged captures only', async () => {
    await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Yakalanan fikir',
      status: 'inbox',
    });
    await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Planlanmış iş' });

    const res = await rpc(app, access, 'resources/read', { uri: 'alliswell://views/inbox' });
    const payload = JSON.parse(res.json().result.contents[0].text);
    expect(payload.view).toBe('inbox');
    expect(payload.tasks.map((t) => t.title)).toEqual(['Yakalanan fikir']);
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

  it('the OPH-262 write tools answer NOT_FOUND for another workspace’s ids', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Gizli iş',
      isUrgent: true,
      remindAt: new Date(Date.now() + 3600000).toISOString(),
    });
    const item = await callTool(app, access, 'add_checklist_item', {
      taskId: task.id,
      title: 'gizli madde',
    });
    const alarmId = tables.reminders.find((r) => r.task_id === task.id).id;
    const before = JSON.stringify(tables.tasks.find((t) => t.id === task.id));

    await registerUser(app, { email: 'mcp-outsider2@example.com' });
    const { tokens } = await fullDance(app, { email: 'mcp-outsider2@example.com' });

    const calls = [
      ['update_task', { taskId: task.id, title: 'ele geçirildi' }],
      ['reopen_task', { taskId: task.id }],
      ['snooze_task', { taskId: task.id, preset: '1_hour' }],
      ['add_checklist_item', { taskId: task.id, title: 'sızma' }],
      [
        'set_checklist_item',
        { taskId: task.id, itemId: item.structuredContent.item.id, isDone: true },
      ],
      ['acknowledge_reminder', { reminderId: alarmId }],
    ];
    for (const [name, args] of calls) {
      const result = await callTool(app, tokens.access_token, name, args);
      expect(result.isError, name).toBe(true);
      expect(result.structuredContent.code, name).toBe('NOT_FOUND');
    }
    // Nothing of the owner's moved, down to the row.
    expect(JSON.stringify(tables.tasks.find((t) => t.id === task.id))).toBe(before);
    expect(tables.checklist_items.filter((c) => c.task_id === task.id)).toHaveLength(1);
    expect(tables.reminders.find((r) => r.id === alarmId).status).toBe('scheduled');
  });

  it('the OPH-263 note/project tools leak nothing across workspaces either', async () => {
    const project = await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Gizli' });
    const note = await callTool(app, access, 'create_note', { title: 'Gizli not' });
    const noteId = note.structuredContent.note.id;

    await registerUser(app, { email: 'mcp-outsider3@example.com' });
    const { tokens } = await fullDance(app, { email: 'mcp-outsider3@example.com' });

    const calls = [
      ['get_note', { noteId }],
      ['update_note', { noteId, title: 'ele geçirildi' }],
      ['link_note', { noteId, entityType: 'project', entityId: project.id }],
      ['unlink_note', { noteId, entityType: 'project', entityId: project.id }],
      ['update_project', { projectId: project.id, name: 'ele geçirildi' }],
    ];
    for (const [name, args] of calls) {
      const result = await callTool(app, tokens.access_token, name, args);
      expect(result.isError, name).toBe(true);
      expect(result.structuredContent.code, name).toBe('NOT_FOUND');
    }
    // Their lists are empty, not filtered-after-the-fact.
    const notes = await callTool(app, tokens.access_token, 'list_notes', {});
    expect(notes.structuredContent.notes).toEqual([]);
    const projects = await callTool(app, tokens.access_token, 'list_projects', {});
    expect(projects.structuredContent.projects).toEqual([]);
    const files = await callTool(app, tokens.access_token, 'list_files', {});
    expect(files.structuredContent.files).toEqual([]);

    expect(tables.notes.find((n) => n.id === noteId).title).toBe('Gizli not');
    expect(tables.projects.find((p) => p.id === project.id).name).toBe('Gizli');
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

  // OPH-262: not "create_task checks the scope" but "EVERY write tool does".
  // One tool forgetting the line would be a silent hole; this enumerates them.
  it('every write tool refuses a read-only token', async () => {
    await registerUser(app, { email: 'mcp-readonly-all@example.com' });
    const { tokens } = await fullDance(app, {
      email: 'mcp-readonly-all@example.com',
      scope: 'mcp:read',
    });
    const calls = [
      ['create_task', { title: 'Yazamam' }],
      ['complete_task', { taskId: ABSENT_ULID }],
      ['update_task', { taskId: ABSENT_ULID, title: 'Yazamam' }],
      ['reopen_task', { taskId: ABSENT_ULID }],
      ['snooze_task', { taskId: ABSENT_ULID, preset: '5_min' }],
      ['add_checklist_item', { taskId: ABSENT_ULID, title: 'Yazamam' }],
      ['set_checklist_item', { taskId: ABSENT_ULID, itemId: ABSENT_ULID, isDone: true }],
      ['acknowledge_reminder', { reminderId: ABSENT_ULID }],
      ['create_note', { title: 'Yazamam' }],
      ['update_note', { noteId: ABSENT_ULID, title: 'Yazamam' }],
      ['link_note', { noteId: ABSENT_ULID, entityType: 'task', entityId: ABSENT_ULID }],
      ['unlink_note', { noteId: ABSENT_ULID, entityType: 'task', entityId: ABSENT_ULID }],
      ['create_project', { name: 'Yazamam' }],
      ['update_project', { projectId: ABSENT_ULID, name: 'Yazamam' }],
      ['create_tag', { name: 'yazamam' }],
    ];
    for (const [name, args] of calls) {
      const refused = await callTool(app, tokens.access_token, name, args);
      expect(refused.isError, name).toBe(true);
      expect(refused.structuredContent.code, name).toBe('MCP_SCOPE_REQUIRED');
    }
  });
});

describe('update_task', () => {
  it('changes fields through the domain layer: revision, reminder, project by name, tags', async () => {
    const project = await seed(owner.headers, owner.workspace.id, 'projects', {
      name: 'Ev işleri',
    });
    const wanted = await seed(owner.headers, owner.workspace.id, 'tags', { name: 'Fatura' });
    const old = await seed(owner.headers, owner.workspace.id, 'tags', { name: 'eski' });
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Eski başlık',
      tagIds: [old.id],
    });
    const remindAt = new Date(Date.now() + 3600000).toISOString();

    const result = await callTool(app, access, 'update_task', {
      taskId: task.id,
      title: 'Yeni başlık',
      priority: 'high',
      remindAt,
      projectName: 'ev isleri', // folded match
      tags: ['fatura', 'bilinmeyen-etiket'],
    });
    expect(result.isError).toBeFalsy();
    expect(result.structuredContent.updated).toBe(true);
    expect(result.structuredContent.unmatchedTags).toEqual(['bilinmeyen-etiket']);

    const row = tables.tasks.find((t) => t.id === task.id);
    expect(row.title).toBe('Yeni başlık');
    expect(row.priority).toBe('high');
    expect(row.project_id).toBe(project.id);
    // `tags` REPLACES — the old link is gone, not merged.
    expect(tables.task_tags.filter((t) => t.task_id === task.id).map((t) => t.tag_id)).toEqual([
      wanted.id,
    ]);
    // The alarm followed remind_at in the same transaction (reconcile ran).
    const alarms = tables.reminders.filter((r) => r.task_id === task.id);
    expect(alarms).toHaveLength(1);
    expect(new Date(alarms[0].remind_at).toISOString()).toBe(remindAt);
    expect(
      tables.sync_revisions.filter((r) => r.entity_id === task.id && r.operation === 'update')
        .length,
    ).toBeGreaterThanOrEqual(2); // the field patch and the tag replace-set
    const log = tables.ai_action_log.find((l) => JSON.parse(l.proposal).tool === 'update_task');
    expect(log.source).toBe('mcp');
    expect(JSON.parse(log.entity_refs)[0]).toEqual({ type: 'task', id: task.id });
  });

  it('an ambiguous project changes NOTHING and returns candidates', async () => {
    await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Okul' });
    await seed(owner.headers, owner.workspace.id, 'projects', { name: 'okuma listesi' });
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Dokunulmasın' });

    const result = await callTool(app, access, 'update_task', {
      taskId: task.id,
      title: 'Değişmemeli',
      projectName: 'ok',
    });
    expect(result.structuredContent.updated).toBe(false);
    expect(result.structuredContent.reason).toBe('PROJECT_AMBIGUOUS');
    expect(result.structuredContent.candidates.map((c) => c.name)).toEqual([
      'Okul',
      'okuma listesi',
    ]);
    // The refusal is total: the title it also asked for was NOT applied.
    expect(tables.tasks.find((t) => t.id === task.id).title).toBe('Dokunulmasın');
  });

  it('the same idempotencyKey replays, changing nothing the second time', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Başlangıç' });
    await callTool(app, access, 'update_task', {
      taskId: task.id,
      title: 'İlk yazım',
      idempotencyKey: 'upd-key-0001',
    });
    const second = await callTool(app, access, 'update_task', {
      taskId: task.id,
      title: 'İkinci yazım',
      idempotencyKey: 'upd-key-0001',
    });
    expect(second.structuredContent.replayed).toBe(true);
    expect(tables.tasks.find((t) => t.id === task.id).title).toBe('İlk yazım');
  });

  it('a call with nothing to change, and an archived task, come back as codes', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Arşivlik' });

    const empty = await callTool(app, access, 'update_task', { taskId: task.id });
    expect(empty.isError).toBe(true);
    expect(empty.structuredContent.code).toBe('INVALID_ARGUMENTS');

    await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
      payload: { status: 'archived' },
    });
    // The domain refuses in HTTP terms; the model gets the stable code, not
    // an opaque TOOL_FAILED (OPH-262's error mapping).
    const archived = await callTool(app, access, 'update_task', {
      taskId: task.id,
      title: 'Olmaz',
    });
    expect(archived.isError).toBe(true);
    expect(archived.structuredContent.code).toBe('TASK_ARCHIVED');
  });

  // A tags-only call skips the field patch entirely, so the archived rule has
  // to live where the write does — this is the gap that guard closed.
  it('an archived task cannot have its tags rewritten either', async () => {
    const tag = await seed(owner.headers, owner.workspace.id, 'tags', { name: 'sonradan' });
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Kapanmış iş' });
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
      payload: { status: 'archived' },
    });

    const result = await callTool(app, access, 'update_task', {
      taskId: task.id,
      tags: [tag.name],
    });
    expect(result.isError).toBe(true);
    expect(result.structuredContent.code).toBe('TASK_ARCHIVED');
    expect(tables.task_tags.filter((t) => t.task_id === task.id)).toHaveLength(0);
  });
});

describe('reopen_task and snooze_task', () => {
  it('reopens a finished task and refuses an open one', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Bitti sanılan' });
    await callTool(app, access, 'complete_task', { taskId: task.id });

    const reopened = await callTool(app, access, 'reopen_task', { taskId: task.id });
    expect(reopened.structuredContent.task.status).toBe('open');
    expect(tables.tasks.find((t) => t.id === task.id).completed_at).toBeNull();

    const again = await callTool(app, access, 'reopen_task', { taskId: task.id });
    expect(again.isError).toBe(true);
    expect(again.structuredContent.code).toBe('TASK_INVALID_TRANSITION');
  });

  it('snoozes the task AND its live alarm; a past instant is refused', async () => {
    const remindAt = new Date(Date.now() + 3600000).toISOString();
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Ertelenecek',
      remindAt,
    });
    const before = Date.now();

    const result = await callTool(app, access, 'snooze_task', { taskId: task.id, preset: '5_min' });
    expect(result.isError).toBeFalsy();
    const until = new Date(result.structuredContent.snoozedUntil).getTime();
    expect(until).toBeGreaterThanOrEqual(before + 4 * 60 * 1000);
    expect(until).toBeLessThanOrEqual(Date.now() + 6 * 60 * 1000);

    const alarm = tables.reminders.find((r) => r.task_id === task.id);
    expect(alarm.status).toBe('snoozed');
    expect(Number(alarm.snooze_count)).toBe(1);

    const past = await callTool(app, access, 'snooze_task', {
      taskId: task.id,
      snoozeUntil: new Date(Date.now() - 60000).toISOString(),
    });
    expect(past.isError).toBe(true);
    expect(past.structuredContent.code).toBe('TASK_SNOOZE_IN_PAST');
  });
});

describe('checklist tools', () => {
  it('adds an item, replays the key, ticks it, and get_task shows the result', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Alışveriş' });

    const added = await callTool(app, access, 'add_checklist_item', {
      taskId: task.id,
      title: 'süt',
      idempotencyKey: 'chk-key-0001',
    });
    expect(added.structuredContent.created).toBe(true);
    const itemId = added.structuredContent.item.id;

    const replay = await callTool(app, access, 'add_checklist_item', {
      taskId: task.id,
      title: 'süt',
      idempotencyKey: 'chk-key-0001',
    });
    expect(replay.structuredContent.replayed).toBe(true);
    expect(tables.checklist_items.filter((c) => c.task_id === task.id)).toHaveLength(1);

    const ticked = await callTool(app, access, 'set_checklist_item', {
      taskId: task.id,
      itemId,
      isDone: true,
    });
    expect(ticked.structuredContent.item.isDone).toBe(true);

    const detail = await callTool(app, access, 'get_task', { taskId: task.id });
    expect(detail.structuredContent.task.checklist).toEqual([
      { id: itemId, title: 'süt', isDone: true },
    ]);
    expect(
      tables.sync_revisions.some(
        (r) => r.entity_id === itemId && r.entity_type === 'checklist_item',
      ),
    ).toBe(true);
  });

  it('an item id that is not on this task is NOT_FOUND', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Boş liste' });
    const other = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Öteki' });
    const added = await callTool(app, access, 'add_checklist_item', {
      taskId: other.id,
      title: 'başkasının maddesi',
    });

    const result = await callTool(app, access, 'set_checklist_item', {
      taskId: task.id,
      itemId: added.structuredContent.item.id,
      isDone: true,
    });
    expect(result.isError).toBe(true);
    expect(result.structuredContent.code).toBe('NOT_FOUND');
  });
});

describe('note tools (OPH-263)', () => {
  it('creates a standalone note and one attached to a task in the same write', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Toplantı' });

    const standalone = await callTool(app, access, 'create_note', {
      title: 'Serbest not',
      contentMarkdown: '# Başlık\n\nGövde metni',
    });
    expect(standalone.structuredContent.created).toBe(true);
    // MCP notes are born markdown-canonical (ADR-0028) — and that means the
    // search column is derived, which is the OPH-261 repair holding.
    expect(standalone.structuredContent.note.contentFormat).toBe('markdown');
    const standaloneRow = tables.notes.find((n) => n.id === standalone.structuredContent.note.id);
    expect(standaloneRow.plain_text).toContain('Gövde metni');

    const attached = await callTool(app, access, 'create_note', {
      title: 'Toplantı notları',
      contentMarkdown: 'kararlar',
      taskId: task.id,
    });
    expect(attached.structuredContent.linkedTaskId).toBe(task.id);
    // The link exists in the same write — not a second call that could fail.
    expect(
      tables.note_links.filter(
        (l) => l.note_id === attached.structuredContent.note.id && l.linked_entity_id === task.id,
      ),
    ).toHaveLength(1);

    // Reachability both ways: the task shows its note, the note list finds it.
    const detail = await callTool(app, access, 'get_task', { taskId: task.id });
    expect(detail.structuredContent.task.notes).toEqual([
      { id: attached.structuredContent.note.id, title: 'Toplantı notları' },
    ]);
    const listed = await callTool(app, access, 'list_notes', { taskId: task.id });
    expect(listed.structuredContent.notes.map((n) => n.title)).toEqual(['Toplantı notları']);
    // A list carries a summary, never the body.
    expect(listed.structuredContent.notes[0].summary).toBe('kararlar');
    expect(listed.structuredContent.notes[0]).not.toHaveProperty('text');
  });

  it('an unknown project creates NOTHING, and the same key replays', async () => {
    const before = tables.notes.length;
    const refused = await callTool(app, access, 'create_note', {
      title: 'Olmayan projeye',
      projectName: 'muhasebe',
    });
    expect(refused.structuredContent.created).toBe(false);
    expect(refused.structuredContent.reason).toBe('PROJECT_NOT_FOUND');
    expect(tables.notes.length).toBe(before);

    const first = await callTool(app, access, 'create_note', {
      title: 'Tek kere',
      idempotencyKey: 'note-key-0001',
    });
    const second = await callTool(app, access, 'create_note', {
      title: 'Tek kere',
      idempotencyKey: 'note-key-0001',
    });
    expect(second.structuredContent.replayed).toBe(true);
    expect(second.structuredContent.note.id).toBe(first.structuredContent.note.id);
    expect(tables.notes.filter((n) => n.title === 'Tek kere')).toHaveLength(1);
  });

  it('a rich-text note refuses a body rewrite but still takes title/pin/archive', async () => {
    // The app's own notes are delta-canonical; this is the note the user typed.
    const rich = await seed(owner.headers, owner.workspace.id, 'notes', {
      title: 'Elle yazılmış',
      contentDelta: [{ insert: 'biçimli metin\n' }],
    });

    const refused = await callTool(app, access, 'update_note', {
      noteId: rich.id,
      contentMarkdown: 'düzleştirme',
    });
    expect(refused.isError).toBe(true);
    expect(refused.structuredContent.code).toBe('NOTE_NOT_MARKDOWN');
    // Nothing was flattened: the delta is untouched and the body still reads.
    const row = tables.notes.find((n) => n.id === rich.id);
    expect(row.content_markdown ?? null).toBeNull();
    expect(row.plain_text).toContain('biçimli metin');

    const renamed = await callTool(app, access, 'update_note', {
      noteId: rich.id,
      title: 'Yeni ad',
      isPinned: true,
    });
    expect(renamed.structuredContent.note.title).toBe('Yeni ad');
    expect(renamed.structuredContent.note.isPinned).toBe(true);
  });

  it('a markdown note takes a new body, and the search column follows it', async () => {
    const created = await callTool(app, access, 'create_note', {
      title: 'Markdown not',
      contentMarkdown: 'ilk gövde',
    });
    const noteId = created.structuredContent.note.id;

    await callTool(app, access, 'update_note', {
      noteId,
      contentMarkdown: 'ikinci gövde ışık',
    });
    expect(tables.notes.find((n) => n.id === noteId).plain_text).toContain('ikinci gövde');
    // …and the note is findable by the new body through the fold search.
    const found = await callTool(app, access, 'search', { query: 'isik', types: ['note'] });
    expect(found.structuredContent.results.map((r) => r.id)).toContain(noteId);
  });

  it('links and unlinks notes, and says so honestly both times', async () => {
    const project = await seed(owner.headers, owner.workspace.id, 'projects', { name: 'Ev' });
    const note = await callTool(app, access, 'create_note', { title: 'Bağlanacak' });
    const noteId = note.structuredContent.note.id;

    const linked = await callTool(app, access, 'link_note', {
      noteId,
      entityType: 'project',
      entityId: project.id,
    });
    expect(linked.structuredContent.linked).toBe(true);

    const twice = await callTool(app, access, 'link_note', {
      noteId,
      entityType: 'project',
      entityId: project.id,
    });
    expect(twice.isError).toBe(true);
    expect(twice.structuredContent.code).toBe('NOTE_LINK_EXISTS');

    // get_note shows what it is attached to, with the target's own name.
    const detail = await callTool(app, access, 'get_note', { noteId });
    expect(detail.structuredContent.note.linkedTo).toEqual([
      { entityType: 'project', entityId: project.id, title: 'Ev' },
    ]);

    const removed = await callTool(app, access, 'unlink_note', {
      noteId,
      entityType: 'project',
      entityId: project.id,
    });
    expect(removed.structuredContent.unlinked).toBe(true);
    expect(tables.note_links.filter((l) => l.note_id === noteId)).toHaveLength(0);
    // The note itself survived — unlink is not a delete.
    expect(tables.notes.find((n) => n.id === noteId).deleted_at ?? null).toBeNull();

    const again = await callTool(app, access, 'unlink_note', {
      noteId,
      entityType: 'project',
      entityId: project.id,
    });
    expect(again.structuredContent.unlinked).toBe(false);
    expect(again.structuredContent.reason).toBe('LINK_NOT_FOUND');
  });
});

describe('project, tag and file tools (OPH-263)', () => {
  it('creates and updates a project; the list carries open-task counts', async () => {
    const created = await callTool(app, access, 'create_project', {
      name: 'Taşınma',
      description: 'kutular',
      dueAt: new Date(Date.now() + 7 * 86400000).toISOString(),
    });
    expect(created.structuredContent.created).toBe(true);
    const projectId = created.structuredContent.project.id;
    expect(
      tables.sync_revisions.some((r) => r.entity_id === projectId && r.entity_type === 'project'),
    ).toBe(true);

    await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Kutu al', projectId });
    const done = await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Bitmiş iş',
      projectId,
    });
    await callTool(app, access, 'complete_task', { taskId: done.id });

    const listed = await callTool(app, access, 'list_projects', {});
    const mine = listed.structuredContent.projects.find((p) => p.id === projectId);
    expect(mine.openTaskCount).toBe(1); // the completed one does not count

    const updated = await callTool(app, access, 'update_project', {
      projectId,
      status: 'paused',
      description: null,
    });
    expect(updated.structuredContent.project.status).toBe('paused');
    expect(tables.projects.find((p) => p.id === projectId).description).toBeNull();
  });

  it('refuses to archive a project — that cascade is a human decision', async () => {
    const created = await callTool(app, access, 'create_project', { name: 'Biten' });
    const result = await callTool(app, access, 'update_project', {
      projectId: created.structuredContent.project.id,
      status: 'archived',
    });
    expect(result.isError).toBe(true);
    expect(result.structuredContent.code).toBe('PROJECT_ARCHIVE_NOT_SUPPORTED');
    expect(tables.projects.find((p) => p.id === created.structuredContent.project.id).status).toBe(
      'active',
    );
  });

  it('creates tags, lists them, and refuses a duplicate name', async () => {
    const created = await callTool(app, access, 'create_tag', { name: 'Işık' });
    expect(created.structuredContent.tag.name).toBe('Işık');

    // The slug rule is the domain's, race and all — the tool inherits it.
    const duplicate = await callTool(app, access, 'create_tag', { name: 'Işık' });
    expect(duplicate.isError).toBe(true);
    expect(duplicate.structuredContent.code).toBe('TAG_SLUG_TAKEN');

    const listed = await callTool(app, access, 'list_tags', {});
    expect(listed.structuredContent.tags.map((t) => t.name)).toEqual(['Işık']);

    // …and the name the list hands out is what update_task resolves against.
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Etiketlenecek' });
    const tagged = await callTool(app, access, 'update_task', {
      taskId: task.id,
      tags: [listed.structuredContent.tags[0].name],
    });
    expect(tagged.structuredContent.updated).toBe(true);
    expect(tables.task_tags.filter((t) => t.task_id === task.id)).toHaveLength(1);
  });

  it('lists attachment metadata and never a way to fetch the bytes', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', { title: 'Ekli görev' });
    await app.db('files').insert({
      id: newId(),
      workspace_id: owner.workspace.id,
      target_type: 'task',
      target_id: task.id,
      uploaded_by: owner.user.id,
      name: 'fatura.pdf',
      mime: 'application/pdf',
      size_bytes: 12345,
      storage_key: `ws/${owner.workspace.id}/fatura.pdf`,
      status: 'ready',
      revision: 1,
    });
    // An upload still in flight is not an attachment yet.
    await app.db('files').insert({
      id: newId(),
      workspace_id: owner.workspace.id,
      target_type: 'task',
      target_id: task.id,
      name: 'yarim.png',
      mime: 'image/png',
      size_bytes: 10,
      storage_key: `ws/${owner.workspace.id}/yarim.png`,
      status: 'uploading',
      revision: 1,
    });

    const result = await callTool(app, access, 'list_files', {
      targetType: 'task',
      targetId: task.id,
    });
    expect(result.structuredContent.files).toHaveLength(1);
    const file = result.structuredContent.files[0];
    expect(file).toEqual({
      id: expect.any(String),
      name: 'fatura.pdf',
      mime: 'application/pdf',
      sizeBytes: 12345,
      targetType: 'task',
      targetId: task.id,
      createdAt: expect.any(String),
    });
    // Decision #2, asserted rather than trusted: no key, no URL, no bytes.
    expect(JSON.stringify(result.structuredContent)).not.toContain('storage_key');
    expect(JSON.stringify(result.structuredContent)).not.toMatch(/https?:\/\//);
  });
});

describe('acknowledge_reminder', () => {
  it('get_task hands out the alarm id, and acknowledging it is idempotent', async () => {
    const task = await seed(owner.headers, owner.workspace.id, 'tasks', {
      title: 'Acil iş',
      isUrgent: true,
      remindAt: new Date(Date.now() + 3600000).toISOString(),
    });

    // Reachability first: the id the write tool needs comes from a READ tool,
    // not from the database (DESIGN §22 — an unreachable tool is not a tool).
    const detail = await callTool(app, access, 'get_task', { taskId: task.id });
    const alarms = detail.structuredContent.task.reminders;
    expect(alarms).toHaveLength(1);
    expect(alarms[0].status).toBe('scheduled');
    expect(alarms[0].requiresAcknowledgement).toBe(true);

    const acked = await callTool(app, access, 'acknowledge_reminder', {
      reminderId: alarms[0].id,
    });
    expect(acked.structuredContent.reminder.status).toBe('acknowledged');
    expect(acked.structuredContent.alreadyAcknowledged).toBe(false);
    expect(acked.structuredContent.reminder.taskId).toBe(task.id);

    const again = await callTool(app, access, 'acknowledge_reminder', {
      reminderId: alarms[0].id,
    });
    expect(again.structuredContent.alreadyAcknowledged).toBe(true);
    const log = tables.ai_action_log.filter(
      (l) => JSON.parse(l.proposal).tool === 'acknowledge_reminder',
    );
    expect(log).toHaveLength(2); // both calls are on the record, no-op or not
  });
});
