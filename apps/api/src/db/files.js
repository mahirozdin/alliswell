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

/**
 * The "no orphaned bytes" cascade (ATTACHMENTS.md §5): when entities die,
 * their files die in the SAME transaction — ready files tombstone (one
 * revision each, replicas must drop them), uploading leftovers hard-delete
 * (they never synced). Object deletions are scheduled onto the GC queue only
 * after the transaction commits (`executionPromise`, the recordSyncWrite
 * announce pattern) so a rollback never deletes real bytes.
 *
 * Used by every entity-delete path — REST routes and sync-push handlers —
 * for tasks (whole subtrees), notes and projects.
 *
 * @param {import('knex').Knex.Transaction} trx
 * @param {import('fastify').FastifyInstance} app
 * @param {{ workspaceId: string, targets: Array<{ type: 'project'|'task'|'note', id: string }> }} args
 * @returns {Promise<number>} how many file rows were affected
 */
export async function cascadeDeleteFiles(trx, app, { workspaceId, targets }) {
  if (!targets || targets.length === 0) return 0;

  const idsByType = new Map();
  for (const { type, id } of targets) {
    if (!idsByType.has(type)) idsByType.set(type, []);
    idsByType.get(type).push(id);
  }

  const rows = [];
  for (const [type, ids] of idsByType) {
    rows.push(
      ...(await trx('files')
        .where({ workspace_id: workspaceId, target_type: type })
        .whereIn('target_id', ids)
        .whereNull('deleted_at')
        .select('id', 'status', 'storage_key')),
    );
  }
  if (rows.length === 0) return 0;

  const keys = [];
  for (const row of rows) {
    if (row.status === 'ready') {
      await softDeleteReadyFile(trx, { workspaceId, fileId: row.id });
    } else {
      await trx('files').where({ id: row.id }).delete();
    }
    keys.push(row.storage_key);
  }

  (trx.executionPromise ?? Promise.resolve())
    .then(() => {
      for (const key of keys) app.storageGc.enqueueRemove(key);
    })
    .catch(() => {}); // rolled back — the files (and their bytes) live on

  return rows.length;
}
