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
    expect(body.contentDelta).toEqual(DELTA);
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
