import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// Needs real MySQL + Redis with migrations applied — exercises the REAL
// InnoDB FULLTEXT index and the JSON content_delta column.
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph040-${Date.now()}`;

describe.runIf(enabled)('integration: notes with FULLTEXT search', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-8' },
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

  const createNote = (payload) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
      headers: owner.headers,
      payload,
    });

  it('round-trips delta JSON and searches via the FULLTEXT index', async () => {
    const delta = [
      { insert: 'Karadeniz yaylaları gezi rotası' },
      { insert: '\n', attributes: { header: 1 } },
      { insert: 'Ayder, Pokut, Badara detayları burada.\n' },
    ];
    const created = await createNote({ title: 'Yayla planı', contentDelta: delta });
    expect(created.statusCode).toBe(201);
    expect(created.json().contentDelta).toEqual(delta);
    expect(created.json().plainText).toContain('Karadeniz yaylaları');

    await createNote({ title: 'Alakasız not', contentDelta: [{ insert: 'başka konu\n' }] });

    const found = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes?q=Pokut`,
      headers: owner.headers,
    });
    expect(found.statusCode).toBe(200);
    expect(found.json().items.map((n) => n.title)).toEqual(['Yayla planı']);

    // The stored plain_text column actually feeds the index.
    const row = await app.db('notes').where({ id: created.json().id }).first('plain_text');
    expect(row.plain_text).toContain('Pokut');
  });
});
