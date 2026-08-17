import fp from 'fastify-plugin';

import { sweepNoteVersions } from '../db/note-versions.js';

/**
 * Note-history retention (OPH-267, ADR-0031 §6) — the storage-GC pattern for a
 * table that grows with typing rather than with uploads.
 *
 * Daily by default. Skipped in tests, where the sweep is called directly
 * (`app.noteVersionGc.sweep({ now })`) with a fake clock — a retention policy
 * measured in months cannot be observed by waiting.
 */
export default fp(
  async function noteVersionGcPlugin(app) {
    const sweep = (options) => sweepNoteVersions(app, options);

    app.decorate('noteVersionGc', { sweep });

    if (app.config.env !== 'test') {
      const timer = setInterval(() => {
        sweep()
          .then((removed) => {
            if (removed > 0) app.log.info({ removed }, 'note version sweep');
          })
          .catch((err) => app.log.warn({ err: err.message }, 'note version sweep failed'));
      }, app.config.noteVersions.sweepSec * 1000);
      timer.unref(); // upkeep must never hold the process open
      app.addHook('onClose', async () => clearInterval(timer));
    }
  },
  { name: 'alliswell-note-version-gc', dependencies: ['alliswell-mysql'] },
);
