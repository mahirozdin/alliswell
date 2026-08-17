import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { markdownToPlainText } from '../../src/lib/delta.js';

/**
 * OPH-261 — a markdown-canonical note can be found, and exports itself.
 *
 * Two measured defects, both of the same shape: the code knew about ADR-0028's
 * two canonical forms in one place and not in the others. `plain_text` was
 * derived only from a delta, so a markdown note was invisible to `?q=`, to
 * FULLTEXT and to the MCP search tools; and the export preferred the delta
 * whenever one existed, so a converted note exported the shadow of an earlier
 * life instead of the document its editor writes.
 */
let app;
let owner;
let workspaceId;

beforeEach(async () => {
  ({ app } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
  workspaceId = owner.workspace.id;
});

afterEach(async () => {
  await app.close();
});

async function createNote(body) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${workspaceId}/notes`,
    headers: owner.headers,
    payload: body,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

describe('markdownToPlainText', () => {
  it('keeps the words and drops the syntax', () => {
    expect(markdownToPlainText('# Başlık\n\nBu **kalın** ve _italik_ bir not.')).toBe(
      'Başlık Bu kalın ve italik bir not.',
    );
    expect(markdownToPlainText('- [ ] süt al\n- [x] ekmek')).toBe('süt al ekmek');
    expect(markdownToPlainText('==vurgulu== ve ~~üstü çizili~~')).toBe('vurgulu ve üstü çizili');
  });

  it('keeps a link label and drops its target', () => {
    // Nobody searches a note for "https://" — they search for the words.
    expect(markdownToPlainText('[AllisWell](https://alliswell.space) harika')).toBe(
      'AllisWell harika',
    );
  });

  it('drops images and fenced code', () => {
    expect(markdownToPlainText('![resim](alliswell://file/1) yanında yazı')).toBe('yanında yazı');
    expect(markdownToPlainText('```js\nconst x = 1;\n```\nkod dışı')).toBe('kod dışı');
  });

  it('is empty for nothing, and never throws on junk', () => {
    expect(markdownToPlainText('')).toBe('');
    expect(markdownToPlainText(null)).toBe('');
    expect(markdownToPlainText(undefined)).toBe('');
  });
});

describe('a markdown-canonical note is searchable (Repair 1)', () => {
  it('derives plain_text on create', async () => {
    const note = await createNote({
      title: 'Yayla',
      contentFormat: 'markdown',
      contentMarkdown: '# Pokut\n\nRota **çok** güzeldi.',
    });

    expect(note.plainText).toContain('Rota çok güzeldi.');
  });

  it('derives it on update, too', async () => {
    const note = await createNote({
      title: 'Yayla',
      contentFormat: 'markdown',
      contentMarkdown: 'ilk hali',
    });

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: { contentMarkdown: '## Sonraki\n\nyeni gövde' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().plainText).toBe('Sonraki yeni gövde');
  });

  it('finds it through the list filter — the point of the column', async () => {
    await createNote({
      title: 'Alışveriş',
      contentFormat: 'markdown',
      contentMarkdown: 'süt ve **yumurta** al',
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${workspaceId}/notes?q=yumurta`,
      headers: owner.headers,
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().items.map((n) => n.title)).toEqual(['Alışveriş']);
  });

  it('derives from the markdown even when a Delta rides along', async () => {
    // ADR-0028 needed a guard here, because a note had two possible canonical
    // fields and the app sent both on every save — deriving from the wrong one
    // would re-base the search column on a generated document. ADR-0033 left
    // one field, so there is one derivation and nothing to guess.
    const note = await createNote({
      title: 'Eski istemci',
      contentDelta: [{ insert: 'delta gövdesi\n' }],
      contentMarkdown: 'markdown gövdesi',
    });

    expect(note.contentFormat).toBe('markdown');
    expect(note.plainText).toBe('markdown gövdesi');
  });

  it('derives from a converted Delta when that is all the client sent', async () => {
    const note = await createNote({
      title: 'Yalnız delta',
      contentDelta: [{ insert: 'yalnızca delta\n' }],
    });

    expect(note.contentMarkdown).toBe('yalnızca delta');
    expect(note.plainText).toBe('yalnızca delta');
  });
});

describe('the export follows the canonical field (Repair 2)', () => {
  it('a markdown note exports its markdown, not its stale delta', async () => {
    const note = await createNote({
      title: 'Dönüştürülmüş',
      contentFormat: 'markdown',
      contentMarkdown: '# Gerçek belge\n\nBu kanonik olan.',
      // The shadow an earlier life left behind — it must not win.
      contentDelta: [{ insert: 'eski delta gövdesi\n' }],
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}/export`,
      headers: owner.headers,
    });

    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('Bu kanonik olan.');
    expect(res.body).not.toContain('eski delta gövdesi');
  });

  it('a delta note still exports from its delta', async () => {
    const note = await createNote({
      title: 'Zengin',
      contentDelta: [{ insert: 'delta gövdesi\n' }],
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}/export`,
      headers: owner.headers,
    });

    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('delta gövdesi');
  });
});

describe('notes can be tagged (Repair 3)', () => {
  it('replace-set adds, keeps and removes in one call', async () => {
    const note = await createNote({ title: 'Etiketlenecek' });
    const tag = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/tags`,
      headers: owner.headers,
      payload: { name: 'gezi' },
    });
    const tagId = tag.json().id;

    const put = await app.inject({
      method: 'PUT',
      url: `/api/v1/notes/${note.id}/tags`,
      headers: owner.headers,
      payload: { tagIds: [tagId] },
    });
    expect(put.statusCode).toBe(200);
    expect(put.json().tagIds).toEqual([tagId]);

    // The same call states what the tags ARE — an empty set clears them.
    const cleared = await app.inject({
      method: 'PUT',
      url: `/api/v1/notes/${note.id}/tags`,
      headers: owner.headers,
      payload: { tagIds: [] },
    });
    expect(cleared.json().tagIds).toEqual([]);
  });

  it('refuses a tag from another workspace rather than silently dropping it', async () => {
    const note = await createNote({ title: 'Yabancı etiket' });
    const stranger = await registerUser(app, { email: 'other@example.com' });
    const foreign = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${stranger.workspace.id}/tags`,
      headers: stranger.headers,
      payload: { name: 'başkasının' },
    });

    const res = await app.inject({
      method: 'PUT',
      url: `/api/v1/notes/${note.id}/tags`,
      headers: owner.headers,
      payload: { tagIds: [foreign.json().id] },
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('NOTE_TAG_NOT_FOUND');
  });
});
