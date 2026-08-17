import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { deltaToPlainText, isValidDelta } from '../../src/lib/delta.js';

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

const DELTA = [
  { insert: 'Deniz feneri gezisi' },
  { insert: '\n', attributes: { header: 1 } },
  { insert: 'Rota ve ' },
  { insert: 'malzeme listesi', attributes: { bold: true } },
  { insert: '\n' },
];

const createNote = (payload, headers = owner.headers) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
    headers,
    payload,
  });

const listNotes = (qs = '', headers = owner.headers) =>
  app.inject({
    method: 'GET',
    url: `/api/v1/workspaces/${owner.workspace.id}/notes${qs}`,
    headers,
  });

describe('lib/delta (OPH-040)', () => {
  it('extracts and normalizes plain text, skipping embeds', () => {
    expect(deltaToPlainText(DELTA)).toBe('Deniz feneri gezisi Rota ve malzeme listesi');
    expect(deltaToPlainText([{ insert: { image: 'x.png' } }, { insert: 'alt' }])).toBe('alt');
    expect(deltaToPlainText(null)).toBe('');
  });

  it('validates ops arrays structurally', () => {
    expect(isValidDelta(DELTA)).toBe(true);
    expect(isValidDelta([{ insert: 42 }])).toBe(false);
    expect(isValidDelta('not-an-array')).toBe(false);
    expect(isValidDelta([{ notInsert: 'x' }])).toBe(false);
  });
});

describe('note CRUD (OPH-040)', () => {
  it('creates a note, derives plain text and logs the sync revision', async () => {
    const res = await createNote({
      title: 'Gezi planı',
      contentDelta: DELTA,
      contentMarkdown: '# Deniz feneri gezisi\nRota ve **malzeme listesi**',
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body).toMatchObject({
      title: 'Gezi planı',
      isPinned: false,
      isArchived: false,
      revision: 1,
      plainText: 'Deniz feneri gezisi Rota ve malzeme listesi',
      links: [],
    });
    // ADR-0033: the response never carries a Delta again. This body sent BOTH
    // fields, the way a pre-2026-08-18 client does, and the markdown is the one
    // that survived.
    expect(body.contentDelta).toBeNull();
    expect(body.contentMarkdown).toBe('# Deniz feneri gezisi\nRota ve **malzeme listesi**');
    expect(tables.sync_revisions.at(-1)).toMatchObject({
      entity_type: 'note',
      operation: 'create',
    });
  });

  it('rejects malformed deltas and foreign projects', async () => {
    const badDelta = await createNote({ title: 'X', contentDelta: [{ bad: true }] });
    expect(badDelta.statusCode).toBe(400);
    expect(badDelta.json()).toMatchObject({ code: 'NOTE_INVALID_DELTA' });

    const foreign = await registerUser(app, { email: 'foreign@example.com' });
    const theirProject = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${foreign.workspace.id}/projects`,
        headers: foreign.headers,
        payload: { name: 'Theirs' },
      })
    ).json();
    const badProject = await createNote({ title: 'X', projectId: theirProject.id });
    expect(badProject.statusCode).toBe(400);
    expect(badProject.json()).toMatchObject({ code: 'NOTE_INVALID_PROJECT' });
  });

  it('patches content (plain text follows), pin and archive flags', async () => {
    const note = (await createNote({ title: 'Evrilen', contentDelta: DELTA })).json();

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: {
        contentDelta: [{ insert: 'Yepyeni içerik\n' }],
        isPinned: true,
      },
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json()).toMatchObject({
      plainText: 'Yepyeni içerik',
      isPinned: true,
      revision: 2,
    });

    const archived = await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: { isArchived: true },
    });
    expect(archived.json().isArchived).toBe(true);
  });

  it('lists newest-first, hides archived by default, filters pinned and archived', async () => {
    await createNote({ title: 'Normal not' });
    const pinned = (await createNote({ title: 'Sabit not', isPinned: true })).json();
    const arch = (await createNote({ title: 'Arşivlik' })).json();
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${arch.id}`,
      headers: owner.headers,
      payload: { isArchived: true },
    });

    const all = (await listNotes()).json();
    expect(all.items.map((n) => n.title)).toEqual(['Sabit not', 'Normal not']);

    const onlyPinned = (await listNotes('?pinned=true')).json();
    expect(onlyPinned.items.map((n) => n.id)).toEqual([pinned.id]);

    const withArchived = (await listNotes('?includeArchived=true')).json();
    expect(withArchived.items).toHaveLength(3);

    // The archive view: ONLY archived notes.
    const onlyArchived = (await listNotes('?archived=true')).json();
    expect(onlyArchived.items.map((n) => n.id)).toEqual([arch.id]);
    const unarchived = (await listNotes('?archived=false')).json();
    expect(unarchived.items).toHaveLength(2);
  });

  it('excludes README notes by default, lists only them with readme=true (OPH-109)', async () => {
    await createNote({ title: 'Sıradan not' });
    const readme = (await createNote({ title: 'Proje README' })).json();
    const project = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
        headers: owner.headers,
        payload: { name: 'Dokümanlı proje' },
      })
    ).json();
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
      payload: { readmeNoteId: readme.id },
    });

    // Default: the README is hidden (it lives in the project Overview).
    const normal = (await listNotes()).json();
    expect(normal.items.map((n) => n.title)).toEqual(['Sıradan not']);

    // readme=true: ONLY README notes.
    const onlyReadmes = (await listNotes('?readme=true')).json();
    expect(onlyReadmes.items.map((n) => n.id)).toEqual([readme.id]);
  });

  it('searches title + plain text via q', async () => {
    await createNote({ title: 'Alışveriş', contentDelta: [{ insert: 'süt ve yumurta\n' }] });
    await createNote({ title: 'Deniz feneri', contentDelta: [{ insert: 'rota planı\n' }] });

    const byBody = (await listNotes('?q=yumurta')).json();
    expect(byBody.items.map((n) => n.title)).toEqual(['Alışveriş']);

    const byTitle = (await listNotes('?q=feneri')).json();
    expect(byTitle.items.map((n) => n.title)).toEqual(['Deniz feneri']);
  });

  it('soft-deletes and 404s afterwards; authz on every route', async () => {
    const note = (await createNote({ title: 'Silinecek' })).json();
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    expect(tables.notes[0].deleted_at).toBeTruthy();
    expect(
      (
        await app.inject({
          method: 'GET',
          url: `/api/v1/notes/${note.id}`,
          headers: owner.headers,
        })
      ).statusCode,
    ).toBe(404);

    const stranger = await registerUser(app, { email: 'stranger@example.com' });
    const kept = (await createNote({ title: 'Korunan' })).json();
    for (const res of await Promise.all([
      listNotes('', stranger.headers),
      createNote({ title: 'Sızma' }, stranger.headers),
      app.inject({
        method: 'GET',
        url: `/api/v1/notes/${kept.id}`,
        headers: stranger.headers,
      }),
      app.inject({
        method: 'PATCH',
        url: `/api/v1/notes/${kept.id}`,
        headers: stranger.headers,
        payload: { title: 'Hijack' },
      }),
      app.inject({
        method: 'DELETE',
        url: `/api/v1/notes/${kept.id}`,
        headers: stranger.headers,
      }),
    ])) {
      expect(res.statusCode).toBe(403);
    }
  });
});

describe('content_format — markdown is the only canonical field (OPH-274, ADR-0033)', () => {
  it('lands as markdown even when the body arrives as a Delta', async () => {
    const res = await createNote({ title: 'Eski istemci', contentDelta: DELTA });

    expect(res.statusCode).toBe(201);
    // ADR-0028's split is over. A Delta is still ACCEPTED — the phone in
    // someone's pocket keeps sending one for weeks after we deploy — but it is
    // converted on the way in, and the note that results is a markdown note.
    expect(res.json()).toMatchObject({
      contentFormat: 'markdown',
      contentDelta: null,
      contentMarkdown: '# Deniz feneri gezisi\nRota ve **malzeme listesi**',
    });
  });

  it('never stores the Delta it converted', async () => {
    const res = await createNote({ title: 'Eski istemci', contentDelta: DELTA });

    // The column keeps its pre-migration rows as a lossless escape hatch, but
    // nothing writes to it again — otherwise the database would hold two
    // bodies for one note, and only one of them would be maintained.
    expect(tables.notes.find((n) => n.id === res.json().id).content_delta).toBeNull();
  });

  it('does not duplicate the title when a v1.6.0 client saves', async () => {
    // The shape the previous release actually sends on every autosave
    // (`note_document.dart` `bodyFor`): all three fields, and a markdown that
    // it prefixed with the title because its own Reading view needed one.
    // Storing that verbatim would make every migrated note render its title
    // twice — once from the column, once as an H1.
    const res = await createNote({
      title: 'Gezi planı',
      contentDelta: DELTA,
      contentMarkdown: '# Gezi planı\n\n# Deniz feneri gezisi\nRota ve **malzeme listesi**',
      contentFormat: 'delta',
    });

    expect(res.statusCode).toBe(201);
    // The Delta is re-derived rather than trusted, so the prefix never enters.
    expect(res.json().contentMarkdown).toBe('# Deniz feneri gezisi\nRota ve **malzeme listesi**');
  });

  it('strips a matching title heading when there is no Delta to re-derive', async () => {
    const res = await createNote({
      title: 'Gezi planı',
      contentMarkdown: '# Gezi planı\n\ngövde',
      contentFormat: 'delta',
    });

    expect(res.json().contentMarkdown).toBe('gövde');
  });

  it('keeps a heading the author actually wrote', async () => {
    // The same first line, from a markdown-canonical write. This one was
    // typed, so stripping it would be editing somebody's document.
    const res = await createNote({
      title: 'Gezi planı',
      contentMarkdown: '# Gezi planı\n\ngövde',
      contentFormat: 'markdown',
    });

    expect(res.json().contentMarkdown).toBe('# Gezi planı\n\ngövde');
  });

  it('can be set at creation for a document that came from a file', async () => {
    const res = await createNote({
      title: 'README',
      contentMarkdown: '# README\n\nmetin',
      contentFormat: 'markdown',
    });

    expect(res.statusCode).toBe(201);
    expect(res.json().contentFormat).toBe('markdown');
  });

  it('survives a round trip through GET', async () => {
    const created = await createNote({
      title: 'Belge',
      contentMarkdown: '# Belge',
      contentFormat: 'markdown',
    });
    const id = created.json().id;

    const fetched = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${id}`,
      headers: owner.headers,
    });

    expect(fetched.json().contentFormat).toBe('markdown');
  });

  it('is patchable — the conversion door DESIGN §29 describes', async () => {
    const created = await createNote({ title: 'Not', contentDelta: DELTA });

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${created.json().id}`,
      headers: owner.headers,
      payload: { contentFormat: 'markdown', contentMarkdown: '# Not' },
    });

    expect(patched.statusCode).toBe(200);
    expect(patched.json().contentFormat).toBe('markdown');
  });

  it('refuses a value nobody has heard of', async () => {
    // A third format would silently decide how somebody's note is edited, so
    // the Ajv enum and the table's CHECK constraint both say no.
    const res = await createNote({
      title: 'Not',
      contentDelta: DELTA,
      contentFormat: 'yaml',
    });

    expect(res.statusCode).toBe(400);
  });
});
