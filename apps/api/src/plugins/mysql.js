import fp from 'fastify-plugin';
import knex from 'knex';
import { buildKnexConfig } from '../db/knexconfig.js';

/**
 * Decorates the app with `app.db` (a knex instance). Connections are pooled lazily,
 * so the server boots even when MySQL is unreachable — /health/ready reports it.
 *
 * Tests may pass a stub via `buildApp({ db })`; the plugin then skips lifecycle handling.
 */
export default fp(
  async function mysqlPlugin(app, opts) {
    const owned = !opts.db;
    const db = opts.db ?? knex(buildKnexConfig(app.config));

    app.decorate('db', db);

    app.addHook('onClose', async () => {
      if (owned) await db.destroy();
    });
  },
  { name: 'alliswell-mysql' },
);
