import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { withRevision } from '../../src/db/sync.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph050-${Date.now()}`;

describe.runIf(enabled)('integration: sync revision generator + pull/push', () => {
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
    expect(res.statusCode).toBe(201);
    const body = res.json();
    owner = {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      // Workspace delete cascades entities + sync tables (FKs).
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('OPH-050: concurrent writers get unique, gapless, monotonic revisions', async () => {
    const WRITERS = 12;
    const revisions = await Promise.all(
      Array.from({ length: WRITERS }, () =>
        app.db.transaction((trx) =>
          withRevision(trx, owner.workspace.id, 'task', newId(), 'create'),
        ),
      ),
    );

    // The workspace row lock serializes writers: 1..N with no dupes, no gaps.
    expect([...revisions].sort((a, b) => a - b)).toEqual(
      Array.from({ length: WRITERS }, (_, i) => i + 1),
    );
    const ws = await app.db('workspaces').where({ id: owner.workspace.id }).first('revision');
    expect(Number(ws.revision)).toBe(WRITERS);
    const logged = await app
      .db('sync_revisions')
      .where({ workspace_id: owner.workspace.id })
      .orderBy('revision', 'asc')
      .select('revision');
    expect(logged.map((r) => Number(r.revision))).toEqual(
      Array.from({ length: WRITERS }, (_, i) => i + 1),
    );
  });

  it('OPH-051/052: push applies a batch, pull replays it as snapshots, LWW protects fields', async () => {
    const clientId = newId();
    const projectId = newId();
    const taskId = newId();
    const base = Number(
      (await app.db('workspaces').where({ id: owner.workspace.id }).first('revision')).revision,
    );

    const pushRes = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: owner.workspace.id,
        baseRevision: base,
        mutations: [
          {
            clientMutationId: newId(),
            entityType: 'project',
            entityId: projectId,
            operation: 'create',
            patch: { name: 'Sync Projesi', colorRgb: '#112233' },
          },
          {
            clientMutationId: newId(),
            entityType: 'task',
            entityId: taskId,
            operation: 'create',
            patch: { title: 'Senkron görev', projectId, priority: 'medium' },
          },
        ],
      },
    });
    expect(pushRes.statusCode).toBe(200);
    expect(pushRes.json().results.map((r) => r.status)).toEqual(['applied', 'applied']);

    const pullRes = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=${base}`,
      headers: owner.headers,
    });
    expect(pullRes.statusCode).toBe(200);
    const changes = pullRes.json().changes;
    expect(changes.map((c) => c.entityType)).toEqual(['project', 'task']);
    expect(changes[1].data).toMatchObject({ id: taskId, title: 'Senkron görev', projectId });

    // A foreign (REST) edit wins over a stale offline patch, field by field.
    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${taskId}`,
      headers: owner.headers,
      payload: { title: 'Sunucuda düzenlendi' },
    });
    expect(patched.statusCode).toBe(200);

    const stalePush = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: owner.workspace.id,
        baseRevision: base,
        mutations: [
          {
            clientMutationId: newId(),
            entityType: 'task',
            entityId: taskId,
            operation: 'update',
            patch: { title: 'Bayat offline başlık', priority: 'high' },
            localUpdatedAt: '2020-01-01T00:00:00.000Z',
          },
        ],
      },
    });
    const result = stalePush.json().results[0];
    expect(result).toMatchObject({ status: 'applied', discardedFields: ['title'] });
    const row = await app.db('tasks').where({ id: taskId }).first();
    expect(row.title).toBe('Sunucuda düzenlendi');
    expect(row.priority).toBe('high');
  });

  it('OPH-053: replaying a processed batch returns recorded results without re-applying', async () => {
    const clientId = newId();
    const noteId = newId();
    const mutation = {
      clientMutationId: newId(),
      entityType: 'note',
      entityId: noteId,
      operation: 'create',
      patch: { title: 'Tek sefer', contentDelta: [{ insert: 'idempotent\n' }] },
    };
    const payload = {
      clientId,
      workspaceId: owner.workspace.id,
      baseRevision: 0,
      mutations: [mutation],
    };

    const first = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload,
    });
    const firstResult = first.json().results[0];
    expect(firstResult).toMatchObject({ status: 'applied', replayed: false });

    const replay = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload,
    });
    expect(replay.json().results[0]).toMatchObject({
      status: 'applied',
      revision: firstResult.revision,
      replayed: true,
    });
    expect(replay.json().toRevision).toBe(first.json().toRevision);

    const notes = await app.db('notes').where({ id: noteId }).select();
    expect(notes).toHaveLength(1);
    const logged = await app
      .db('sync_revisions')
      .where({ entity_type: 'note', entity_id: noteId })
      .select();
    expect(logged).toHaveLength(1);
  });
});
