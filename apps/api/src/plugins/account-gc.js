import fp from 'fastify-plugin';

import { accountsDueForPurge, purgeAccount } from '../db/accounts.js';

/**
 * Account-deletion sweep: erases accounts whose grace period has expired
 * (src/db/accounts.js).
 *
 * A promise to delete data is only worth what actually deletes it, so this runs
 * on a timer rather than waiting for the user to come back. Purges are
 * sequential — each one cascades across a whole workspace and queues object
 * deletions, and there is no deadline that makes hammering the database worth
 * it.
 *
 * Skipped in tests (call `app.accountGc.sweep()` directly there), exactly like
 * the storage sweep.
 */

const SWEEP_BATCH = 50;

export default fp(
  async function accountGcPlugin(app) {
    async function sweep(now = new Date()) {
      const userIds = await accountsDueForPurge(app.db, now, SWEEP_BATCH);
      let purged = 0;
      for (const userId of userIds) {
        try {
          const result = await purgeAccount(app, userId);
          purged += 1;
          app.log.info({ userId, ...result }, 'account purged');
        } catch (err) {
          // One stuck account must not stop the rest; the next sweep retries it.
          app.log.error({ err: err.message, userId }, 'account purge failed');
        }
      }
      return purged;
    }

    app.decorate('accountGc', { sweep });

    if (app.config.env !== 'test') {
      const timer = setInterval(() => {
        sweep().catch((err) => app.log.warn({ err: err.message }, 'account sweep failed'));
      }, app.config.accountSweepSec * 1000);
      timer.unref(); // upkeep must never hold the process open
      app.addHook('onClose', async () => clearInterval(timer));
    }
  },
  { name: 'alliswell-account-gc', dependencies: ['alliswell-mysql'] },
);
