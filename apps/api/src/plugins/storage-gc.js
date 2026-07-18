import fp from 'fastify-plugin';
import { createJobRunner } from '../queue/runner.js';

/**
 * Storage garbage collection (Epic 14, ATTACHMENTS.md §§2.1+5) — the "no
 * orphaned bytes" half of the design:
 *
 * - **`storage-delete` job**: object deletions ride the shared queue runner
 *   (BullMQ with Redis, inline otherwise) so a transient store error retries
 *   instead of leaking the object. `jobKey = storage key` dedupes bursts;
 *   deleting an already-missing object is success (`remove` is idempotent).
 * - **Stale-upload sweep**: `uploading` rows are invisible to sync, so ones
 *   whose client vanished mid-PUT would sit forever. Rows older than 24 h are
 *   hard-deleted (they never synced — no tombstone owed) and their objects
 *   queued for removal. Runs every `STORAGE_SWEEP_SEC`, skipped in tests
 *   (call `app.storageGc.sweepStaleUploads()` directly there).
 */

export const STALE_UPLOAD_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const SWEEP_BATCH = 100;

export default fp(
  async function storageGcPlugin(app) {
    const runner = createJobRunner(app, {
      name: 'storage-delete',
      jobKey: (data) => data.storageKey,
      handler: async ({ storageKey }) => {
        if (!app.storage.enabled) return; // feature turned off since enqueue
        await app.storage.remove(storageKey);
      },
    });

    async function sweepStaleUploads(now = new Date()) {
      if (!app.storage.enabled) return 0;
      const cutoff = new Date(now.getTime() - STALE_UPLOAD_MAX_AGE_MS);
      const rows = await app
        .db('files')
        .where({ status: 'uploading' })
        .where('created_at', '<', cutoff)
        .limit(SWEEP_BATCH)
        .select('id', 'storage_key');
      for (const row of rows) {
        // Guarded delete: if the upload completed between select and here,
        // the row is `ready` now and must survive.
        const removed = await app.db('files').where({ id: row.id, status: 'uploading' }).delete();
        if (removed > 0) await runner.enqueue({ storageKey: row.storage_key });
      }
      return rows.length;
    }

    app.decorate('storageGc', {
      /** Fire-and-forget object deletion (call AFTER the deleting tx commits). */
      enqueueRemove: (storageKey) => runner.enqueue({ storageKey }),
      idle: () => runner.idle(),
      sweepStaleUploads,
    });

    if (app.config.env !== 'test' && app.storage.enabled) {
      const timer = setInterval(() => {
        sweepStaleUploads().catch((err) =>
          app.log.warn({ err: err.message }, 'stale-upload sweep failed'),
        );
      }, app.config.storage.sweepSec * 1000);
      timer.unref(); // upkeep must never hold the process open
      app.addHook('onClose', async () => clearInterval(timer));
    }

    app.addHook('onClose', async () => {
      await runner.close();
    });
  },
  { name: 'alliswell-storage-gc', dependencies: ['alliswell-mysql', 'alliswell-storage'] },
);
