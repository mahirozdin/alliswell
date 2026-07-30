import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
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
});
