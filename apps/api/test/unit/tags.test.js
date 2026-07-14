import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const createTag = (payload, headers = owner.headers) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
    headers,
    payload,
  });

describe('tag CRUD (OPH-031)', () => {
  it('creates a tag with a slug derived from the (Turkish) name', async () => {
    const res = await createTag({ name: 'Derin İş', colorRgb: '#0EA5E9' });

    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      name: 'Derin İş',
      slug: 'derin-is',
      colorRgb: '#0EA5E9',
      revision: 1,
    });
    expect(tables.sync_revisions.at(-1)).toMatchObject({
      entity_type: 'tag',
      operation: 'create',
    });
  });

  it('rejects duplicate names case-insensitively via the slug (409)', async () => {
    expect((await createTag({ name: 'Focus' })).statusCode).toBe(201);

    for (const name of ['Focus', 'FOCUS', 'föcus']) {
      const res = await createTag({ name });
      expect(res.statusCode, name).toBe(409);
      expect(res.json()).toMatchObject({ code: 'TAG_SLUG_TAKEN' });
    }
    expect(tables.tags).toHaveLength(1);
  });

  it('renames follow the slug and conflicting renames answer 409', async () => {
    const focus = (await createTag({ name: 'Focus' })).json();
    expect((await createTag({ name: 'Errand' })).statusCode).toBe(201);

    const renamed = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tags/${focus.id}`,
      headers: owner.headers,
      payload: { name: 'Deep Work' },
    });
    expect(renamed.statusCode).toBe(200);
    expect(renamed.json()).toMatchObject({ name: 'Deep Work', slug: 'deep-work', revision: 3 });

    const clash = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tags/${focus.id}`,
      headers: owner.headers,
      payload: { name: 'errand' },
    });
    expect(clash.statusCode).toBe(409);

    // Renaming to itself (same slug) is fine — no self-conflict.
    const same = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tags/${focus.id}`,
      headers: owner.headers,
      payload: { name: 'DEEP work' },
    });
    expect(same.statusCode).toBe(200);
    expect(same.json().slug).toBe('deep-work');
  });

  it('lists alphabetically, hides deleted, and frees the slug on delete', async () => {
    const zebra = (await createTag({ name: 'Zebra' })).json();
    await createTag({ name: 'Alpha' });

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tags/${zebra.id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);

    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
      headers: owner.headers,
    });
    expect(list.json().items.map((t) => t.name)).toEqual(['Alpha']);

    // Soft-deleted, but the slug slot is released for a recreate.
    expect(tables.tags.find((t) => t.id === zebra.id).slug).toMatch(/^zebra--deleted--/);
    const recreated = await createTag({ name: 'Zebra' });
    expect(recreated.statusCode).toBe(201);
    expect(recreated.json().slug).toBe('zebra');
  });

  it('enforces workspace membership on every route', async () => {
    const tag = (await createTag({ name: 'Private' })).json();
    const outsider = await registerUser(app, { email: 'outsider@example.com' });

    const denials = await Promise.all([
      app.inject({
        method: 'GET',
        url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
        headers: outsider.headers,
      }),
      createTag({ name: 'Sneaky' }, outsider.headers),
      app.inject({ method: 'GET', url: `/api/v1/tags/${tag.id}`, headers: outsider.headers }),
      app.inject({
        method: 'PATCH',
        url: `/api/v1/tags/${tag.id}`,
        headers: outsider.headers,
        payload: { name: 'Hijack' },
      }),
      app.inject({ method: 'DELETE', url: `/api/v1/tags/${tag.id}`, headers: outsider.headers }),
    ]);
    for (const res of denials) {
      expect(res.statusCode).toBe(403);
      expect(res.json()).toMatchObject({ code: 'AUTH_WORKSPACE_FORBIDDEN' });
    }
  });

  it('validates names and colors', async () => {
    expect((await createTag({ name: '' })).statusCode).toBe(400);
    expect((await createTag({ name: 'Ok', colorRgb: 'red' })).statusCode).toBe(400);
    expect((await createTag({})).statusCode).toBe(400);
  });
});
