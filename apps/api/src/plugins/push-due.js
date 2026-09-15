import fp from 'fastify-plugin';

import { sweepDuePushes } from '../db/reminder-push.js';

/**
 * The clock behind the due sweep (OPH-315, ADR-0038 §3).
 *
 * An interval, not a BullMQ repeatable — the house pattern of
 * series-gc/account-gc/calendar-sync, and for the same reasons: the self-host
 * path must work with Redis absent, and running on every replica is harmless
 * because the sweep claims each delivery with a unique index rather than
 * assuming it is alone.
 *
 * Skipped in tests — call `app.pushDue.sweep({ now })` directly there with the
 * instant you want. A live timer would only add non-determinism.
 */
export default fp(
  async function pushDuePlugin(app) {
    const sweep = (options) => sweepDuePushes(app, options);
    app.decorate('pushDue', { sweep });

    // Nothing to send with means nothing to run: an instance without push
    // credentials should not wake up every minute to learn that again.
    if (app.config.env !== 'test' && app.pushTransport) {
      const timer = setInterval(() => {
        sweep().catch((err) => app.log.warn({ err: err.message }, 'reminder push sweep failed'));
      }, app.config.push.sweepSec * 1000);
      timer.unref(); // upkeep must never hold the process open
      app.addHook('onClose', async () => clearInterval(timer));
    }
  },
  { name: 'alliswell-push-due', dependencies: ['alliswell-mysql', 'alliswell-push'] },
);
