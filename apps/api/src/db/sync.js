import { newId } from '../lib/ids.js';
import { publishSyncChanged, publishEntityChanged } from '../lib/sync-events.js';

/**
 * Records one entity write in the workspace's monotonic change log
 * (BLUEPRINT §6.2, AGENTS.md §6): bumps `workspaces.revision` and inserts the
 * matching `sync_revisions` row. MUST run inside the same transaction as the
 * entity write itself, and the caller MUST stamp the returned revision onto
 * the entity row — that is what makes incremental sync pulls consistent.
 *
 * Concurrency: the UPDATE takes a row lock on the workspace, serializing
 * writers per workspace, so (workspace_id, revision) stays unique.
 *
 * @param {import('knex').Knex.Transaction} trx
 * @param {{ workspaceId: string, entityType: string, entityId: string,
 *           operation: 'create'|'update'|'delete', changedFields?: string[] }} write
 * @returns {Promise<number>} the new workspace revision
 */
export async function recordSyncWrite(
  trx,
  { workspaceId, entityType, entityId, operation, changedFields },
) {
  await trx('workspaces').where({ id: workspaceId }).increment('revision', 1);
  const workspace = await trx('workspaces').where({ id: workspaceId }).first('revision');
  const revision = Number(workspace.revision);

  await trx('sync_revisions').insert({
    id: newId(),
    workspace_id: workspaceId,
    revision,
    entity_type: entityType,
    entity_id: entityId,
    operation,
    changed_fields: changedFields ? JSON.stringify(changedFields) : null,
  });

  // Announce only AFTER the transaction commits (an emit from inside would
  // leak uncommitted revisions). The in-memory test db has no
  // executionPromise — its "transactions" always commit.
  (trx.executionPromise ?? Promise.resolve())
    .then(() => {
      publishSyncChanged(workspaceId, revision);
      publishEntityChanged({ workspaceId, entityType, entityId, operation });
    })
    .catch(() => {}); // rolled back — nothing happened, nothing to announce

  return revision;
}

/**
 * Blueprint-named form of the same helper (OPH-050, BLUEPRINT §6.2) with
 * positional arguments:
 *
 *   const revision = await withRevision(trx, wsId, 'task', taskId, 'update', ['title']);
 *
 * Both names hit the identical implementation — routes written against
 * recordSyncWrite (Epics 04–05) need no retrofit.
 *
 * @param {import('knex').Knex.Transaction} trx
 * @param {string} workspaceId
 * @param {string} entityType
 * @param {string} entityId
 * @param {'create'|'update'|'delete'} operation
 * @param {string[]} [changedFields]
 * @returns {Promise<number>} the new workspace revision
 */
export function withRevision(trx, workspaceId, entityType, entityId, operation, changedFields) {
  return recordSyncWrite(trx, { workspaceId, entityType, entityId, operation, changedFields });
}

const BULK_INSERT_CHUNK = 500;

/**
 * Bulk form of [recordSyncWrite] for a writer that materializes MANY rows of
 * one workspace at once (an import, a bulk provisioning step, a repair job).
 *
 * Same invariants, same output: the workspace revision advances by exactly
 * one per write, and each write gets its own `sync_revisions` row with a
 * consecutive revision — a puller cannot tell these apart from N single
 * calls. What changes is the cost: one increment + one read + chunked
 * inserts, instead of three round trips per row (measured on 3000 rows:
 * seconds → tens of milliseconds).
 *
 * Ordering: revisions are assigned in array order, so the caller can zip the
 * returned array back onto its rows to stamp them.
 *
 * @param {import('knex').Knex.Transaction} trx
 * @param {string} workspaceId
 * @param {Array<{entityType: string, entityId: string,
 *                operation: 'create'|'update'|'delete', changedFields?: string[]}>} writes
 * @returns {Promise<number[]>} the assigned revisions, in the writes' order
 */
export async function recordSyncWrites(trx, workspaceId, writes) {
  if (writes.length === 0) return [];

  // One row lock, one allocation: the same serialization single writes get,
  // paid once for the whole batch.
  await trx('workspaces').where({ id: workspaceId }).increment('revision', writes.length);
  const workspace = await trx('workspaces').where({ id: workspaceId }).first('revision');
  const last = Number(workspace.revision);
  const first = last - writes.length + 1;

  const rows = writes.map((write, i) => ({
    id: newId(),
    workspace_id: workspaceId,
    revision: first + i,
    entity_type: write.entityType,
    entity_id: write.entityId,
    operation: write.operation,
    changed_fields: write.changedFields ? JSON.stringify(write.changedFields) : null,
  }));
  for (let i = 0; i < rows.length; i += BULK_INSERT_CHUNK) {
    await trx('sync_revisions').insert(rows.slice(i, i + BULK_INSERT_CHUNK));
  }

  // After commit, exactly like the single-write path. One sync-changed event
  // carries the whole batch (clients pull a range, not a row).
  (trx.executionPromise ?? Promise.resolve())
    .then(() => {
      publishSyncChanged(workspaceId, last);
      for (const write of writes) {
        publishEntityChanged({
          workspaceId,
          entityType: write.entityType,
          entityId: write.entityId,
          operation: write.operation,
        });
      }
    })
    .catch(() => {});

  return rows.map((row) => row.revision);
}
