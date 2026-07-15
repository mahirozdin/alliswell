import { EventEmitter } from 'node:events';

/**
 * In-process bridge between the write paths and the socket layer (OPH-057).
 * `recordSyncWrite` publishes AFTER its transaction commits; the socket
 * plugin relays 'sync:changed' to the workspace's room (the Redis adapter
 * fans out across instances — no payload beyond {workspaceId, toRevision},
 * clients respond by pulling, BLUEPRINT §6.2/ARCHITECTURE §5).
 */
export const syncEvents = new EventEmitter();
// Unit tests run several app instances per process — keep headroom.
syncEvents.setMaxListeners(50);

const pending = new Map();
let flushScheduled = false;

function flush() {
  flushScheduled = false;
  for (const [workspaceId, toRevision] of pending) {
    syncEvents.emit('sync:changed', { workspaceId, toRevision });
  }
  pending.clear();
}

/**
 * Coalesces bursts: one request often commits several revisions (task +
 * reminder + …) — the room gets ONE event per workspace per tick, carrying
 * the highest revision seen.
 *
 * @param {string} workspaceId
 * @param {number} revision
 */
export function publishSyncChanged(workspaceId, revision) {
  pending.set(workspaceId, Math.max(pending.get(workspaceId) ?? 0, revision));
  if (!flushScheduled) {
    flushScheduled = true;
    setImmediate(flush);
  }
}

/**
 * Per-entity post-commit notification — the calendar mirror (OPH-072)
 * listens for task changes. Uncoalesced on purpose: the mirror queue dedupes
 * by task id itself.
 *
 * @param {{ workspaceId: string, entityType: string, entityId: string,
 *           operation: 'create'|'update'|'delete' }} change
 */
export function publishEntityChanged(change) {
  syncEvents.emit('entity:changed', change);
}
