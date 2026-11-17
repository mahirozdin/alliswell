import crypto from 'node:crypto';

import { newId } from '../lib/ids.js';

/**
 * Note history (OPH-267, ADR-0031).
 *
 * `captureNoteVersion` is called from inside the note-write transaction in
 * `db/notes.js` and nowhere else — that ONE call site is what makes REST, sync
 * push, MCP, an API key and bulk import all produce history without any of
 * them knowing history exists (ADR-0031 §2).
 *
 * Two things keep the table honest rather than merely full:
 *
 * - **the rolling head** — a follow-up write from the same client, same
 *   `origin='edit'`, inside the coalescing window updates the newest row in
 *   place. The editor autosaves on a 1.5 s idle debounce (finding #5), so ten
 *   minutes of typing is one row, not ~260;
 * - **the content hash** — an identical body writes nothing at all.
 */

/** Where a version came from. `edit` is a human typing; the rest are events. */
export const NOTE_VERSION_ORIGINS = [
  // The note's birth state. Not in the backlog's enum — it earned its place
  // when the tests showed the creation row being coalesced INTO by the first
  // edit that followed it, which silently deleted "what this note was when it
  // arrived". Because the rolling head only ever merges into a previous row
  // whose origin is `edit`, giving birth its own name makes it unmergeable by
  // construction rather than by a special case.
  'create',
  'edit',
  'merge',
  'restore',
  'conflict',
  'import',
  'api',
  'mcp',
];

/** Origins that never coalesce: each one is a moment somebody may point at. */
const NON_COALESCING = new Set(['merge', 'restore', 'conflict', 'import', 'api', 'mcp']);

/**
 * The note fields a version is made of. Anything else is not content.
 *
 * ADR-0033 emptied the delta half. Every write path normalizes its body to
 * markdown before the row reaches here, and the note's `content_delta` column
 * still holds whatever it held before the 2026-08-18 migration — so capturing
 * it would pair a FRESH markdown body with a STALE delta inside one version
 * row, and `restore` would have to guess which of the two you meant.
 */
export function versionSnapshotOf(row) {
  return {
    title: row.title ?? '',
    content_delta: null,
    content_markdown: row.content_markdown ?? null,
    content_format: 'markdown',
  };
}

/**
 * SHA-256 over the snapshot, so identical bodies do not stack (ADR-0031 §4).
 *
 * The format is still part of it, and the delta slot is still in the join, so
 * the digest of a pre-ADR-0033 version is reproducible: the 2026-08-18
 * migration recomputes the hashes of the rows it converts with exactly this
 * function, which is what keeps "unchanged" honest across the change.
 */
export function contentHash(snapshot) {
  return crypto
    .createHash('sha256')
    .update(
      [
        snapshot.title,
        snapshot.content_format,
        snapshot.content_markdown ?? '',
        snapshot.content_delta ?? '',
      ].join('\0'),
    )
    .digest('hex');
}

/** True when this write changed anything a version would record. */
export function isContentWrite(patch) {
  return ['title', 'content_delta', 'content_markdown', 'content_format'].some(
    (field) => field in patch,
  );
}

/**
 * Records one version, inside the caller's transaction.
 *
 * @param {object} trx knex transaction — the SAME one writing the note, so a
 *   version and the write it describes commit together or not at all
 * @param {object} options
 * @param {object} options.config app.config (retention/coalescing knobs)
 * @param {object} options.row the note row AFTER the write
 * @param {string} options.origin one of [NOTE_VERSION_ORIGINS]
 * @param {string} [options.clientId] the sync client, when there is one
 * @param {string} [options.userId]
 * @param {Date} [options.now]
 * @returns {Promise<{action: 'inserted'|'coalesced'|'unchanged', id: string}>} what it
 *   did and which row holds the content now — OPH-268 needs that id to hand a
 *   client the `conflictVersionId` of the body it just refused.
 */
export async function captureNoteVersion(
  trx,
  { config, row, origin = 'edit', clientId = null, userId = null, now = new Date() },
) {
  const snapshot = versionSnapshotOf(row);
  const hash = contentHash(snapshot);

  const previous = await trx('note_versions')
    .where({ note_id: row.id })
    .orderBy('created_at', 'desc')
    .orderBy('id', 'desc')
    .first();

  // No history yet → this is the note's birth. Say so, so the first edit
  // cannot roll it up (see [NOTE_VERSION_ORIGINS]).
  const effectiveOrigin = !previous && origin === 'edit' ? 'create' : origin;

  // Identical content: an autosave that fired after a cursor move is not a
  // version (ADR-0031 §4).
  if (previous && previous.content_hash === hash) return { action: 'unchanged', id: previous.id };

  const windowMs = (config.noteVersions?.coalesceMin ?? 10) * 60 * 1000;
  const canCoalesce =
    previous &&
    !NON_COALESCING.has(effectiveOrigin) &&
    previous.origin === 'edit' &&
    (previous.client_id ?? null) === (clientId ?? null) &&
    now.getTime() - new Date(previous.created_at).getTime() < windowMs;

  if (canCoalesce) {
    // The rolling head: the row keeps its identity and its created_at (when
    // this editing session STARTED), and takes the newest body.
    await trx('note_versions')
      .where({ id: previous.id })
      .update({
        ...snapshot,
        note_revision: Number(row.revision ?? 0),
        content_hash: hash,
        created_by: userId ?? previous.created_by ?? null,
        // OPH-494: the moment this body was written, for history and the
        // conflict banner — `created_at` stays the session's start.
        updated_at: now,
      });
    return { action: 'coalesced', id: previous.id };
  }

  const id = newId();
  await trx('note_versions').insert({
    id,
    workspace_id: row.workspace_id,
    note_id: row.id,
    note_revision: Number(row.revision ?? 0),
    ...snapshot,
    origin: effectiveOrigin,
    client_id: clientId,
    created_by: userId,
    content_hash: hash,
    created_at: now,
    updated_at: now,
  });
  return { action: 'inserted', id };
}

/**
 * The retention sweep (ADR-0031 §6). Server policy, deliberately not
 * negotiated with devices — Joplin's history collapses to the minimum any
 * device kept, which is how an offline phone truncates a laptop's history.
 *
 * Three tiers plus a cap, applied oldest-first:
 *   0–7 days              keep everything
 *   7–RETENTION_DAYS      thin to one per note per calendar day
 *   older                 delete
 *   conflict/merge/restore/import survive to PROTECTED_DAYS regardless
 *   more than CAP rows for one note → thin from the oldest end
 *
 * Returns how many rows it removed, so the log line is a number and not a
 * feeling.
 */
export async function sweepNoteVersions(app, { now = new Date(), batch = 500 } = {}) {
  const policy = app.config.noteVersions;
  const protectedOrigins = ['conflict', 'merge', 'restore', 'import'];
  const fresh = new Date(now.getTime() - policy.keepAllDays * 86400000);
  const retention = new Date(now.getTime() - policy.retentionDays * 86400000);
  const protectedCutoff = new Date(now.getTime() - policy.protectedDays * 86400000);

  let removed = 0;

  // Tier 3 — past retention. Protected origins get their longer window.
  const expired = await app
    .db('note_versions')
    .where('created_at', '<', retention)
    .whereNotIn('origin', protectedOrigins)
    .limit(batch)
    .select('id');
  const expiredProtected = await app
    .db('note_versions')
    .where('created_at', '<', protectedCutoff)
    .whereIn('origin', protectedOrigins)
    .limit(batch)
    .select('id');
  const doomed = [...expired, ...expiredProtected].map((r) => r.id);
  if (doomed.length > 0) {
    removed += await app.db('note_versions').whereIn('id', doomed).delete();
  }

  // Tier 2 — between the fresh window and retention: one per note per day.
  // Read the survivors and decide in JS: the grouping is by (note, calendar
  // day, origin-is-protected), which no portable single statement expresses.
  const thinnable = await app
    .db('note_versions')
    .where('created_at', '<', fresh)
    .where('created_at', '>=', retention)
    .whereNotIn('origin', protectedOrigins)
    .orderBy('created_at', 'desc')
    .limit(batch * 4)
    .select('id', 'note_id', 'created_at');
  const keptDay = new Set();
  const extras = [];
  for (const version of thinnable) {
    const day = new Date(version.created_at).toISOString().slice(0, 10);
    const key = `${version.note_id}:${day}`;
    // Newest-first, so the first row seen for a day is the one that survives.
    if (keptDay.has(key)) extras.push(version.id);
    else keptDay.add(key);
  }
  if (extras.length > 0) {
    removed += await app.db('note_versions').whereIn('id', extras).delete();
  }

  // The per-note cap, oldest-first (protected rows included: a cap is a cap).
  const counts = new Map();
  const recent = await app
    .db('note_versions')
    .orderBy('created_at', 'desc')
    .limit(policy.cap * 20)
    .select('id', 'note_id');
  const overflow = [];
  for (const version of recent) {
    const seen = (counts.get(version.note_id) ?? 0) + 1;
    counts.set(version.note_id, seen);
    if (seen > policy.cap) overflow.push(version.id);
  }
  if (overflow.length > 0) {
    removed += await app.db('note_versions').whereIn('id', overflow).delete();
  }

  return removed;
}
