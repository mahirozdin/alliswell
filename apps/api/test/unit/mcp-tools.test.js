import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fullDance, callTool, rpc } from '../helpers/mcpdance.js';

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
