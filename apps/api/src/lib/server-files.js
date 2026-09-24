import { newId } from './ids.js';
import { notifyEntityWrite } from './ee.js';
import { recordSyncWrite } from '../db/sync.js';
import { sanitizeFileName, storageKeyFor } from '../db/files.js';

/**
 * OPH-340 — a file the SERVER holds, written through the same doors a
 * client's upload walks (ADR-0011, amendment 2026-09-25).
 *
 * ADR-0011's rule stands: a client's bytes go straight to the bucket and
 * never through this API. This module is the one narrow exception, for a file
 * that has no client at all — a message that arrived by mail, a form posted
 * by a page that cannot sign a request. Nobody else could put those bytes in
 * the bucket, so the server does, and the storage plugin's `putObject` relay
 * is reached through here and nowhere else.
 *
 * ── THE EXCEPTION CARRIES EVERY PROTECTION THE CLIENT PATH HAS ─────────
 *
 * An exception that skipped a check would be the way around it, so each one
 * is applied here, to the bytes in hand rather than to a declaration:
 *
 *   size      `maxUploadBytes`, against the buffer's own length.
 *   type      decided by the FIRST BYTES, among the types the caller
 *             accepts. The name and any claimed type never get a vote, and
 *             the stored name takes the extension of what the file IS.
 *   guards    every OPH-331 upload guard, asked with the MEASURED size in
 *             the `commit` phase — so a storage quota cannot be walked past
 *             by writing from the server instead of the client.
 *   target    a core target must be a live row of this workspace. An
 *             extension's own kind is the extension's to vouch for: it is
 *             the caller here, and its registered check asks questions about
 *             a PERSON (a team, a membership, a verb) that a server holding
 *             a mail cannot answer.
 *
 * Refusals are thrown as `ServerFileRefused` with a stable code, and nothing
 * is written before the last of them has passed.
 *
 * ── BORN READY, AND ANNOUNCED ──────────────────────────────────────────
 *
 * The client handshake exists to learn whether the bytes arrived; here they
 * were in this process and the relay reported what it wrote, so the row is
 * written `ready` with its sync revision in one transaction. The entity-write
 * observers hear it like any upload (OPH-325), with `origin: 'server'` so an
 * observer can tell a file nobody uploaded from one somebody did. The caller
 * may write its own rows in the same transaction (`inTransaction`); if
 * anything there fails, the row rolls back and the object is queued for
 * removal, so no byte is left that nothing points at.
 *
 * The plain build has no caller of this module, and its behaviour does not
 * change: `test/unit/server-files.test.js` pins that no core module imports it.
 */

export class ServerFileRefused extends Error {
  constructor(code, message = code) {
    super(message);
    this.code = code;
  }
}

/** Enough bytes for any signature a caller is likely to test; a type needs fewer. */
const SNIFF_BYTES = 16;

const CORE_TARGET_TABLES = Object.freeze({ project: 'projects', task: 'tasks', note: 'notes' });

/**
 * What the first bytes say this is, among `types` (`{ mime, ext, match(head) }`),
 * or null. Never reads the name.
 */
export function sniffFileType(body, types) {
  if (!Buffer.isBuffer(body) || body.length < 4) return null;
  const head = body.subarray(0, SNIFF_BYTES);
  return types.find((type) => type.match(head)) ?? null;
}

/**
 * The name to store: the caller's (made safe), wearing the extension of what
 * the file IS. A photo that arrived as `invoice.pdf` is saved as
 * `invoice.jpg` and opens as a photo.
 */
export function nameForSniffed(raw, ext, fallback = 'file') {
  const clean = sanitizeFileName(raw) ?? fallback;
  const stem = clean.replace(/\.[A-Za-z0-9]{1,8}$/, '').trim() || fallback;
  return `${stem}.${ext}`;
}

async function targetExists(app, { workspaceId, targetType, targetId }) {
  if (app.ee?.attachmentTargets?.[targetType]) return true;
  if (targetType === 'workspace') return targetId === workspaceId;
  const table = CORE_TARGET_TABLES[targetType];
  if (!table) return false;
  const row = await app
    .db(table)
    .where({ id: targetId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first('id');
  return Boolean(row);
}

/**
 * Writes `body` to storage and gives it a `files` row, or throws
 * `ServerFileRefused` having written nothing.
 *
 * @param {import('fastify').FastifyInstance} app
 * @param {{
 *   workspaceId: string, targetType: string, targetId: string,
 *   body: Buffer, filename?: string|null, fallbackName?: string,
 *   types: Array<{ mime: string, ext: string, match: (head: Buffer) => boolean }>,
 *   uploadedBy?: string|null,
 *   inTransaction?: (trx: import('knex').Knex.Transaction, row: object) => Promise<void>,
 * }} input
 * @returns {Promise<object>} the committed `files` row
 */
export async function storeServerFile(
  app,
  {
    workspaceId,
    targetType,
    targetId,
    body,
    filename = null,
    fallbackName = 'file',
    types,
    uploadedBy = null,
    inTransaction = null,
  },
) {
  if (!app.storage?.enabled) throw new ServerFileRefused('STORAGE_DISABLED');
  if (!Buffer.isBuffer(body) || body.length === 0) throw new ServerFileRefused('FILE_EMPTY');
  if (body.length > app.storage.maxUploadBytes) {
    throw new ServerFileRefused(
      'FILE_TOO_LARGE',
      `File exceeds the ${app.storage.maxUploadBytes}-byte upload limit`,
    );
  }
  const type = sniffFileType(body, types);
  if (!type) throw new ServerFileRefused('FILE_TYPE_REFUSED');
  if (!(await targetExists(app, { workspaceId, targetType, targetId }))) {
    throw new ServerFileRefused('FILE_INVALID_TARGET');
  }

  const fileId = newId();
  // OPH-331, the COMMIT phase — the one that cannot be lied to, because the
  // size is measured. `request` is null: nobody asked; `origin` says so.
  for (const guard of app.ee?.uploadGuards ?? []) {
    const refusal = await guard({
      app,
      db: app.db,
      request: null,
      origin: 'server',
      workspaceId,
      sizeBytes: body.length,
      fileId,
      phase: 'commit',
    });
    if (refusal) {
      throw new ServerFileRefused(
        refusal.code ?? 'FILE_UPLOAD_REFUSED',
        refusal.message ?? 'This upload was refused',
      );
    }
  }

  const key = storageKeyFor(workspaceId, fileId);
  const written = await app.storage.putObject(key, { body, contentType: type.mime });

  let row;
  try {
    await app.db.transaction(async (trx) => {
      const revision = await recordSyncWrite(trx, {
        workspaceId,
        entityType: 'file',
        entityId: fileId,
        operation: 'create',
      });
      await trx('files').insert({
        id: fileId,
        workspace_id: workspaceId,
        target_type: targetType,
        target_id: targetId,
        uploaded_by: uploadedBy,
        name: nameForSniffed(filename, type.ext, fallbackName),
        mime: type.mime,
        size_bytes: written.size,
        storage_key: key,
        status: 'ready',
        revision,
      });
      row = await trx('files').where({ id: fileId }).first();
      await notifyEntityWrite(app, trx, {
        workspaceId,
        entityType: 'file',
        entityId: fileId,
        operation: 'create',
        actorId: uploadedBy,
        after: row,
        origin: 'server',
      });
      if (inTransaction) await inTransaction(trx, row);
    });
  } catch (err) {
    // The object was written and its row was not: nothing points at it, so
    // it goes — through the GC queue, so a store hiccup retries rather than
    // leaking it.
    app.storageGc?.enqueueRemove(key);
    throw err;
  }
  return row;
}
