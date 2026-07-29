import fp from 'fastify-plugin';

import { materializeSeries } from '../db/task-series.js';

/**
 * The rolling window's engine (OPH-205, ADR-0020 §4/§5): every day, each live
 * series gets the occurrences that have just entered its 12-month horizon.
 *
 * This is an interval, not a BullMQ repeatable — the house pattern of
 * account-gc/storage-gc/calendar-sync, for the reasons ADR-0020 §5 records:
 * `createJobRunner` has no repeatable API, the self-host path must work with
 * Redis absent, and running on every replica is harmless because
 * `materializeSeries` is idempotent on `(series_id, occurrence_date)`.
 *
 * Skipped in tests — call `app.seriesGc.sweep(now)` directly there, passing the
 * clock you want (the API suite injects `now`, it does not fake timers).
 */

export default fp(
  async function seriesGcPlugin(app) {
    async function sweep(now = new Date()) {
      const series = await app
        .db('task_series')
        .whereNull('deleted_at')
        .orderBy('id', 'asc')
        .select();
      let created = 0;
      for (const row of series) {
        try {
          await app.db.transaction(async (trx) => {
            const result = await materializeSeries(trx, {
              workspaceId: row.workspace_id,
              series: row,
              now,
            });
            created += result.created;
          });
        } catch (err) {
          // One impossible rule must not stop every other series in the
          // instance; the next sweep retries it and the log names the series.
          app.log.error({ err: err.message, seriesId: row.id }, 'series materialization failed');
        }
      }
      if (created > 0) app.log.info({ series: series.length, created }, 'series window rolled');
      return created;
    }

    app.decorate('seriesGc', { sweep });

    if (app.config.env !== 'test') {
      const timer = setInterval(() => {
        sweep().catch((err) => app.log.warn({ err: err.message }, 'series sweep failed'));
      }, app.config.seriesSweepSec * 1000);
      timer.unref(); // upkeep must never hold the process open
      app.addHook('onClose', async () => clearInterval(timer));
    }
  },
  { name: 'alliswell-series-gc', dependencies: ['alliswell-mysql'] },
);
