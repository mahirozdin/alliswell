import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-268 over real MySQL: Scenario A, verbatim.
 *
 * The finding this epic closed was not "there is no lock" — it was WHICH
 * revision the lock compared. The optimistic lock compared the workspace pull
 * cursor, so a socket-driven pull that moved that cursor past the other
 * device's write made the lock conclude "nothing foreign happened" and one
 * body silently replaced another.
 *
 * Every test here therefore pushes with a FRESH top-level `baseRevision` (the
 * workspace cursor, already past the other client's write — exactly what the
 * socket pull produces) and a STALE mutation-level `baseRevision` (the note
 * revision the editor actually saw). Under the old code the cursor check found
 * nothing foreign and applied the write whole. An absent `discardedFields` is
 * asserted for that reason: it proves the cursor lock discarded nothing, so it
 * is not what is saving these bodies — the three-way merge is.
 */
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph268-${Date.now()}`;
const PASSWORD = 'integration-pw-268';

describe.runIf(enabled)('integration: note three-way merge (OPH-268, Scenario A)', () => {
  let app;
  let owner;

  /** The workspace's current revision — what a client's pull cursor holds. */
  const workspaceRevision = async () =>
    Number(
      (await app.db('workspaces').where({ id: owner.workspace.id }).first('revision')).revision,
    );

  /** A note's own revision — what the editor saw (the base OPH-268 introduced). */
  const noteRevision = async (noteId) =>
    Number((await app.db('notes').where({ id: noteId }).first('revision')).revision);

  const push = (clientId, cursor, mutation) =>
    app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: owner.workspace.id,
        baseRevision: cursor,
        mutations: [{ clientMutationId: newId(), ...mutation }],
      },
    });

  /** Creates a markdown note and returns its id + the revision it was born at. */
  async function createMarkdownNote(clientId, contentMarkdown, title = 'Toplantı notları') {
    const noteId = newId();
    const res = await push(clientId, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'create',
      patch: { title, contentMarkdown, contentFormat: 'markdown' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().results[0].status).toBe('applied');
    return { noteId, base: await noteRevision(noteId) };
  }

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: PASSWORD },
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

  it('Scenario A: a socket pull moves the cursor past the other write and BOTH texts live', async () => {
    const clientA = newId();
    const clientB = newId();
    const { noteId, base } = await createMarkdownNote(
      clientA,
      '# Toplantı notları\n\nGündem: bütçe\nKatılımcılar: Ayşe\n',
    );

    // Client A edits the agenda line. Ordinary write — its base is current.
    const aRes = await push(clientA, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: '# Toplantı notları\n\nGündem: bütçe ve işe alım\nKatılımcılar: Ayşe\n',
        contentFormat: 'markdown',
      },
    });
    expect(aRes.json().results[0].status).toBe('applied');
    expect(await noteRevision(noteId)).toBeGreaterThan(base);

    // ── The socket pull. This is the step that used to disarm the lock. ──────
    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=${base}&limit=200`,
      headers: owner.headers,
    });
    expect(pull.statusCode).toBe(200);
    const cursorPastA = pull.json().toRevision;
    expect(cursorPastA).toBeGreaterThanOrEqual(await noteRevision(noteId));

    // Client B pushes with that fresh cursor but the STALE note base it was
    // editing. Old code: "nothing foreign since the cursor" → overwrite.
    const bRes = await push(clientB, cursorPastA, {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: '# Toplantı notları\n\nGündem: bütçe\nKatılımcılar: Ayşe, Mehmet\n',
        contentFormat: 'markdown',
      },
    });
    expect(bRes.statusCode).toBe(200);
    const result = bRes.json().results[0];

    expect(result.status).toBe('merged');
    // The cursor-based lock protected nothing here — it saw no foreign change,
    // so it discarded no field (the key is omitted when the list is empty).
    expect(result.discardedFields).toBeUndefined();

    const row = await app.db('notes').where({ id: noteId }).first();
    expect(row.content_markdown).toContain('bütçe ve işe alım'); // A survived
    expect(row.content_markdown).toContain('Ayşe, Mehmet'); // B survived
    expect(row.content_format).toBe('markdown');
    // The merged body is echoed back so the client adopts it without a refetch.
    expect(result.merged.contentMarkdown).toBe(row.content_markdown);

    // A merge is a moment somebody may point at: it never coalesces away.
    const versions = await app
      .db('note_versions')
      .where({ note_id: noteId })
      .orderBy('created_at', 'asc')
      .select('origin');
    expect(versions.map((v) => v.origin)).toEqual(['create', 'edit', 'merge']);
  });

  it('word level: two people editing opposite ends of ONE markdown paragraph merge', async () => {
    const clientA = newId();
    const clientB = newId();
    // A markdown paragraph is a single long line, so a line-level diff3 would
    // call this a conflict when nothing actually overlaps.
    const { noteId, base } = await createMarkdownNote(clientA, 'Toplantı salı ofiste yapılacak.\n');

    await push(clientA, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: 'Toplantı çarşamba ofiste yapılacak.\n',
        contentFormat: 'markdown',
      },
    });

    const bRes = await push(clientB, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: 'Toplantı salı fabrikada yapılacak.\n',
        contentFormat: 'markdown',
      },
    });

    expect(bRes.json().results[0].status).toBe('merged');
    const row = await app.db('notes').where({ id: noteId }).first();
    expect(row.content_markdown.trim()).toBe('Toplantı çarşamba fabrikada yapılacak.');
  });

  it('a genuine overlap is refused — and the REFUSED body is kept, with an id pointing at it', async () => {
    const clientA = newId();
    const clientB = newId();
    const { noteId, base } = await createMarkdownNote(clientA, 'Toplantı salı ofiste yapılacak.\n');

    await push(clientA, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: 'Toplantı pazartesi ofiste yapılacak.\n',
        contentFormat: 'markdown',
      },
    });
    const afterA = await app.db('notes').where({ id: noteId }).first();

    // Both rewrote the SAME word. No merge can honestly pick one.
    const bRes = await push(clientB, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: { contentMarkdown: 'Toplantı cuma ofiste yapılacak.\n', contentFormat: 'markdown' },
    });

    const result = bRes.json().results[0];
    expect(result.status).toBe('conflict');
    expect(result.errorCode).toBe('NOTE_CONTENT_CONFLICT');
    expect(result.reason).toBe('OVERLAP');
    expect(result.conflictVersionId).toBeTruthy();

    // The server's body is untouched by a refusal.
    const row = await app.db('notes').where({ id: noteId }).first();
    expect(row.content_markdown).toBe(afterA.content_markdown);

    // "The overwritten body is in no table" is the sentence this epic killed.
    const kept = await app.db('note_versions').where({ id: result.conflictVersionId }).first();
    expect(kept.origin).toBe('conflict');
    expect(kept.content_markdown).toBe('Toplantı cuma ofiste yapılacak.\n');
    expect(kept.content_format).toBe('markdown');
    expect(kept.note_id).toBe(noteId);
  });

  it('offline reconnect: a stale base still merges as long as the base body survives', async () => {
    const clientA = newId();
    const offline = newId();
    const { noteId, base } = await createMarkdownNote(
      clientA,
      '# Alışveriş\n\n- süt\n- ekmek\n- yumurta\n',
    );

    // Three writes land while the other device is in airplane mode. They are
    // separate clients so none of them coalesces the base row away.
    for (const [i, line] of ['- peynir', '- zeytin', '- çay'].entries()) {
      const current = await app.db('notes').where({ id: noteId }).first();
      const res = await push(newId(), await workspaceRevision(), {
        entityType: 'note',
        entityId: noteId,
        operation: 'update',
        baseRevision: await noteRevision(noteId),
        patch: {
          contentMarkdown: `${current.content_markdown}${line}\n`,
          contentFormat: 'markdown',
        },
      });
      expect(res.json().results[0].status, `write ${i}`).toBe('applied');
    }

    // The offline device reconnects and pushes what it wrote against the base
    // it left with. It retitled the list — a region nobody else touched, three
    // writes and an airplane-mode gap later.
    const res = await push(offline, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: '# Market listesi\n\n- süt\n- ekmek\n- yumurta\n',
        contentFormat: 'markdown',
      },
    });

    expect(res.json().results[0].status).toBe('merged');
    const row = await app.db('notes').where({ id: noteId }).first();
    expect(row.content_markdown).toContain('# Market listesi'); // the offline edit
    for (const item of ['süt', 'ekmek', 'yumurta', 'peynir', 'zeytin', 'çay']) {
      expect(row.content_markdown, `${item} survived`).toContain(item);
    }
  });

  it('two devices appending to the SAME list end genuinely conflict — and say so', async () => {
    const clientA = newId();
    const clientB = newId();
    const { noteId, base } = await createMarkdownNote(clientA, '# Alışveriş\n\n- süt\n- ekmek\n');

    await push(clientA, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: '# Alışveriş\n\n- süt\n- ekmek\n- peynir\n',
        contentFormat: 'markdown',
      },
    });

    // Both appended a DIFFERENT item at the same insertion point. No merge can
    // know the intended order, so the honest answer is a conflict — this is a
    // documented boundary of the feature, not a defect.
    const res = await push(clientB, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentMarkdown: '# Alışveriş\n\n- süt\n- ekmek\n- bal\n',
        contentFormat: 'markdown',
      },
    });

    const result = res.json().results[0];
    expect(result.status).toBe('conflict');
    expect(result.reason).toBe('OVERLAP');
    const kept = await app.db('note_versions').where({ id: result.conflictVersionId }).first();
    expect(kept.content_markdown).toContain('- bal');
  });

  it('a base whose version retention removed it is an honest conflict, not a guess', async () => {
    const clientA = newId();
    const clientB = newId();
    const { noteId, base } = await createMarkdownNote(clientA, 'Birinci hâli.\n');

    await push(clientA, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: { contentMarkdown: 'İkinci hâli.\n', contentFormat: 'markdown' },
    });

    // Retention thinned the base away — a device offline for months.
    await app.db('note_versions').where({ note_id: noteId, note_revision: base }).delete();

    const res = await push(clientB, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: { contentMarkdown: 'Üçüncü hâli.\n', contentFormat: 'markdown' },
    });

    const result = res.json().results[0];
    expect(result.status).toBe('conflict');
    expect(result.reason).toBe('BASE_MISSING');
    // Even with no base to merge against, the refused body is not lost.
    const kept = await app.db('note_versions').where({ id: result.conflictVersionId }).first();
    expect(kept.content_markdown).toBe('Üçüncü hâli.\n');
    expect(kept.origin).toBe('conflict');
  });

  it('OPH-274: a device still sending Deltas merges instead of conflicting', async () => {
    // The gap ADR-0033 closed, over real MySQL. Under ADR-0028 this push
    // answered NOT_MARKDOWN — a Delta is a JSON op array, so the merge engine
    // Epic 25 built refused to run on the app's OWN notes, which is every note
    // anybody had. The base is read back out of `note_versions` inside the
    // request, so the migration having converted history is part of what this
    // proves; a unit test with a fake table cannot.
    const clientA = newId();
    const clientB = newId();
    const { noteId, base } = await createMarkdownNote(
      clientA,
      'birinci satır\nikinci satır\nüçüncü satır\n',
      'Delta gönderen cihaz',
    );

    await push(clientA, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: { contentMarkdown: 'SUNUCU satırı\nikinci satır\nüçüncü satır\n' },
    });

    // The old client's shape, verbatim: ops, a derived markdown carrying the
    // title heading, and contentFormat 'delta'.
    const res = await push(clientB, await workspaceRevision(), {
      entityType: 'note',
      entityId: noteId,
      operation: 'update',
      baseRevision: base,
      patch: {
        contentDelta: [{ insert: 'birinci satır\nikinci satır\nESKİ İSTEMCİ satırı\n' }],
        contentMarkdown:
          '# Delta gönderen cihaz\n\nbirinci satır\nikinci satır\nESKİ İSTEMCİ satırı',
        contentFormat: 'delta',
      },
    });

    const result = res.json().results[0];
    expect(result.status).toBe('merged');
    expect(result.merged.contentMarkdown).toContain('SUNUCU satırı');
    expect(result.merged.contentMarkdown).toContain('ESKİ İSTEMCİ satırı');
    // The title heading the old client prefixed did not survive into the body.
    expect(result.merged.contentMarkdown).not.toContain('# Delta gönderen cihaz');
    // And the delta column stayed empty throughout.
    const row = await app.db('notes').where({ id: noteId }).first();
    expect(row.content_delta).toBeNull();
    expect(row.content_format).toBe('markdown');
  });
});
