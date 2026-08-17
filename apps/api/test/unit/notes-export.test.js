import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { deltaToMarkdown } from '../../src/lib/delta.js';

// Fixtures mirror the client converter suite
// (apps/app/test/features/notes/delta_markdown_test.dart) — both converters
// must produce identical documents for the same delta.
describe('lib/delta deltaToMarkdown (OPH-045)', () => {
  it('converts headers, inline styles, links and lists', () => {
    const markdown = deltaToMarkdown([
      { insert: 'Başlık' },
      { insert: '\n', attributes: { header: 1 } },
      { insert: 'Normal ve ' },
      { insert: 'kalın', attributes: { bold: true } },
      { insert: ' ve ' },
      { insert: 'italik', attributes: { italic: true } },
      { insert: ' ve ' },
      { insert: 'bağlantı', attributes: { link: 'https://alliswell.dev' } },
      { insert: '\nMadde bir' },
      { insert: '\n', attributes: { list: 'bullet' } },
      { insert: 'Yapıldı' },
      { insert: '\n', attributes: { list: 'checked' } },
    ]);

    expect(markdown.split('\n')).toEqual([
      '# Başlık',
      'Normal ve **kalın** ve _italik_ ve [bağlantı](https://alliswell.dev)',
      '- Madde bir',
      '- [x] Yapıldı',
    ]);
  });

  it('merges consecutive code lines into one fenced block, renders embeds inline', () => {
    const markdown = deltaToMarkdown([
      { insert: 'const a = 1;' },
      { insert: '\n', attributes: { 'code-block': true } },
      { insert: 'const b = 2;' },
      { insert: '\n', attributes: { 'code-block': true } },
      // Since OPH-152 image embeds render as markdown images (they used to be
      // dropped) — attachment coverage lives in delta-embeds.test.js.
      { insert: { image: 'x.png' } },
      { insert: 'son satır\n' },
    ]);

    expect(markdown.split('\n')).toEqual([
      '```',
      'const a = 1;',
      'const b = 2;',
      '```',
      '![](x.png)son satır',
    ]);
  });

  it('renders blockquote, ordered/unchecked lists, strike and inline code', () => {
    const markdown = deltaToMarkdown([
      { insert: 'alıntı' },
      { insert: '\n', attributes: { blockquote: true } },
      { insert: 'birinci' },
      { insert: '\n', attributes: { list: 'ordered' } },
      { insert: 'bekliyor' },
      { insert: '\n', attributes: { list: 'unchecked' } },
      { insert: 'üstü çizili', attributes: { strike: true } },
      { insert: ' ve ' },
      { insert: 'kod', attributes: { code: true } },
      { insert: '\n' },
    ]);

    expect(markdown.split('\n')).toEqual([
      '> alıntı',
      '1. birinci',
      '- [ ] bekliyor',
      '~~üstü çizili~~ ve `kod`',
    ]);
  });

  it('empty and trailing-newline documents come out clean', () => {
    expect(deltaToMarkdown([])).toBe('');
    expect(deltaToMarkdown(null)).toBe('');
    expect(deltaToMarkdown([{ insert: 'tek satır\n' }])).toBe('tek satır');
  });
});

describe('GET /notes/:id/export (OPH-045)', () => {
  let app;
  let owner;

  beforeEach(async () => {
    ({ app } = await buildTestApp());
    owner = await registerUser(app, { email: 'owner@example.com' });
  });

  afterEach(async () => {
    await app.close();
  });

  const createNote = (payload) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
      headers: owner.headers,
      payload,
    });

  it('exports the stored markdown, titled', async () => {
    const created = await createNote({
      title: 'Gezi Planı',
      contentMarkdown: 'Rota ve **malzeme**',
    });
    expect(created.statusCode).toBe(201);

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${created.json().id}/export?format=md`,
      headers: owner.headers,
    });

    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toBe('text/markdown; charset=utf-8');
    // slugify drops the dotless ı (no NFKD decomposition) — "gezi-plan".
    expect(res.headers['content-disposition']).toBe('attachment; filename="gezi-plan.md"');
    // ADR-0033: the title lives in its own column and the STORED body never
    // repeats it, so a file that has to stand on its own gets its heading here.
    expect(res.body).toBe('# Gezi Planı\n\nRota ve **malzeme**');
  });

  it('converts a Delta body on the way in, so the export is already markdown', async () => {
    const created = await createNote({
      title: 'Eski istemci',
      contentDelta: [
        { insert: 'Deniz feneri' },
        { insert: '\n', attributes: { header: 1 } },
        { insert: 'Rota ve ' },
        { insert: 'malzeme', attributes: { bold: true } },
        { insert: '\n' },
      ],
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${created.json().id}/export?format=md`,
      headers: owner.headers,
    });

    expect(res.statusCode).toBe(200);
    expect(res.body).toBe('# Eski istemci\n\n# Deniz feneri\nRota ve **malzeme**');
  });

  it('titles an empty note and never returns a bare empty file', async () => {
    const bare = await createNote({ title: 'Boş' });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${bare.json().id}/export`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toBe('# Boş\n');
  });

  it('rejects unknown formats, foreign notes and missing notes', async () => {
    const created = await createNote({ title: 'Gizli' });
    const noteId = created.json().id;

    const badFormat = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${noteId}/export?format=pdf`,
      headers: owner.headers,
    });
    expect(badFormat.statusCode).toBe(400);

    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const forbidden = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${noteId}/export`,
      headers: outsider.headers,
    });
    expect(forbidden.statusCode).toBe(403);

    const missing = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${'0'.repeat(26)}/export`,
      headers: owner.headers,
    });
    expect(missing.statusCode).toBe(404);
    expect(missing.json().code).toBe('NOTE_NOT_FOUND');
  });
});
