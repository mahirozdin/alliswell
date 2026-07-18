import { describe, it, expect } from 'vitest';
import { deltaToMarkdown, deltaToPlainText, embedFileIds } from '../../src/lib/delta.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fakeStorage } from '../helpers/fakestorage.js';

// OPH-152 — attachment embeds in the canonical markdown converter
// (ATTACHMENTS.md §7). These fixtures are the parity contract the Dart
// converter must mirror in OPH-156.

const FILE_A = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const uri = (id) => `alliswell://file/${id}`;

describe('deltaToMarkdown embeds', () => {
  it('renders image embeds as markdown images, others as links', () => {
    const ops = [
      { insert: 'Before\n' },
      { insert: { image: uri(FILE_A) } },
      { insert: '\n' },
      { insert: { video: uri(FILE_A) } },
      { insert: '\nAfter\n' },
    ];
    expect(deltaToMarkdown(ops)).toBe(
      `Before\n![](${uri(FILE_A)})\n[attachment](${uri(FILE_A)})\nAfter`,
    );
  });

  it('labels embeds through the resolver (export uses the file name)', () => {
    const ops = [
      { insert: { image: uri(FILE_A) } },
      { insert: '\n' },
      { insert: { video: 'https://example.com/clip.mp4' } },
      { insert: '\n' },
    ];
    const embedLabel = (source) => (source === uri(FILE_A) ? 'Özet.png' : null);
    expect(deltaToMarkdown(ops, { embedLabel })).toBe(
      `![Özet.png](${uri(FILE_A)})\n[attachment](https://example.com/clip.mp4)`,
    );
  });

  it('drops unknown embed shapes and keeps plain text extraction embed-free', () => {
    const ops = [{ insert: { formula: 'x^2' } }, { insert: 'text\n' }];
    expect(deltaToMarkdown(ops)).toBe('text');
    expect(deltaToPlainText([{ insert: { image: uri(FILE_A) } }, { insert: 'searchable' }])).toBe(
      'searchable',
    );
  });
});

describe('embedFileIds', () => {
  it('extracts alliswell file ids from image+video embeds, unique, ignoring foreign urls', () => {
    const other = '01BX5ZZKBKACTAV9WEVGEMMVS0';
    const ops = [
      { insert: { image: uri(FILE_A) } },
      { insert: { video: uri(other) } },
      { insert: { image: uri(FILE_A) } }, // duplicate
      { insert: { image: 'https://example.com/x.png' } },
      { insert: 'text' },
    ];
    expect(embedFileIds(ops)).toEqual([FILE_A, other]);
    expect(embedFileIds(null)).toEqual([]);
  });
});

describe('GET /notes/:id/export with embeds', () => {
  it('labels file embeds with their current name; unknown ids stay bare', async () => {
    const store = fakeStorage();
    const { app } = await buildTestApp({ storage: store });
    const session = await registerUser(app, { email: 'export-embeds@example.com' });
    const wsId = session.workspace.id;

    const note = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${wsId}/notes`,
      headers: session.headers,
      payload: { title: 'With media' },
    });
    const noteId = note.json().id;

    // Upload a real (fake-stored) file attached to the note.
    const init = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${wsId}/files`,
      headers: session.headers,
      payload: { targetType: 'note', targetId: noteId, name: 'Şema.png', sizeBytes: 9 },
    });
    const fileId = init.json().file.id;
    store.objects.set(`ws/${wsId}/${fileId}`, 9);
    await app.inject({
      method: 'POST',
      url: `/api/v1/files/${fileId}/complete`,
      headers: session.headers,
    });

    const ghost = '01BX5ZZKBKACTAV9WEVGEMMVS0';
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${noteId}`,
      headers: session.headers,
      payload: {
        contentDelta: [
          { insert: 'Diagram:\n' },
          { insert: { image: uri(fileId) } },
          { insert: '\n' },
          { insert: { image: uri(ghost) } },
          { insert: '\n' },
        ],
      },
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${noteId}/export?format=md`,
      headers: session.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain(`![Şema.png](${uri(fileId)})`);
    expect(res.body).toContain(`![](${uri(ghost)})`);
    await app.close();
  });
});
