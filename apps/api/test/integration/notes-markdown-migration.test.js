import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';
import { up as convertToMarkdown } from '../../migrations/20260818090000_notes_markdown_canonical.js';

/**
 * OPH-274 (ADR-0033) over real MySQL: the conversion every existing note goes
 * through on deploy.
 *
 * A unit test with a fake table cannot prove this. The rows are seeded by
 * writing `content_format='delta'` and a real Delta straight into MySQL —
 * which is exactly what the database holds the moment before the migration
 * runs, and which the API can no longer produce, because every write path now
 * normalizes. So the fixture has to bypass the API on purpose.
 *
 * The assertion that matters most is the embed one. `deltaToMarkdown` takes an
 * `embedLabel` resolver, and it is easy to write a converter that puts the
 * file NAME where the URI belongs. If that went wrong, every image in every
 * migrated note would silently stop resolving — and the note would still look
 * fine in a list, because only the body changed.
 */
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph274-${Date.now()}`;
const PASSWORD = 'integration-pw-274';

describe.runIf(enabled)('integration: notes become markdown-canonical (OPH-274)', () => {
  let app;
  let owner;
  let fileId;

  /** Writes a pre-ADR-0033 row straight into MySQL, bypassing normalization. */
  const seedDeltaNote = async ({ title, delta, markdown = null }) => {
    const id = newId();
    await app.db('notes').insert({
      id,
      workspace_id: owner.workspace.id,
      title,
      content_delta: JSON.stringify(delta),
      content_markdown: markdown,
      content_format: 'delta',
      plain_text: 'ESKİ ARAMA KOLONU',
      created_by: owner.user.id,
      updated_by: owner.user.id,
      revision: 1,
    });
    return id;
  };

  const seedDeltaVersion = async ({ noteId, title, delta }) => {
    const id = newId();
    await app.db('note_versions').insert({
      id,
      workspace_id: owner.workspace.id,
      note_id: noteId,
      note_revision: 1,
      title,
      content_delta: JSON.stringify(delta),
      content_markdown: null,
      content_format: 'delta',
      content_hash: 'stale-hash-from-before-the-migration'.padEnd(64, '0').slice(0, 64),
      origin: 'edit',
    });
    return id;
  };

  const noteRow = (id) => app.db('notes').where({ id }).first();

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig() });
    await app.ready();

    const registered = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}@example.com`, password: PASSWORD },
    });
    expect(registered.statusCode).toBe(201);
    const body = registered.json();
    owner = {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };

    // A real, ready file row so the embed resolver has a name to find.
    fileId = newId();
    await app.db('files').insert({
      id: fileId,
      workspace_id: owner.workspace.id,
      target_type: 'note',
      target_id: newId(),
      name: 'Şema.png',
      mime: 'image/png',
      size_bytes: 12,
      storage_key: `ws/${owner.workspace.id}/${fileId}`,
      status: 'ready',
      uploaded_by: owner.user.id,
    });
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

  it('converts a Delta body, keeping the embed URI and relabelling only the alt text', async () => {
    const id = await seedDeltaNote({
      title: 'Şemalı not',
      delta: [
        { insert: 'Başlık' },
        { insert: '\n', attributes: { header: 1 } },
        { insert: 'Diyagram:\n' },
        { insert: { image: `alliswell://file/${fileId}` } },
        { insert: '\n' },
      ],
    });

    await convertToMarkdown(app.db);

    const row = await noteRow(id);
    expect(row.content_format).toBe('markdown');
    // The URI is what the renderer resolves and what an export carries. If the
    // file NAME had landed here instead, every migrated image would break.
    expect(row.content_markdown).toContain(`](alliswell://file/${fileId})`);
    expect(row.content_markdown).toContain('![Şema.png](');
    expect(row.content_markdown).toContain('# Başlık');
    // The Delta is preserved: never written again, still readable.
    expect(row.content_delta).not.toBeNull();
  });

  it('re-derives the search column from the markdown it just produced', async () => {
    const id = await seedDeltaNote({
      title: 'Aranabilir',
      delta: [{ insert: 'deniz feneri rotası\n' }],
    });

    await convertToMarkdown(app.db);

    const row = await noteRow(id);
    expect(row.plain_text).toBe('deniz feneri rotası');

    // …and FULLTEXT can now find it, which is the only proof that matters.
    const found = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes?q=feneri`,
      headers: owner.headers,
    });
    expect(found.json().items.map((n) => n.id)).toContain(id);
  });

  it('converts note_versions too, so history can still be a merge base', async () => {
    const noteId = await seedDeltaNote({ title: 'Geçmişli', delta: [{ insert: 'baş\n' }] });
    const versionId = await seedDeltaVersion({
      noteId,
      title: 'Geçmişli',
      delta: [{ insert: 'eski sürüm gövdesi\n' }],
    });

    await convertToMarkdown(app.db);

    const version = await app.db('note_versions').where({ id: versionId }).first();
    expect(version.content_format).toBe('markdown');
    expect(version.content_markdown).toBe('eski sürüm gövdesi');
    // The digest is recomputed, or the first edit after deploy would stack a
    // duplicate version onto every note (ADR-0031 §4).
    expect(version.content_hash).not.toContain('stale-hash');
  });

  it('converts a Delta-canonical row that never had a Delta', async () => {
    const id = newId();
    await app.db('notes').insert({
      id,
      workspace_id: owner.workspace.id,
      title: 'Hiç yazılmamış',
      content_delta: null,
      content_markdown: null,
      content_format: 'delta',
      created_by: owner.user.id,
      updated_by: owner.user.id,
      revision: 1,
    });

    await convertToMarkdown(app.db);

    // Left behind, this would be the one row in the table whose format still
    // names a writer that no longer exists.
    expect((await noteRow(id)).content_format).toBe('markdown');
  });

  it('is idempotent — a second run finds nothing left to do', async () => {
    const id = await seedDeltaNote({ title: 'Tekrar', delta: [{ insert: 'gövde\n' }] });

    await convertToMarkdown(app.db);
    const first = await noteRow(id);
    await convertToMarkdown(app.db);
    const second = await noteRow(id);

    expect(second.content_markdown).toBe(first.content_markdown);
    expect(second.plain_text).toBe(first.plain_text);
  });

  it('leaves a markdown note completely alone', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
      headers: owner.headers,
      payload: { title: 'Zaten markdown', contentMarkdown: '# Elle yazılmış\n\ngövde' },
    });
    const id = created.json().id;
    const before = await noteRow(id);

    await convertToMarkdown(app.db);

    const after = await noteRow(id);
    expect(after.content_markdown).toBe(before.content_markdown);
    expect(after.plain_text).toBe(before.plain_text);
  });
});
