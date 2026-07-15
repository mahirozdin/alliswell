import fp from 'fastify-plugin';
import { createJobRunner } from '../queue/runner.js';
import {
  runInboundSyncJob,
  runWatchJob,
  sweepCalendarAccounts,
} from '../queue/calendar-sync-job.js';

/**
 * Inbound calendar sync (OPH-074/075/076, BLUEPRINT §7.2 steps 6-10) — the
 * mirror plugin's twin, pointing the other way. Two job kinds share one queue:
 *
 * - `watch` — open/renew the account's Google push channel
 * - `sync`  — consume everything that changed since the last pass
 *
 * Triggers: the webhook (a change was announced), choosing a default calendar
 * (first full sync), and the sweep (renewals, retries, and polling for
 * installs with no public webhook address).
 */
export default fp(
  async function calendarSyncPlugin(app) {
    const runner = createJobRunner(app, {
      name: 'calendar-inbound',
      handler: (data) =>
        data.type === 'watch' ? runWatchJob(app, data) : runInboundSyncJob(app, data),
      // Per account AND per kind: a pending renewal must not swallow a pending
      // sync, and vice versa.
      jobKey: (data) => `${data.type}-${data.accountId}`,
    });

    const calendarSync = {
      enqueueSync: (accountId) => runner.enqueue({ type: 'sync', accountId }),
      enqueueWatch: (accountId) => runner.enqueue({ type: 'watch', accountId }),
      sweep: () => sweepCalendarAccounts(app),
      idle: () => runner.idle(),
    };
    app.decorate('calendarSync', calendarSync);

    // Unit tests call sweep() themselves — a live timer would make them
    // non-deterministic for no coverage in return.
    if (app.config.env !== 'test') {
      const timer = setInterval(() => {
        calendarSync
          .sweep()
          .catch((err) => app.log.warn({ err: err.message }, 'calendar sweep failed'));
      }, app.config.calendar.sweepSec * 1000);
      timer.unref(); // upkeep must never hold the process open
      app.addHook('onClose', async () => clearInterval(timer));
    }

    app.addHook('onClose', async () => {
      await runner.close();
    });
  },
  {
    name: 'alliswell-calendar-sync',
    // `mirror` because adopting an event hands the task straight back to the
    // outbound queue to bring its content in line.
    dependencies: ['alliswell-redis', 'alliswell-mysql', 'alliswell-mirror'],
  },
);
