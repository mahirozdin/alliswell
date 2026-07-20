import { recordSyncWrite } from './sync.js';
import { softDeleteReadyFile } from './files.js';

/**
 * Folder tree helpers (OPH-169, ADR-0014). Depth is capped and moves are
 * cycle-checked here — one implementation serves the REST routes AND the
 * sync-push handlers.
 */

export const FOLDER_MAX_DEPTH = 10;

/** Live folder row or null. */
export function liveFolder(db, workspaceId, folderId) {
  return db('folders')
    .where({ id: folderId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first();
}

/**
 * 1-based depth of the folder that WOULD sit under [parentId] (null = root →
 * depth 1). Throws never — returns Infinity on a broken chain so callers
 * refuse instead of looping.
 */
export async function depthUnder(db, workspaceId, parentId) {
  let depth = 1;
  let cursor = parentId;
  const seen = new Set();
  while (cursor != null) {
    if (seen.has(cursor) || depth > FOLDER_MAX_DEPTH + 1) return Infinity;
    seen.add(cursor);
    const row = await db('folders')
      .where({ id: cursor, workspace_id: workspaceId })
      .whereNull('deleted_at')
      .first('parent_id');
    if (!row) return Infinity;
    depth += 1;
    cursor = row.parent_id;
  }
  return depth;
}

/** True when [candidateParentId] lies INSIDE [folderId]'s subtree (a cycle). */
export async function wouldCycle(db, workspaceId, folderId, candidateParentId) {
  let cursor = candidateParentId;
  const seen = new Set();
  while (cursor != null && !seen.has(cursor)) {
    if (cursor === folderId) return true;
    seen.add(cursor);
    const row = await db('folders')
      .where({ id: cursor, workspace_id: workspaceId })
      .whereNull('deleted_at')
      .first('parent_id');
    if (!row) return false;
    cursor = row.parent_id;
  }
  return cursor === folderId;
}

/** Every live descendant folder id of [rootId], root EXCLUDED, BFS order. */
export async function subtreeFolderIds(db, workspaceId, rootId) {
  const out = [];
  let frontier = [rootId];
  while (frontier.length > 0) {
    const children = await db('folders')
      .where({ workspace_id: workspaceId })
      .whereIn('parent_id', frontier)
      .whereNull('deleted_at')
      .select('id');
    frontier = children.map((r) => r.id);
    out.push(...frontier);
  }
  return out;
}

/**
 * The counted recursive delete (ADR-0014): tombstones the folder, its
 * descendant folders and their workspace files in ONE transaction (each row
 * its own revision), then queues object GC after commit — the ADR-0011
 * no-orphaned-bytes guarantee, verbatim.
 *
 * @returns {Promise<{folders: number, files: number, rootRevision: number}>}
 */
export async function deleteFolderSubtree(trx, app, { workspaceId, folderId }) {
  const folderIds = [folderId, ...(await subtreeFolderIds(trx, workspaceId, folderId))];

  const fileRows = await trx('files')
    .where({ workspace_id: workspaceId, target_type: 'workspace' })
    .whereIn('folder_id', folderIds)
    .whereNull('deleted_at')
    .select('id', 'status', 'storage_key');

  const keys = [];
  for (const row of fileRows) {
    if (row.status === 'ready') {
      await softDeleteReadyFile(trx, { workspaceId, fileId: row.id });
    } else {
      await trx('files').where({ id: row.id }).delete();
    }
    keys.push(row.storage_key);
  }

  let rootRevision = 0;
  for (const id of folderIds) {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'folder',
      entityId: id,
      operation: 'delete',
    });
    if (id === folderId) rootRevision = revision;
    await trx('folders')
      .where({ id })
      .update({ deleted_at: new Date(), revision, updated_at: new Date() });
  }

  (trx.executionPromise ?? Promise.resolve())
    .then(() => {
      for (const key of keys) app.storageGc.enqueueRemove(key);
    })
    .catch(() => {}); // rolled back — bytes live on

  return { folders: folderIds.length, files: fileRows.length, rootRevision };
}
