import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph032-${Date.now()}`;

describe.runIf(enabled)('integration: task CRUD, filters, subtree delete', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-6' },
    });
    const body = res.json();
    owner = {
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
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

  const createTask = (payload) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload,
    });

  it('creates a tagged task with checklist, filters it, then deletes the subtree', async () => {
    const tag = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
        headers: owner.headers,
        payload: { name: 'Entegrasyon' },
      })
    ).json();

    const parent = (
      await createTask({
        title: 'Parent task',
        tagIds: [tag.id],
        isUrgent: true,
        dueAt: '2026-07-16T09:00:00.000Z',
      })
    ).json();
    expect(parent.tagIds).toEqual([tag.id]);

    const child = (await createTask({ title: 'Child', parentTaskId: parent.id })).json();

    const item = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${parent.id}/checklist`,
        headers: owner.headers,
        payload: { title: 'Adım 1' },
      })
    ).json();
    expect(item.taskId).toBe(parent.id);

    // Filters hit real SQL: tag join + urgency + due range.
    const filtered = await app.inject({
      method: 'GET',
      url:
        `/api/v1/workspaces/${owner.workspace.id}/tasks` +
        `?tagId=${tag.id}&urgent=true&dueFrom=2026-07-16T00:00:00.000Z&dueTo=2026-07-16T23:59:59.000Z`,
      headers: owner.headers,
    });
    expect(filtered.json().items.map((t) => t.id)).toEqual([parent.id]);

    // Subtree delete: both tasks soft-deleted, each with its own sync log row.
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${parent.id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);

    const rows = await app
      .db('tasks')
      .whereIn('id', [parent.id, child.id])
      .select('id', 'deleted_at');
    expect(rows.every((r) => r.deleted_at !== null)).toBe(true);

    const log = await app
      .db('sync_revisions')
      .where({ workspace_id: owner.workspace.id, operation: 'delete', entity_type: 'task' })
      .select('entity_id');
    expect(log.map((r) => r.entity_id).sort()).toEqual([parent.id, child.id].sort());
  });

  it('paginates with the ULID cursor on real data', async () => {
    for (let i = 1; i <= 3; i += 1) {
      expect((await createTask({ title: `Page ${i}` })).statusCode).toBe(201);
    }
    const page1 = (
      await app.inject({
        method: 'GET',
        url: `/api/v1/workspaces/${owner.workspace.id}/tasks?limit=2`,
        headers: owner.headers,
      })
    ).json();
    expect(page1.items).toHaveLength(2);
    expect(page1.nextCursor).toBe(page1.items.at(-1).id);

    const page2 = (
      await app.inject({
        method: 'GET',
        url: `/api/v1/workspaces/${owner.workspace.id}/tasks?limit=2&cursor=${page1.nextCursor}`,
        headers: owner.headers,
      })
    ).json();
    const overlap = page2.items.filter((t) => page1.items.some((p) => p.id === t.id));
    expect(overlap).toHaveLength(0);
  });
});
