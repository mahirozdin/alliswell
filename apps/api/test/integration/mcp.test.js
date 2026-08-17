import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { newId } from '../../src/lib/ids.js';
import { fullDance, callTool } from '../helpers/mcpdance.js';

/**
 * OPH-218 over real MySQL: the full OAuth dance against a real argon2 user,
 * a create_task that lands a real row + real sync_revisions, and the proof
 * that an MCP write flows to devices — /sync/pull sees the task.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('MCP integration (OPH-218)', () => {
  let app;
  let ws;
  let ownerId;
  let headers;
  const emailPrefix = `mcp-int-${Date.now()}`;

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'sifre-12345' },
    });
    const body = res.json();
    ws = body.workspace.id;
    ownerId = body.user.id;
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('oauth_tokens').whereIn('user_id', ids).delete();
      await app.db('oauth_codes').whereIn('user_id', ids).delete();
      await app.db('mcp_mutations').whereIn('user_id', ids).delete();
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('workspace_members').whereIn('user_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('the full dance mints a token and create_task lands a real synced row', async () => {
    const { tokens } = await fullDance(app, {
      email: `${emailPrefix}-owner@example.com`,
      password: 'sifre-12345',
    });

    const result = await callTool(app, tokens.access_token, 'create_task', {
      title: 'MCP ile oluşturulan görev',
      idempotencyKey: 'int-key-0001',
    });
    expect(result.structuredContent.created).toBe(true);
    const taskId = result.structuredContent.task.id;

    const row = await app.db('tasks').where({ id: taskId }).first();
    expect(row.title).toBe('MCP ile oluşturulan görev');
    const revisions = await app
      .db('sync_revisions')
      .where({ entity_id: taskId, entity_type: 'task' })
      .select();
    expect(revisions.length).toBeGreaterThan(0);

    // The MCP write flows to devices: /sync/pull returns the new task.
    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=0&limit=200`,
      headers,
    });
    expect(pull.statusCode).toBe(200);
    const tasks = pull.json().changes.filter((c) => c.entityType === 'task');
    expect(tasks.some((c) => c.entityId === taskId)).toBe(true);
  });

  it('the idempotency ledger holds under a real unique index', async () => {
    const { tokens } = await fullDance(app, {
      email: `${emailPrefix}-owner@example.com`,
      password: 'sifre-12345',
    });
    const first = await callTool(app, tokens.access_token, 'create_task', {
      title: 'Tekil iş',
      idempotencyKey: 'int-key-0002',
    });
    const second = await callTool(app, tokens.access_token, 'create_task', {
      title: 'Tekil iş',
      idempotencyKey: 'int-key-0002',
    });
    expect(second.structuredContent.replayed).toBe(true);
    expect(second.structuredContent.task.id).toBe(first.structuredContent.task.id);
    const ledger = await app
      .db('mcp_mutations')
      .where({ idempotency_key: 'int-key-0002' })
      .select();
    expect(ledger).toHaveLength(1);
  });

  // ── OPH-263: the domain tools, over the engine that can actually contradict
  // them. The unit suite proves the schemas and the refusals against a fake db;
  // what follows can only fail on real MySQL.

  it('the Turkish fold is app-owned — the engine leaves the ı-gap open', async () => {
    const { tokens } = await fullDance(app, {
      email: `${emailPrefix}-owner@example.com`,
      password: 'sifre-12345',
    });
    const access = tokens.access_token;

    await callTool(app, access, 'create_task', {
      title: 'Işık ayarlarını gözden geçir',
      idempotencyKey: 'int-fold-task',
    });
    await callTool(app, access, 'create_note', {
      title: 'Sığır eti tarifi',
      contentMarkdown: 'Kısık ateşte pişir.\n',
      idempotencyKey: 'int-fold-note',
    });

    // The premise, measured against the shapes the app actually issues rather
    // than remembered. Careful: `'ışık' LIKE '%isik%'` between two LITERALS
    // answers 1 under utf8mb4_0900_ai_ci and will talk you out of this whole
    // mechanism. Against a COLUMN — which is what a query does — it answers 0,
    // and so does FULLTEXT. Both of the engine's own paths miss the word.
    const naiveLike = await app
      .db('tasks')
      .where({ workspace_id: ws })
      .whereRaw('title LIKE ?', ['%isik%'])
      .count('* as n');
    expect(Number(naiveLike[0].n)).toBe(0);

    const naiveFulltext = await app
      .db('notes')
      .where({ workspace_id: ws })
      .whereRaw('MATCH(title, plain_text) AGAINST(? IN BOOLEAN MODE)', ['sigir*'])
      .count('* as n');
    expect(Number(naiveFulltext[0].n)).toBe(0);

    // Dotless ı typed as i — the way somebody actually searches on a phone.
    // The app-owned fold is what turns both misses into hits.
    const isik = await callTool(app, access, 'search', { query: 'isik ayarlari' });
    expect(
      isik.structuredContent.results.some((r) => r.title === 'Işık ayarlarını gözden geçir'),
    ).toBe(true);

    const sigir = await callTool(app, access, 'search', { query: 'sigir' });
    expect(sigir.structuredContent.results.some((r) => r.title === 'Sığır eti tarifi')).toBe(true);
  });

  it('one dance reaches across entities: project → task → note, both directions', async () => {
    const { tokens } = await fullDance(app, {
      email: `${emailPrefix}-owner@example.com`,
      password: 'sifre-12345',
    });
    const access = tokens.access_token;

    const project = await callTool(app, access, 'create_project', {
      name: 'Taşınma',
      idempotencyKey: 'int-x-project',
    });
    const projectId = project.structuredContent.project.id;

    const task = await callTool(app, access, 'create_task', {
      title: 'Nakliyeci ara',
      projectName: 'Taşınma',
      idempotencyKey: 'int-x-task',
    });
    const taskId = task.structuredContent.task.id;
    expect(task.structuredContent.task.projectId).toBe(projectId);

    // A standalone note and a note about a task are the same tool.
    const note = await callTool(app, access, 'create_note', {
      title: 'Nakliyeci teklifleri',
      contentMarkdown: '- A firması: 12.000\n- B firması: 9.500\n',
      taskId,
      idempotencyKey: 'int-x-note',
    });
    const noteId = note.structuredContent.note.id;

    // Reachable from the task…
    const gotTask = await callTool(app, access, 'get_task', { taskId });
    expect(JSON.stringify(gotTask.structuredContent)).toContain(noteId);

    // …and the note knows what it is about. Real FKs, real join rows.
    const link = await app
      .db('note_links')
      .where({ note_id: noteId, linked_entity_type: 'task', linked_entity_id: taskId })
      .first();
    expect(link).toBeTruthy();

    // Linking the same pair twice is an honest refusal, not a duplicate row.
    // A tool refusal is an `isError` RESULT, not a JSON-RPC error.
    const again = await callTool(app, access, 'link_note', {
      noteId,
      entityType: 'task',
      entityId: taskId,
    });
    expect(again.isError).toBe(true);
    expect(again.structuredContent.code).toBe('NOTE_LINK_EXISTS');
    const links = await app
      .db('note_links')
      .where({ note_id: noteId, linked_entity_type: 'task', linked_entity_id: taskId })
      .select();
    expect(links).toHaveLength(1);
  });

  it('MCP note and project writes reach devices too, not just tasks', async () => {
    const before = Number(
      (await app.db('workspaces').where({ id: ws }).first('revision')).revision,
    );
    const { tokens } = await fullDance(app, {
      email: `${emailPrefix}-owner@example.com`,
      password: 'sifre-12345',
    });
    const access = tokens.access_token;

    const project = await callTool(app, access, 'create_project', {
      name: 'Yayın hazırlığı',
      idempotencyKey: 'int-sync-project',
    });
    const note = await callTool(app, access, 'create_note', {
      title: 'Sürüm notları',
      contentMarkdown: 'Taslak.\n',
      idempotencyKey: 'int-sync-note',
    });

    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=${before}&limit=200`,
      headers,
    });
    expect(pull.statusCode).toBe(200);
    const ids = pull.json().changes.map((c) => c.entityId);
    expect(ids).toContain(project.structuredContent.project.id);
    expect(ids).toContain(note.structuredContent.note.id);
  });

  it('list_files hands over no URL and no storage key (AI.md §7), over real rows', async () => {
    const { tokens } = await fullDance(app, {
      email: `${emailPrefix}-owner@example.com`,
      password: 'sifre-12345',
    });
    const access = tokens.access_token;

    const fileId = newId();
    await app.db('files').insert({
      id: fileId,
      workspace_id: ws,
      target_type: 'workspace',
      target_id: ws,
      uploaded_by: ownerId,
      name: 'sozlesme.pdf',
      mime: 'application/pdf',
      size_bytes: 1024,
      storage_key: `ws/${ws}/gizli-anahtar-degeri`,
      status: 'ready',
    });

    const listed = await callTool(app, access, 'list_files', {});
    const payload = JSON.stringify(listed);
    expect(payload).toContain('sozlesme.pdf');
    // The boundary: bytes and the means of reaching them never enter MCP.
    expect(payload).not.toContain('gizli-anahtar-degeri');
    expect(payload).not.toMatch(/X-Amz-Signature|https?:\/\//);
  });
});
