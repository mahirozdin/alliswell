import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';
import { isContentWrite, contentHash } from '../../src/db/note-versions.js';

/**
 * OPH-267 — note history (ADR-0031).
 *
 * The promises, in the order they would hurt if broken: every content write is
 * captured wherever it came from, a typing session is ONE row, an identical
 * body is no row, a pin is no row, restore does not rewrite history, and none
 * of this ever reaches the replica.
 */

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'versions@example.com' });
});

const ws = () => owner.workspace.id;

async function createNote(payload, headers = owner.headers) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ws()}/notes`,
    headers,
    payload,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

async function patchNote(id, payload, headers = owner.headers) {
  return app.inject({ method: 'PATCH', url: `/api/v1/notes/${id}`, headers, payload });
}

const versionsOf = (noteId) => tables.note_versions.filter((v) => v.note_id === noteId);

/** Pushes the newest version's clock back, so the coalescing window closes. */
function ageNewestVersion(noteId, minutes) {
  const rows = versionsOf(noteId);
  const newest = rows.at(-1);
  newest.created_at = new Date(Date.now() - minutes * 60000);
}

describe('what counts as content', () => {
  // Pinned directly, because the behavioural test below cannot see it: a
  // pin-only patch is ALSO caught by the hash check, so both layers would have
  // to break before a row appeared. Deliberately breaking `isContentWrite`
  // during review proved exactly that — the suite stayed green. Two defences
  // are good; a rule no test states is not.
  it('is the body and the title, and nothing else', () => {
    expect(isContentWrite({ title: 'x' })).toBe(true);
    expect(isContentWrite({ content_markdown: 'x' })).toBe(true);
    expect(isContentWrite({ content_delta: '[]' })).toBe(true);
    expect(isContentWrite({ content_format: 'markdown' })).toBe(true);

    expect(isContentWrite({ is_pinned: true })).toBe(false);
    expect(isContentWrite({ is_archived: true })).toBe(false);
    expect(isContentWrite({ project_id: 'x' })).toBe(false);
    expect(isContentWrite({})).toBe(false);
  });

  it('the hash covers the canonical format, not just the visible text', () => {
    const asDelta = {
      title: 'A',
      content_delta: '[{"insert":"body"}]',
      content_markdown: 'body',
      content_format: 'delta',
    };
    // Same fields, different canonical source: converting a note changes what
    // the note IS (ADR-0028 §1), so it is a new version.
    expect(contentHash(asDelta)).not.toBe(contentHash({ ...asDelta, content_format: 'markdown' }));
    expect(contentHash(asDelta)).toBe(contentHash({ ...asDelta }));
  });
});

describe('capture', () => {
  it('a new note is version one', async () => {
    const note = await createNote({ title: 'İlk hali', contentMarkdown: 'gövde' });
    const versions = versionsOf(note.id);
    expect(versions).toHaveLength(1);
    expect(versions[0].title).toBe('İlk hali');
    expect(versions[0].origin).toBe('create');
    expect(versions[0].content_hash).toMatch(/^[a-f0-9]{64}$/);
  });

  it('a typing session is ONE row, not one per autosave', async () => {
    const note = await createNote({ title: 'Yazılıyor', contentMarkdown: 'a' });
    // Six autosaves in quick succession, the 1.5 s debounce's real shape.
    for (const body of ['ab', 'abc', 'abcd', 'abcde', 'abcdef', 'abcdefg']) {
      await patchNote(note.id, { contentMarkdown: body, contentFormat: 'markdown' });
    }
    const versions = versionsOf(note.id);
    // One creation row + one rolling head — NOT seven.
    expect(versions).toHaveLength(2);
    expect(versions.at(-1).content_markdown).toBe('abcdefg');
  });

  it('a pause longer than the window starts a new row', async () => {
    const note = await createNote({ title: 'Ara verildi', contentMarkdown: 'a' });
    await patchNote(note.id, { contentMarkdown: 'ab', contentFormat: 'markdown' });
    expect(versionsOf(note.id)).toHaveLength(2);

    ageNewestVersion(note.id, 25); // longer than NOTE_VERSION_COALESCE_MIN
    await patchNote(note.id, { contentMarkdown: 'abc', contentFormat: 'markdown' });
    expect(versionsOf(note.id)).toHaveLength(3);
  });

  it('an identical body writes nothing at all', async () => {
    const note = await createNote({ title: 'Aynı', contentMarkdown: 'gövde' });
    await patchNote(note.id, { contentMarkdown: 'değişti', contentFormat: 'markdown' });
    const before = versionsOf(note.id).length;

    // The same content again — an autosave that fired after a cursor move.
    await patchNote(note.id, { contentMarkdown: 'değişti', contentFormat: 'markdown' });
    expect(versionsOf(note.id)).toHaveLength(before);
  });

  it('a pin or an archive is not content and burns no version', async () => {
    const note = await createNote({ title: 'Sabitlenecek' });
    const before = versionsOf(note.id).length;

    await patchNote(note.id, { isPinned: true });
    await patchNote(note.id, { isArchived: true });
    expect(versionsOf(note.id)).toHaveLength(before);
    // …and the flags really did change — the no-op is the VERSION, not the write.
    expect(Boolean(tables.notes.find((n) => n.id === note.id).is_pinned)).toBe(true);
  });

  it('every writer stamps its own origin', async () => {
    // REST with a session: birth, then a human edit.
    const typed = await createNote({ title: 'Elle' });
    expect(versionsOf(typed.id).at(-1).origin).toBe('create');
    await patchNote(typed.id, { contentMarkdown: 'yazıldı', contentFormat: 'markdown' });
    expect(versionsOf(typed.id).at(-1).origin).toBe('edit');

    // REST with an API key (OPH-264) — same route, different credential.
    const key = await app
      .inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws()}/api-keys`,
        headers: owner.headers,
        payload: { name: 'script' },
      })
      .then((r) => r.json());
    const viaKey = await createNote(
      { title: 'Script’ten' },
      { authorization: `Bearer ${key.key}` },
    );
    expect(versionsOf(viaKey.id).at(-1).origin).toBe('api');

    // Bulk import (OPH-266) — the ordering note said this line lands here.
    const imported = await app
      .inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws()}/import/notes`,
        headers: owner.headers,
        payload: { notes: [{ title: 'Aktarılmış', contentMarkdown: 'gövde' }] },
      })
      .then((r) => r.json());
    expect(versionsOf(imported.created[0]).at(-1).origin).toBe('import');
  });

  it('the offline path captures too — with the device that wrote it', async () => {
    const note = await createNote({ title: 'Telefondan' });
    const clientId = newId();
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: ws(),
        baseRevision: note.revision,
        mutations: [
          {
            clientMutationId: newId(),
            entityType: 'note',
            entityId: note.id,
            operation: 'update',
            patch: { contentMarkdown: 'çevrimdışı yazıldı', contentFormat: 'markdown' },
          },
        ],
      },
    });
    expect(res.statusCode).toBe(200);

    const newest = versionsOf(note.id).at(-1);
    expect(newest.content_markdown).toBe('çevrimdışı yazıldı');
    // The writer most likely to overwrite somebody is the one that must not
    // leave the history empty (ADR-0031 §2).
    expect(newest.client_id).toBe(clientId);
  });
});

describe('reading history', () => {
  it('the list is metadata; the body needs its own call', async () => {
    const note = await createNote({ title: 'Geçmişli', contentMarkdown: 'birinci' });
    ageNewestVersion(note.id, 25);
    await patchNote(note.id, { contentMarkdown: 'ikinci', contentFormat: 'markdown' });

    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}/versions`,
      headers: owner.headers,
    });
    expect(list.statusCode).toBe(200);
    const items = list.json().items;
    expect(items).toHaveLength(2);
    expect(items[0].sizeBytes).toBeGreaterThan(0);
    expect(items[0]).not.toHaveProperty('contentMarkdown');

    const detail = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}/versions/${items[0].id}`,
      headers: owner.headers,
    });
    expect(detail.json().contentMarkdown).toBeTruthy();
  });

  it('the diff is computed here, in word segments', async () => {
    const note = await createNote({
      title: 'Diff',
      contentMarkdown: 'kırmızı araba geldi',
      contentFormat: 'markdown',
    });
    const first = versionsOf(note.id).at(-1).id;
    ageNewestVersion(note.id, 25);
    await patchNote(note.id, { contentMarkdown: 'mavi araba geldi', contentFormat: 'markdown' });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}/versions/${first}/diff`,
      headers: owner.headers,
    });
    const segments = res.json().segments;
    expect(segments.some((s) => s.type === 'removed' && s.value.includes('kırmızı'))).toBe(true);
    expect(segments.some((s) => s.type === 'added' && s.value.includes('mavi'))).toBe(true);
    expect(segments.some((s) => s.type === 'equal' && s.value.includes('araba'))).toBe(true);
  });

  it('another account cannot read this note’s history', async () => {
    const note = await createNote({ title: 'Gizli' });
    const outsider = await registerUser(app, { email: 'versions-outsider@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}/versions`,
      headers: outsider.headers,
    });
    expect(res.statusCode).toBe(403);
  });
});

describe('restore', () => {
  it('replace makes a NEW head — history is added to, never rewritten', async () => {
    const note = await createNote({
      title: 'Geri alınacak',
      contentMarkdown: 'ilk gövde',
      contentFormat: 'markdown',
    });
    const firstVersion = versionsOf(note.id).at(-1).id;
    ageNewestVersion(note.id, 25);
    await patchNote(note.id, { contentMarkdown: 'yanlışlıkla silindi', contentFormat: 'markdown' });
    const beforeCount = versionsOf(note.id).length;

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/notes/${note.id}/versions/${firstVersion}/restore`,
      headers: owner.headers,
      payload: { mode: 'replace' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().contentMarkdown).toBe('ilk gövde');

    const versions = versionsOf(note.id);
    // A new row, stamped `restore` — and the version we restored FROM is still
    // there, as is the state we left (that is what "undoable in turn" means).
    expect(versions.length).toBe(beforeCount + 1);
    expect(versions.at(-1).origin).toBe('restore');
    expect(versions.some((v) => v.id === firstVersion)).toBe(true);
    expect(versions.some((v) => v.content_markdown === 'yanlışlıkla silindi')).toBe(true);
  });

  it('copy leaves the current note completely alone', async () => {
    const note = await createNote({
      title: 'Kopyalanacak',
      contentMarkdown: 'eski gövde',
      contentFormat: 'markdown',
    });
    const firstVersion = versionsOf(note.id).at(-1).id;
    ageNewestVersion(note.id, 25);
    await patchNote(note.id, { contentMarkdown: 'yeni gövde', contentFormat: 'markdown' });

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/notes/${note.id}/versions/${firstVersion}/restore`,
      headers: owner.headers,
      payload: { mode: 'copy' },
    });
    expect(res.statusCode).toBe(200);
    const copy = res.json();
    expect(copy.id).not.toBe(note.id);
    expect(copy.contentMarkdown).toBe('eski gövde');
    // The original still holds the newer body.
    expect(tables.notes.find((n) => n.id === note.id).content_markdown).toBe('yeni gövde');
  });
});

describe('retention (ADR-0031 §6)', () => {
  const day = 86400000;

  function seedVersion(noteId, { daysAgo, origin = 'edit' }) {
    const id = newId();
    tables.note_versions.push({
      id,
      workspace_id: owner.workspace.id,
      note_id: noteId,
      note_revision: 1,
      title: 'x',
      content_delta: null,
      content_markdown: `body-${id}`,
      content_format: 'markdown',
      origin,
      client_id: null,
      created_by: null,
      content_hash: id.toLowerCase().padEnd(64, '0'),
      created_at: new Date(Date.now() - daysAgo * day),
    });
    return id;
  }

  it('keeps the last week whole, thins the middle, deletes the old', async () => {
    const note = await createNote({ title: 'Saklama' });
    const noteId = note.id;
    // Three from yesterday: untouched (inside the fresh window).
    const fresh = [1, 1, 1].map(() => seedVersion(noteId, { daysAgo: 1 }));
    // Three from the same day, 30 days back: thinned to one.
    const middle = [30, 30, 30].map(() => seedVersion(noteId, { daysAgo: 30 }));
    // One from 200 days back: past retention.
    const ancient = seedVersion(noteId, { daysAgo: 200 });
    // …and a conflict row of the same age: protected for a year.
    const ancientProtected = seedVersion(noteId, { daysAgo: 200, origin: 'conflict' });

    const removed = await app.noteVersionGc.sweep();
    expect(removed).toBeGreaterThan(0);

    const kept = new Set(tables.note_versions.map((v) => v.id));
    for (const id of fresh) expect(kept.has(id)).toBe(true);
    expect(middle.filter((id) => kept.has(id))).toHaveLength(1);
    expect(kept.has(ancient)).toBe(false);
    expect(kept.has(ancientProtected)).toBe(true);
  });

  it('a very old protected row eventually goes too', async () => {
    const note = await createNote({ title: 'Yıllık' });
    const old = seedVersion(note.id, { daysAgo: 400, origin: 'merge' });
    await app.noteVersionGc.sweep();
    expect(tables.note_versions.some((v) => v.id === old)).toBe(false);
  });
});

describe('history stays on the server (ADR-0031 §1)', () => {
  it('is not a sync entity — a device cannot pull or push one', async () => {
    const note = await createNote({ title: 'Replikaya inmez' });
    expect(versionsOf(note.id).length).toBeGreaterThan(0);

    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ws()}&sinceRevision=0`,
      headers: owner.headers,
    });
    expect(pull.statusCode).toBe(200);
    expect(JSON.stringify(pull.json())).not.toContain('noteVersion');
    expect(JSON.stringify(pull.json())).not.toContain('note_version');

    const push = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId: newId(),
        workspaceId: ws(),
        baseRevision: 0,
        mutations: [
          {
            clientMutationId: newId(),
            entityType: 'noteVersion',
            entityId: newId(),
            operation: 'create',
            patch: { title: 'olmaz' },
          },
        ],
      },
    });
    // Rejected by the schema (400) or by the engine (a rejected result) — the
    // point is that no version row can be born on a device.
    const rejected =
      push.statusCode === 400 || push.json().results?.every((r) => r.status !== 'applied') === true;
    expect(rejected).toBe(true);
  });
});
