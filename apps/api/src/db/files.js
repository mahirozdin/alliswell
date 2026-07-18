import { recordSyncWrite } from './sync.js';

/**
 * File metadata helpers (Epic 14, ATTACHMENTS.md §§3+5).
 *
 * The storage key is derived, never stored input: opaque, filename-free, and
 * workspace-prefixed so a bucket listing groups by tenant. Rename never moves
 * the object because the name simply is not in the key.
 */
export function storageKeyFor(workspaceId, fileId) {
  return `ws/${workspaceId}/${fileId}`;
}

/**
 * Soft-deletes one READY file inside the caller's transaction: tombstone
 * revision + `deleted_at`, exactly like every synced entity. The caller owns
 * enqueueing the object deletion AFTER commit (`storageGc.enqueueRemove`) —
 * queueing from inside would race the rollback.
 *
 * @returns {Promise<number>} the tombstone revision
 */
export async function softDeleteReadyFile(trx, { workspaceId, fileId }) {
  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'file',
    entityId: fileId,
    operation: 'delete',
  });
  await trx('files')
    .where({ id: fileId })
    .update({ deleted_at: new Date(), revision, updated_at: new Date() });
  return revision;
}
