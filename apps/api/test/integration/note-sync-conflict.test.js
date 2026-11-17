import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

/**
 * A note's own device never conflicts with itself (OPH-486, OPH-487,
 * ADR-0072).
 *
 * The 2026-11-18 report: a brand-new note said "edited on another device too"
 * while one person typed on one computer, and later half of it was missing.
 * Every case here was first reproduced against the old server and asserts the
 * fixed behaviour. Bodies are the Flutter client's real ones
 * (`SyncMutation.toJson`, `NoteStore.create/update`).
 */
const enabled = process.env.INTEGRATION === '1';
const emailPrefix = `notesync-${Date.now()}`;

describe.runIf(enabled)('note sync: own writes never conflict (OPH-486/487)', () => {
  let app;
  let owner;

  const wsRev = async () =>
    Number(
      (await app.db('workspaces').where({ id: owner.workspace.id }).first('revision')).revision,
    );
  const note = (id) => app.db('notes').where({ id }).first();
  const versions = async (id) =>
    app
      .db('note_versions')
      .where({ note_id: id })
      .orderBy('id', 'asc')
      .select('id', 'origin', 'client_id', 'note_revision', 'content_markdown');

  const push = async (clientId, mutations) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: owner.workspace.id,
        baseRevision: await wsRev(),
        mutations,
      },
    });
    expect(res.statusCode).toBe(200);
    return res.json().results;
  };

  const createM = (noteId, body = '', title = 'Yeni not') => ({
    clientMutationId: newId(),
    entityType: 'note',
    entityId: noteId,
    operation: 'create',
    localUpdatedAt: new Date().toISOString(),
    patch: { title, contentMarkdown: body, contentFormat: 'markdown' },
  });
  const updateM = (noteId, body, baseRevision, cmid = newId(), extra = {}) => ({
    clientMutationId: cmid,
    entityType: 'note',
    entityId: noteId,
    operation: 'update',
    localUpdatedAt: new Date().toISOString(),
    ...(baseRevision == null ? {} : { baseRevision }),
    patch: { title: 'Yeni not', contentMarkdown: body, contentFormat: 'markdown', ...extra },
  });
  const create = async (clientId, body) => {
    const noteId = newId();
    const [c] = await push(clientId, [createM(noteId, body)]);
    expect(c.status).toBe('applied');
    return { noteId, rev: c.revision };
  };
  const update = async (clientId, noteId, base, body, cmid) =>
    (await push(clientId, [updateM(noteId, body, base, cmid)]))[0];

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-6' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    owner = {
      user: body.user,
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

  describe('OPH-486: base 0 and own history', () => {
    it('an update with base 0 in the same batch as its create is applied, not BASE_MISSING', async () => {
      const pc = newId();
      const noteId = newId();
      const typed = 'Satır bir\nSatır iki';
      const results = await push(pc, [createM(noteId, ''), updateM(noteId, typed, 0)]);
      expect(results.map((r) => r.status)).toEqual(['applied', 'applied']);
      expect(results[1].conflictVersionId).toBeUndefined();
      expect((await note(noteId)).content_markdown).toBe(typed);
      expect((await versions(noteId)).map((v) => v.origin)).not.toContain('conflict');
    });

    it('an update with base 0 pushed after its create settled is applied', async () => {
      const pc = newId();
      const { noteId } = await create(pc, 'Merhaba');
      const u = await update(pc, noteId, 0, 'Merhaba\nDünya');
      expect(u.status).toBe('applied');
      expect((await note(noteId)).content_markdown).toBe('Merhaba\nDünya');
    });

    it('base 0 is still a conflict when ANOTHER writer reached the note first', async () => {
      const pc = newId();
      const web = newId();
      const { noteId, rev } = await create(pc, 'A\nM\nN');
      expect((await update(web, noteId, rev, 'A\nM\nWEB')).status).toBe('applied');
      const late = await update(pc, noteId, 0, 'A\nM\nPC');
      expect(late.status).toBe('conflict');
      expect((await note(noteId)).content_markdown).toBe('A\nM\nWEB');
    });

    it('base 0 after someone else only PINNED the note merges from the own create', async () => {
      const pc = newId();
      const web = newId();
      const { noteId } = await create(pc, 'Bir');
      const [pin] = await push(web, [
        {
          clientMutationId: newId(),
          entityType: 'note',
          entityId: noteId,
          operation: 'update',
          localUpdatedAt: new Date().toISOString(),
          patch: { isPinned: true },
        },
      ]);
      expect(pin.status).toBe('applied');
      const late = await update(pc, noteId, 0, 'Bir\nİki');
      expect(['applied', 'merged']).toContain(late.status);
      expect((await note(noteId)).content_markdown).toBe('Bir\nİki');
    });

    it('a base one of its OWN writes behind is applied (rolling head erased that version)', async () => {
      const pc = newId();
      const { noteId, rev: r0 } = await create(pc, '');
      const u1 = await update(pc, noteId, r0, 'Satır 1');
      const u2 = await update(pc, noteId, u1.revision, 'Satır 1\nSatır 2');
      expect([u1.status, u2.status]).toEqual(['applied', 'applied']);
      const u3 = await update(pc, noteId, u1.revision, 'Satır 1\nSatır 2\nSatır 3');
      expect(u3.status).toBe('applied');
      expect((await note(noteId)).content_markdown).toBe('Satır 1\nSatır 2\nSatır 3');
    });

    it('a pure append on a stale own base is applied, not OVERLAP', async () => {
      const pc = newId();
      const { noteId, rev: r0 } = await create(pc, 'Giriş');
      expect((await update(pc, noteId, r0, 'Giriş\nA')).status).toBe('applied');
      const u2 = await update(pc, noteId, r0, 'Giriş\nA\nB');
      expect(u2.status).toBe('applied');
      expect((await note(noteId)).content_markdown).toBe('Giriş\nA\nB');
    });

    it('a body identical to the server body is applied even on a stale foreign base', async () => {
      const pc = newId();
      const web = newId();
      const { noteId, rev: r0 } = await create(pc, 'Aynı');
      expect((await update(web, noteId, r0, 'Aynı metin')).status).toBe('applied');
      const same = await push(pc, [
        updateM(noteId, 'Aynı metin', r0, newId(), { title: 'Yeni başlık' }),
      ]);
      expect(same[0].status).toBe('applied');
      expect((await note(noteId)).title).toBe('Yeni başlık');
    });

    it('a write from ANOTHER client in the range still goes through the three-way merge', async () => {
      const pc = newId();
      const web = newId();
      const { noteId, rev: r0 } = await create(pc, 'A\nM\nN');
      expect((await update(web, noteId, r0, 'A\nM\nX')).status).toBe('applied');
      const mine = await update(pc, noteId, r0, 'A\nM\nY');
      expect(mine).toMatchObject({ status: 'conflict', reason: 'OVERLAP' });
      expect((await note(noteId)).content_markdown).toBe('A\nM\nX');
    });

    it('a REST write (no client id) in the range is foreign, never fast-forwarded', async () => {
      const pc = newId();
      const { noteId, rev: r0 } = await create(pc, 'A\nM\nN');
      const rest = await app.inject({
        method: 'PATCH',
        url: `/api/v1/notes/${noteId}`,
        headers: owner.headers,
        payload: { contentMarkdown: 'A\nM\nREST', contentFormat: 'markdown' },
      });
      expect(rest.statusCode).toBe(200);
      const mine = await update(pc, noteId, r0, 'A\nM\nPC');
      expect(mine.status).toBe('conflict');
      expect((await note(noteId)).content_markdown).toBe('A\nM\nREST');
    });

    it('a conflict row is never the merge base: a clean merge keeps every line', async () => {
      const pc = newId();
      const web = newId();
      const tablet = newId();
      const { noteId, rev: r0 } = await create(pc, 'A\nM\nN');
      const w = await update(web, noteId, r0, 'A\nM\nN\nW');
      expect(w.status).toBe('applied');
      // A refused body sharing note_revision with the real state.
      const c = await update(tablet, noteId, r0, 'A\nM\nQ');
      expect(c.status).toBe('conflict');
      const atW = (await versions(noteId)).filter((v) => Number(v.note_revision) === w.revision);
      expect(atW.map((v) => v.origin).sort()).toEqual(['conflict', 'edit']);
      // A third writer moves the note on, so the PC's base is stale.
      expect((await update(tablet, noteId, w.revision, 'A\nM\nN\nW\nV')).status).toBe('applied');
      const p = await update(pc, noteId, w.revision, 'P\nA\nM\nN\nW');
      expect(p.status).toBe('merged');
      expect((await note(noteId)).content_markdown).toBe('P\nA\nM\nN\nW\nV');
    });
  });

  describe('OPH-487: a reused clientMutationId', () => {
    it('a resend with the SAME payload still replays the first answer', async () => {
      const pc = newId();
      const { noteId, rev } = await create(pc, '');
      const cmid = newId();
      const m = updateM(noteId, 'Paragraf A', rev, cmid);
      const [first] = await push(pc, [m]);
      const [again] = await push(pc, [{ ...m, localUpdatedAt: new Date().toISOString() }]);
      expect(again).toMatchObject({ status: 'applied', revision: first.revision, replayed: true });
    });

    it('a resend with a NEWER body under an applied id is applied, never silently replayed', async () => {
      const pc = newId();
      const { noteId, rev } = await create(pc, '');
      const cmid = newId();
      const [u1] = await push(pc, [updateM(noteId, 'Paragraf A', rev, cmid)]);
      expect(u1.status).toBe('applied');
      const [u1again] = await push(pc, [updateM(noteId, 'Paragraf A\n\nParagraf B', rev, cmid)]);
      expect(u1again.replayed).toBe(false);
      expect(u1again.status).toBe('applied');
      expect(u1again.revision).toBeGreaterThan(u1.revision);
      expect((await note(noteId)).content_markdown).toBe('Paragraf A\n\nParagraf B');
      // …and THAT answer is what a later identical resend replays.
      const [third] = await push(pc, [updateM(noteId, 'Paragraf A\n\nParagraf B', rev, cmid)]);
      expect(third).toMatchObject({ replayed: true, revision: u1again.revision });
    });

    it('a resend with a newer body under a CONFLICTED id keeps that body in a version', async () => {
      const pc = newId();
      const web = newId();
      const { noteId, rev: r0 } = await create(pc, 'A\nM\nN');
      expect((await update(web, noteId, r0, 'A\nM\nX')).status).toBe('applied');
      const cmid = newId();
      const first = await update(pc, noteId, r0, 'A\nM\nY', cmid);
      expect(first.status).toBe('conflict');
      const again = await update(pc, noteId, r0, 'A\nM\nY ve devamı', cmid);
      expect(again.replayed).toBe(false);
      expect(again.status).toBe('conflict');
      expect(again.conflictVersionId).toEqual(expect.any(String));
      const kept = (await versions(noteId)).find((v) => v.id === again.conflictVersionId);
      expect(kept.content_markdown).toBe('A\nM\nY ve devamı');
    });
  });
});
