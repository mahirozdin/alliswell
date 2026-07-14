import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL + Redis with migrations applied — exercises the REAL
// uq_tags_workspace_slug index (case-insensitive utf8mb4_0900_ai_ci collation).
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph031-${Date.now()}`;

describe.runIf(enabled)('integration: tag slug uniqueness on real MySQL', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-5' },
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

  const createTag = (name) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
      headers: owner.headers,
      payload: { name },
    });

  it('creates, conflicts on duplicate, frees the slug after delete', async () => {
    const created = await createTag('Derin İş');
    expect(created.statusCode).toBe(201);
    expect(created.json().slug).toBe('derin-is');

    const dup = await createTag('derin iş');
    expect(dup.statusCode).toBe(409);
    expect(dup.json()).toMatchObject({ code: 'TAG_SLUG_TAKEN' });

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tags/${created.json().id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);

    const recreated = await createTag('Derin İş');
    expect(recreated.statusCode).toBe(201);
    expect(recreated.json().slug).toBe('derin-is');

    const rows = await app.db('tags').where({ workspace_id: owner.workspace.id });
    expect(rows).toHaveLength(2); // soft-deleted original + fresh one
  });
});
