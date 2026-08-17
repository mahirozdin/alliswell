import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';
import { mergeMarkdown, normalizeText } from '../../src/lib/note-merge.js';

/**
 * OPH-268 — conflict correctness (findings #1/#2/#3).
 *
 * Scenario A, the one that started round 18: two clients editing one note
 * while a pull runs between them. It used to lose one of the two texts
 * silently. The contract now: **both texts survive** — merged when they do not
 * overlap, and otherwise refused with the losing body kept as a version.
 */

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'conflict@example.com' });
});

const ws = () => owner.workspace.id;

async function markdownNote(body) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ws()}/notes`,
    headers: owner.headers,
    payload: { title: 'Ortak not', contentFormat: 'markdown', contentMarkdown: body },
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

/** One client's offline write of a note body, carrying what it last saw. */
function push({ noteId, body, baseRevision, clientId = newId(), title }) {
  return app.inject({
    method: 'POST',
    url: '/api/v1/sync/push',
    headers: owner.headers,
    payload: {
      clientId,
      workspaceId: ws(),
      baseRevision: 0,
      mutations: [
        {
          clientMutationId: newId(),
          entityType: 'note',
          entityId: noteId,
          operation: 'update',
          baseRevision,
          patch: {
            ...(title ? { title } : {}),
            contentMarkdown: body,
            contentFormat: 'markdown',
          },
        },
      ],
    },
  });
}

const noteRow = (id) => tables.notes.find((n) => n.id === id);
const versionsOf = (id) => tables.note_versions.filter((v) => v.note_id === id);

describe('the merge engine itself', () => {
  it('merges edits that do not touch each other', () => {
    const base = 'satır bir\nsatır iki\nsatır üç';
    const ours = 'satır bir DEĞİŞTİ\nsatır iki\nsatır üç';
    const theirs = 'satır bir\nsatır iki\nsatır üç EKLENDİ';
    const merged = mergeMarkdown(base, ours, theirs);
    expect(merged.ok).toBe(true);
    expect(merged.text).toContain('DEĞİŞTİ');
    expect(merged.text).toContain('EKLENDİ');
  });

  it('refines by WORD inside one paragraph — markdown’s single-line trap', () => {
    // One line, two people, opposite ends. Line-level diff3 calls this a
    // conflict; the diff3 paper says its guarantees need "well-separated"
    // regions, and a markdown paragraph is one line.
    const base = 'Toplantı salı günü ofiste yapılacak';
    const ours = 'Toplantı çarşamba günü ofiste yapılacak';
    const theirs = 'Toplantı salı günü evde yapılacak';
    const merged = mergeMarkdown(base, ours, theirs);
    expect(merged.ok).toBe(true);
    expect(merged.refined).toBe(true);
    expect(merged.text).toBe('Toplantı çarşamba günü evde yapılacak');
  });

  it('refuses when the two sides changed the same words', () => {
    const base = 'Toplantı salı günü';
    const merged = mergeMarkdown(base, 'Toplantı çarşamba günü', 'Toplantı perşembe günü');
    expect(merged.ok).toBe(false);
    expect(merged.reason).toBe('OVERLAP');
  });

  it('one line ending, whatever the platform sent', () => {
    expect(normalizeText('a\r\nb\rc')).toBe('a\nb\nc');
    const merged = mergeMarkdown('a\nb', 'a\r\nb DEĞİŞTİ', 'a\nb');
    expect(merged.ok).toBe(true);
  });
});

describe('scenario A — two clients, one note', () => {
  it('both texts survive: the second write MERGES instead of overwriting', async () => {
    const note = await markdownNote('birinci satır\nikinci satır\nüçüncü satır');
    const base = note.revision;

    // Client A writes first and wins the race normally.
    const first = await push({
      noteId: note.id,
      body: 'birinci satır A TARAFI\nikinci satır\nüçüncü satır',
      baseRevision: base,
      clientId: newId(),
    });
    expect(first.json().results[0].status).toBe('applied');

    // Client B was editing the SAME base and knows nothing about A. This is
    // the write that used to silently delete A's line.
    const second = await push({
      noteId: note.id,
      body: 'birinci satır\nikinci satır\nüçüncü satır B TARAFI',
      baseRevision: base,
      clientId: newId(),
    });
    const result = second.json().results[0];
    expect(result.status).toBe('merged');
    expect(result.merged.contentMarkdown).toContain('A TARAFI');
    expect(result.merged.contentMarkdown).toContain('B TARAFI');

    // …and the stored note holds both, with a version stamped `merge`.
    const stored = noteRow(note.id);
    expect(stored.content_markdown).toContain('A TARAFI');
    expect(stored.content_markdown).toContain('B TARAFI');
    expect(versionsOf(note.id).at(-1).origin).toBe('merge');
    // The search column followed the merged body (OPH-261's repair).
    expect(stored.plain_text).toContain('B TARAFI');
  });

  it('a real overlap is refused — and the refused body is KEPT', async () => {
    const note = await markdownNote('teslim tarihi salı');
    const base = note.revision;

    await push({ noteId: note.id, body: 'teslim tarihi çarşamba', baseRevision: base });
    const second = await push({
      noteId: note.id,
      body: 'teslim tarihi perşembe',
      baseRevision: base,
    });

    const result = second.json().results[0];
    expect(result.status).toBe('conflict');
    expect(result.errorCode).toBe('NOTE_CONTENT_CONFLICT');
    expect(result.conflictVersionId).toBeTruthy();

    // The note keeps the first writer's body…
    expect(noteRow(note.id).content_markdown).toBe('teslim tarihi çarşamba');
    // …and the SECOND writer's text is not gone. That sentence is the whole
    // point of the epic: nothing is lost, and the id says where it is.
    const kept = tables.note_versions.find((v) => v.id === result.conflictVersionId);
    expect(kept.origin).toBe('conflict');
    expect(kept.content_markdown).toBe('teslim tarihi perşembe');
  });

  it('two autosaves in a row do NOT produce a fake conflict', async () => {
    const note = await markdownNote('yazmaya başladım');
    const clientId = newId();

    const first = await push({
      noteId: note.id,
      body: 'yazmaya başladım biraz daha',
      baseRevision: note.revision,
      clientId,
    });
    expect(first.json().results[0].status).toBe('applied');
    // The client advances its base with its OWN result revision — exactly what
    // the app does — and the next autosave must be an ordinary write.
    const advanced = first.json().results[0].revision;

    const second = await push({
      noteId: note.id,
      body: 'yazmaya başladım biraz daha ve daha',
      baseRevision: advanced,
      clientId,
    });
    expect(second.json().results[0].status).toBe('applied');
  });
});

describe('when merging is not honest, it does not happen', () => {
  it('a note born from a Delta now MERGES — the NOT_MARKDOWN refusal is gone', async () => {
    // Until ADR-0033 this was the common case and it could never merge: a
    // Delta is a JSON op array, so `threeWayNoteWrite` refused with
    // NOT_MARKDOWN and every conflict between two rich-text notes went to the
    // banner. Epic 25 built the merge engine and this is what kept it from
    // running. One canonical form later, the same push merges.
    const note = await app
      .inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws()}/notes`,
        headers: owner.headers,
        payload: {
          title: 'Eskiden zengin metin',
          contentDelta: [{ insert: 'ilk satır\nikinci satır\nüçüncü satır\n' }],
        },
      })
      .then((r) => r.json());
    const base = note.revision;
    expect(note.contentFormat).toBe('markdown');

    // The other device rewrites the FIRST line.
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: { contentMarkdown: 'sunucu satırı\nikinci satır\nüçüncü satır' },
    });

    // This one rewrites the THIRD, from the same base. Disjoint regions.
    const res = await push({
      noteId: note.id,
      body: 'ilk satır\nikinci satır\nistemci satırı',
      baseRevision: base,
    });
    const result = res.json().results[0];
    expect(result.status).toBe('merged');
    expect(result.merged.contentMarkdown).toContain('sunucu satırı');
    expect(result.merged.contentMarkdown).toContain('istemci satırı');
  });

  it('a base that retention already swept is an honest conflict', async () => {
    const note = await markdownNote('uzun süredir çevrimdışı');
    const base = note.revision;
    await push({ noteId: note.id, body: 'sunucuda değişti', baseRevision: base });

    // The device comes back after the base version was thinned away.
    tables.note_versions = tables.note_versions.filter((v) => v.note_revision !== base);

    const res = await push({
      noteId: note.id,
      body: 'telefonda yazdıklarım',
      baseRevision: base,
    });
    const result = res.json().results[0];
    expect(result.status).toBe('conflict');
    expect(result.reason).toBe('BASE_MISSING');
    // Still kept. A conflict is never a reason to drop somebody's text.
    expect(
      tables.note_versions.find((v) => v.id === result.conflictVersionId).content_markdown,
    ).toBe('telefonda yazdıklarım');
  });

  it('an old client that sends no base behaves exactly as before', async () => {
    const note = await markdownNote('eski istemci');
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: { contentMarkdown: 'sunucuda değişti', contentFormat: 'markdown' },
    });

    // No `baseRevision` on the mutation — the pre-OPH-268 protocol.
    const res = await app.inject({
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
            entityType: 'note',
            entityId: note.id,
            operation: 'update',
            patch: { contentMarkdown: 'eski istemciden', contentFormat: 'markdown' },
          },
        ],
      },
    });
    // Today's behaviour: the document-level lock refuses it. A protocol that
    // breaks its own old clients is not a protocol.
    expect(res.json().results[0].status).toBe('conflict');
    expect(res.json().results[0].errorCode).toBe('NOTE_CONTENT_CONFLICT');
  });
});

describe('REST clients get the same treatment', () => {
  it('PATCH with a base merges, and without one keeps working', async () => {
    const note = await markdownNote('alfa\nbeta\ngama');
    const base = note.revision;
    await push({ noteId: note.id, body: 'alfa DEĞİŞTİ\nbeta\ngama', baseRevision: base });

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: {
        contentMarkdown: 'alfa\nbeta\ngama EKLENDİ',
        contentFormat: 'markdown',
        baseRevision: base,
      },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().contentMarkdown).toContain('DEĞİŞTİ');
    expect(res.json().contentMarkdown).toContain('EKLENDİ');
    expect(versionsOf(note.id).at(-1).origin).toBe('merge');
  });

  it('PATCH with an overlapping base answers 409, body kept', async () => {
    const note = await markdownNote('tek satır salı');
    const base = note.revision;
    await push({ noteId: note.id, body: 'tek satır çarşamba', baseRevision: base });

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
      payload: {
        contentMarkdown: 'tek satır perşembe',
        contentFormat: 'markdown',
        baseRevision: base,
      },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('NOTE_CONTENT_CONFLICT');
    expect(
      tables.note_versions.some(
        (v) => v.origin === 'conflict' && v.content_markdown === 'tek satır perşembe',
      ),
    ).toBe(true);
  });
});
