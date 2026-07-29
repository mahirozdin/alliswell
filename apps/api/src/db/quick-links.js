import { recordSyncWrite } from './sync.js';

/**
 * Quick link rules (OPH-197, ADR-0018, BLUEPRINT §4.12). One implementation
 * serves the REST routes AND the sync-push handlers, exactly like db/folders.js.
 *
 * Read helpers take `db` (either `app.db` or a trx); writers take a `trx` and
 * expect the caller to own the transaction.
 *
 * Deletes here are always SOFT, and that is load-bearing rather than stylistic:
 * the pull drops rows the caller may not see (ADR-0018), so a hard delete would
 * swallow the OWNER's tombstone too and strand the row on their other devices.
 * Every delete also nulls `target_id`, freeing the uniqueness slot so the same
 * target can be added again later.
 */

export const QUICK_LINK_MAX_PER_USER = 50;
export const QUICK_LINK_KINDS = ['project', 'task', 'note', 'folder', 'file', 'url'];
/** Gap between neighbours, so a future "insert between" needs no rewrite. */
export const QUICK_LINK_SORT_STEP = 1024;

const TARGET_TABLES = {
  project: 'projects',
  task: 'tasks',
  note: 'notes',
  folder: 'folders',
  file: 'files',
};

const HTTP_URL_RE = /^https?:\/\/\S+$/i;

/**
 * Shape rule: entity kinds carry a target and no url, `url` carries a url and
 * no target. Pure — the sync push bypasses Ajv entirely, so this must live
 * outside the route schemas.
 */
export function validateKindShape({ kind, targetId, url }) {
  if (!QUICK_LINK_KINDS.includes(kind)) return 'QUICK_LINK_INVALID_TARGET';
  if (kind === 'url') {
    if (targetId != null) return 'QUICK_LINK_INVALID_TARGET';
    if (typeof url !== 'string' || !HTTP_URL_RE.test(url) || url.length > 2048) {
      return 'QUICK_LINK_INVALID_TARGET';
    }
    return null;
  }
  if (url != null) return 'QUICK_LINK_INVALID_TARGET';
  if (typeof targetId !== 'string' || targetId.length !== 26) return 'QUICK_LINK_INVALID_TARGET';
  return null;
}

/** Live quick link row in this workspace, or undefined. */
export function liveQuickLink(db, { workspaceId, id }) {
  return db('quick_links').where({ id, workspace_id: workspaceId }).whereNull('deleted_at').first();
}

/** The caller's live rows, rail order. */
export function listUserQuickLinks(db, { workspaceId, userId }) {
  return db('quick_links')
    .where({ workspace_id: workspaceId, user_id: userId })
    .whereNull('deleted_at')
    .orderBy('sort_order', 'asc')
    .orderBy('created_at', 'asc')
    .select();
}

/** `select().length`, not `count()` — the ceiling is 50 rows and the unit-test
 *  fake db has no aggregate support. */
export async function countUserQuickLinks(db, { workspaceId, userId }) {
  const rows = await db('quick_links')
    .where({ workspace_id: workspaceId, user_id: userId })
    .whereNull('deleted_at')
    .select('id');
  return rows.length;
}

/** Tail position + one step. */
export async function nextSortOrder(db, { workspaceId, userId }) {
  const rows = await listUserQuickLinks(db, { workspaceId, userId });
  if (rows.length === 0) return 0;
  const last = rows.at(-1);
  return Number(last.sort_order ?? 0) + QUICK_LINK_SORT_STEP;
}

/** Id of the caller's existing shortcut to the same target, or null. */
export async function duplicateQuickLinkId(
  db,
  { workspaceId, userId, kind, targetId, exceptId = null },
) {
  if (kind === 'url') return null; // url rows are deliberately not deduped
  const row = await db('quick_links')
    .where({ workspace_id: workspaceId, user_id: userId, kind, target_id: targetId })
    .whereNull('deleted_at')
    .first('id');
  if (!row || row.id === exceptId) return null;
  return row.id;
}

/** True when the target exists, lives in this workspace and is not deleted. */
export async function targetExists(db, { workspaceId, kind, targetId }) {
  const table = TARGET_TABLES[kind];
  if (!table) return false;
  let query = db(table).where({ id: targetId, workspace_id: workspaceId }).whereNull('deleted_at');
  // An `uploading` file has never synced and has no bytes yet; it is not a
  // thing a user can have opened, so it cannot be a shortcut target.
  if (kind === 'file') query = query.where({ status: 'ready' });
  return Boolean(await query.first('id'));
}

/**
 * The single create gate, shared by `POST /quick-links` and the sync push
 * guard. Returns a machine-readable code or null.
 */
export async function checkCreatable(db, { workspaceId, userId, kind, targetId, url }) {
  const shapeError = validateKindShape({ kind, targetId, url });
  if (shapeError) return shapeError;
  if ((await countUserQuickLinks(db, { workspaceId, userId })) >= QUICK_LINK_MAX_PER_USER) {
    return 'QUICK_LINK_LIMIT';
  }
  if (kind !== 'url') {
    if (!(await targetExists(db, { workspaceId, kind, targetId }))) {
      return 'QUICK_LINK_TARGET_NOT_FOUND';
    }
    if (await duplicateQuickLinkId(db, { workspaceId, userId, kind, targetId })) {
      return 'QUICK_LINK_DUPLICATE';
    }
  }
  return null;
}

/**
 * The order payload must be the caller's EXACT live id set: `sort_order =
 * index * step` only defines a total order if the list is total, and a partial
 * list would leave the unlisted rows at stale offsets that interleave
 * arbitrarily.
 */
export async function validateOrder(db, { workspaceId, userId, orderedIds }) {
  if (!Array.isArray(orderedIds) || orderedIds.length === 0) return 'QUICK_LINK_ORDER_INCOMPLETE';
  if (new Set(orderedIds).size !== orderedIds.length) return 'QUICK_LINK_ORDER_INCOMPLETE';
  const rows = await listUserQuickLinks(db, { workspaceId, userId });
  if (rows.length !== orderedIds.length) return 'QUICK_LINK_ORDER_INCOMPLETE';
  const live = new Set(rows.map((r) => r.id));
  if (orderedIds.some((id) => !live.has(id))) return 'QUICK_LINK_ORDER_INCOMPLETE';
  return null;
}

/** Soft-deletes one row (frees the target slot); returns its new revision. */
export async function softDeleteQuickLink(trx, { workspaceId, id }) {
  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'quick_link',
    entityId: id,
    operation: 'delete',
  });
  await trx('quick_links')
    .where({ id })
    .update({ deleted_at: new Date(), target_id: null, revision, updated_at: new Date() });
  return revision;
}

/**
 * Every member's shortcuts to the given hard-deleted targets die in the SAME
 * transaction, each with its own revision so every device's rail heals itself
 * on the next pull (ADR-0018 §4). Archiving must NOT call this — archives are
 * reversible and the shortcut stays, rendered muted.
 *
 * @param {Array<{type: string, id: string}>} targets
 * @returns {Promise<number>} number of shortcuts removed
 */
export async function cascadeDeleteQuickLinks(trx, { workspaceId, targets }) {
  const byKind = new Map();
  for (const { type, id } of targets) {
    if (!TARGET_TABLES[type]) continue;
    if (!byKind.has(type)) byKind.set(type, []);
    byKind.get(type).push(id);
  }
  let removed = 0;
  for (const [kind, ids] of byKind) {
    const rows = await trx('quick_links')
      .where({ workspace_id: workspaceId, kind })
      .whereIn('target_id', ids)
      .whereNull('deleted_at')
      .select('id');
    for (const row of rows) {
      await softDeleteQuickLink(trx, { workspaceId, id: row.id });
      removed += 1;
    }
  }
  return removed;
}

/**
 * Writes the whole order in one transaction. Every row gets its own revision
 * (so other devices converge) EXCEPT `skipRevisionFor` — the sync-push anchor,
 * whose revision was already minted by `applyUpdate` and recorded against the
 * client mutation; re-stamping it would overwrite that.
 *
 * @returns {Promise<Map<string, number>>} id → revision (anchor excluded)
 */
export async function writeQuickLinkOrder(
  trx,
  { workspaceId, userId, orderedIds, skipRevisionFor = null },
) {
  const revisions = new Map();
  for (const [index, id] of orderedIds.entries()) {
    const sortOrder = index * QUICK_LINK_SORT_STEP;
    // user_id in every where: even with a skipped validation, a foreign id
    // updates zero rows.
    const scope = { id, workspace_id: workspaceId, user_id: userId };
    if (id === skipRevisionFor) {
      await trx('quick_links').where(scope).update({ sort_order: sortOrder });
      continue;
    }
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'quick_link',
      entityId: id,
      operation: 'update',
      changedFields: ['sort_order'],
    });
    await trx('quick_links')
      .where(scope)
      .update({ sort_order: sortOrder, revision, updated_at: new Date() });
    revisions.set(id, revision);
  }
  return revisions;
}
