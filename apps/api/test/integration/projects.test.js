import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph030-${Date.now()}`;

describe.runIf(enabled)('integration: project CRUD with sync revisions', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-4' },
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
      // Workspace delete cascades projects + sync_revisions (FKs).
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('walks the full lifecycle and keeps the workspace revision monotonic', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
      headers: owner.headers,
      payload: { name: 'Integration Project', colorRgb: '#00AA55' },
    });
    expect(created.statusCode).toBe(201);
    const project = created.json();
    expect(project.revision).toBe(1);

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
      payload: { status: 'paused', isFavorite: true },
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json().revision).toBe(2);

    const deleted = await app.inject({
      method: 'DELETE',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
    });
    expect(deleted.statusCode).toBe(204);

    // Database-level invariants: 3 log rows, workspace revision = 3, soft delete.
    const ws = await app.db('workspaces').where({ id: owner.workspace.id }).first('revision');
    expect(Number(ws.revision)).toBe(3);
    const log = await app
      .db('sync_revisions')
      .where({ workspace_id: owner.workspace.id, entity_id: project.id })
      .orderBy('revision', 'asc');
    expect(log.map((r) => r.operation)).toEqual(['create', 'update', 'delete']);
    const row = await app.db('projects').where({ id: project.id }).first();
    expect(row.deleted_at).not.toBeNull();
    expect(Number(row.revision)).toBe(3);
  });

  it('denies non-members with 403', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-outsider@example.com`, password: 'integration-pw-4' },
    });
    const outsider = res.json();

    const denied = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
      headers: { authorization: `Bearer ${outsider.tokens.accessToken}` },
    });
    expect(denied.statusCode).toBe(403);
    expect(denied.json()).toMatchObject({ code: 'AUTH_WORKSPACE_FORBIDDEN' });
  });
});
