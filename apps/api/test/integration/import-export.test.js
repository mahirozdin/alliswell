import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-266 + OPH-264 over real MySQL: issue #3's acceptance test.
 *
 * The unit suites already prove the schemas, the closed doors and the refusal
 * codes against a fake db. What only real infrastructure can prove is here:
 *
 * - the ROUND TRIP — imported rows are indistinguishable from typed ones, so
 *   they appear in `/sync/pull` (they reach devices with no import-aware code
 *   anywhere in the clients) and come back out of `/export/notes` unchanged;
 * - a real key authenticating a real script end to end, against the real
 *   `api_keys` unique index and its real foreign keys;
 * - partial success driven by an actual domain refusal rather than a stub.
 */
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph266-${Date.now()}`;
const PASSWORD = 'integration-pw-266';

describe.runIf(enabled)('integration: bulk import/export + API keys (OPH-266, OPH-264)', () => {
  let app;
  let owner;
  let stranger;

  const register = async (suffix) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-${suffix}@example.com`, password: PASSWORD },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    return {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  };

  /** Mints a real key and returns { id, headers } — the plaintext exists once. */
  async function mintKey(identity, name = 'script') {
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${identity.workspace.id}/api-keys`,
      headers: identity.headers,
      payload: { name },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.key.startsWith('awk_')).toBe(true);
    return { id: body.id, token: body.key, headers: { authorization: `Bearer ${body.key}` } };
  }

  const importNotes = (headers, workspaceId, notes) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/import/notes`,
      headers,
      payload: { notes },
    });

  const exportNotes = (headers, workspaceId, query = '') =>
    app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${workspaceId}/export/notes${query}`,
      headers,
    });

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    owner = await register('owner');
    stranger = await register('stranger');
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

  it('round trip: import → /sync/pull sees it → export gives the same document back', async () => {
    const ws = owner.workspace.id;
    const before = Number(
      (await app.db('workspaces').where({ id: ws }).first('revision')).revision,
    );

    const res = await importNotes(owner.headers, ws, [
      { title: 'Birinci not', contentMarkdown: '# Başlık\n\nGövde metni.\n' },
      { title: 'İkinci not', contentMarkdown: '- madde bir\n- madde iki\n', isPinned: true },
      { title: 'Arşivlenmiş not', contentMarkdown: 'Eski içerik.\n', isArchived: true },
    ]);
    expect(res.statusCode).toBe(200);
    const { created, errors } = res.json();
    expect(errors).toEqual([]);
    expect(created).toHaveLength(3);

    // 1. They reach devices: an imported note is an ordinary synced note.
    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=${before}&limit=200`,
      headers: owner.headers,
    });
    expect(pull.statusCode).toBe(200);
    const pulled = pull.json().changes.filter((c) => c.entityType === 'note');
    for (const id of created) {
      expect(
        pulled.some((c) => c.entityId === id),
        `${id} pulled`,
      ).toBe(true);
    }

    // 2. They come back out unchanged — markdown is canonical for an import.
    const exported = await exportNotes(owner.headers, ws);
    expect(exported.statusCode).toBe(200);
    const byId = new Map(exported.json().notes.map((n) => [n.id, n]));
    const first = byId.get(created[0]);
    expect(first).toMatchObject({
      title: 'Birinci not',
      contentFormat: 'markdown',
      contentMarkdown: '# Başlık\n\nGövde metni.\n',
      isPinned: false,
      isArchived: false,
    });
    expect(byId.get(created[1])).toMatchObject({ isPinned: true });
    // An export that quietly dropped the archived note would be the wrong tidy.
    expect(byId.get(created[2])).toMatchObject({ isArchived: true });

    // 3. OPH-267: history says where these came from.
    const versions = await app
      .db('note_versions')
      .whereIn('note_id', created)
      .select('note_id', 'origin');
    expect(versions).toHaveLength(3);
    expect(new Set(versions.map((v) => v.origin))).toEqual(new Set(['import']));
  });

  it('partial success: a dead project fails ONE item and the rest are really created', async () => {
    const ws = owner.workspace.id;
    const ghost = newId(); // a well-formed ULID naming nothing

    const res = await importNotes(owner.headers, ws, [
      { title: 'Sağlam bir not' },
      { title: 'Ölü projeye bağlı', projectId: ghost },
      { title: 'Bundan sonrası da inmeli' },
    ]);

    expect(res.statusCode).toBe(200);
    const { created, errors } = res.json();
    // The failure does not abort the batch — that is the whole design.
    expect(created).toHaveLength(2);
    expect(errors).toHaveLength(1);
    expect(errors[0].index).toBe(1);
    expect(errors[0].code).toBeTruthy();

    const rows = await app.db('notes').whereIn('id', created).select('title');
    expect(rows.map((r) => r.title).sort()).toEqual(['Bundan sonrası da inmeli', 'Sağlam bir not']);
    // The refused item created NOTHING — not a row, not a version.
    const orphan = await app.db('notes').where({ workspace_id: ws, project_id: ghost }).select();
    expect(orphan).toEqual([]);
  });

  it('the ceilings are enforced, not advisory', async () => {
    const ws = owner.workspace.id;

    const tooMany = await importNotes(
      owner.headers,
      ws,
      Array.from({ length: 501 }, (_, i) => ({ title: `Not ${i}` })),
    );
    expect(tooMany.statusCode).toBe(400);

    const emptyBatch = await importNotes(owner.headers, ws, []);
    expect(emptyBatch.statusCode).toBe(400);

    const pageTooBig = await exportNotes(owner.headers, ws, '?limit=201');
    expect(pageTooBig.statusCode).toBe(400);

    // 500 is allowed, so the refusal above is the ceiling and not an off-by-one.
    const atCeiling = await importNotes(
      owner.headers,
      ws,
      Array.from({ length: 500 }, (_, i) => ({ title: `Tavan ${i}` })),
    );
    expect(atCeiling.statusCode).toBe(200);
    expect(atCeiling.json().created).toHaveLength(500);
  });

  it('export paginates by cursor and never repeats or drops a note', async () => {
    const ws = stranger.workspace.id;
    const imported = await importNotes(
      stranger.headers,
      ws,
      Array.from({ length: 25 }, (_, i) => ({ title: `Sayfalı ${i}` })),
    );
    expect(imported.json().created).toHaveLength(25);

    const seen = [];
    let cursor = null;
    for (let page = 0; page < 10; page += 1) {
      const res = await exportNotes(
        stranger.headers,
        ws,
        `?limit=10${cursor ? `&cursor=${cursor}` : ''}`,
      );
      expect(res.statusCode).toBe(200);
      const body = res.json();
      seen.push(...body.notes.map((n) => n.id));
      cursor = body.nextCursor;
      if (!cursor) break;
    }
    expect(seen).toHaveLength(25);
    expect(new Set(seen).size).toBe(25);
  });

  it('a real API key drives the whole script end to end, then revocation stops it dead', async () => {
    const ws = owner.workspace.id;
    const key = await mintKey(owner, 'yedekleme script’i');

    // The key writes…
    const wrote = await importNotes(key.headers, ws, [
      { title: 'Anahtarla gelen not', contentMarkdown: 'Script yazdı.\n' },
    ]);
    expect(wrote.statusCode).toBe(200);
    const [noteId] = wrote.json().created;

    // …and the key reads its own write back.
    const read = await exportNotes(key.headers, ws);
    expect(read.statusCode).toBe(200);
    expect(read.json().notes.some((n) => n.id === noteId)).toBe(true);

    // A key may not mint another key — the closed door, over real rows.
    const escalate = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/api-keys`,
      headers: key.headers,
      payload: { name: 'ikinci anahtar' },
    });
    expect(escalate.statusCode).toBe(403);
    expect(await app.db('api_keys').where({ workspace_id: ws }).count('* as n')).toEqual([
      { n: 1 },
    ]);

    // The workspace binding holds against a real foreign workspace.
    const foreign = await exportNotes(key.headers, stranger.workspace.id);
    expect(foreign.statusCode).toBe(403);

    // last_used_at is real bookkeeping, not a column that never fills.
    const row = await app.db('api_keys').where({ id: key.id }).first();
    expect(row.last_used_at).not.toBeNull();

    const revoke = await app.inject({
      method: 'POST',
      url: `/api/v1/api-keys/${key.id}/revoke`,
      headers: owner.headers,
    });
    expect(revoke.statusCode).toBe(200);

    const afterRevoke = await exportNotes(key.headers, ws);
    expect(afterRevoke.statusCode).toBe(401);
    expect(afterRevoke.json().code).toBe('AUTH_API_KEY_REVOKED');
  });

  it('the key_hash unique index is real, and deleting the user takes its keys with it', async () => {
    const victim = await register(`cascade-${Date.now()}`);
    const key = await mintKey(victim, 'silinecek');
    const row = await app.db('api_keys').where({ id: key.id }).first();

    await expect(app.db('api_keys').insert({ ...row, id: newId(), name: 'çift' })).rejects.toThrow(
      /duplicate|unique/i,
    );

    await app.db('workspaces').where({ owner_id: victim.user.id }).delete();
    await app.db('users').where({ id: victim.user.id }).delete();
    expect(await app.db('api_keys').where({ id: key.id }).first()).toBeUndefined();
  });
});
