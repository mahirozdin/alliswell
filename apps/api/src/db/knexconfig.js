import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { resolveEeDir } from '../lib/ee.js';

/**
 * Shared knex configuration used by both the runtime plugin (src/plugins/mysql.js)
 * and the knex CLI (knexfile.js). Timestamps are stored as UTC (`timezone: 'Z'`).
 *
 * @param {ReturnType<import('../config.js')['loadConfig']>} config
 */
export function buildKnexConfig(config) {
  // EE-005: when the enterprise overlay is present, its migrations join the
  // core directory as a knex array. Ordering across directories is global by
  // filename timestamp (single knex_migrations table), which is why the
  // overlay repo carries a collision gate. Both paths are absolute so the CLI
  // (cwd apps/api) and the runtime plugin agree.
  const coreMigrations = fileURLToPath(new URL('../../migrations', import.meta.url));
  const eeDir = resolveEeDir(config);
  const eeMigrations = eeDir ? path.join(eeDir, 'server', 'migrations') : null;
  const directory =
    eeMigrations && existsSync(eeMigrations) ? [coreMigrations, eeMigrations] : coreMigrations;

  return {
    client: 'mysql2',
    connection: {
      host: config.database.host,
      port: config.database.port,
      user: config.database.user,
      password: config.database.password,
      database: config.database.name,
      charset: 'utf8mb4',
      timezone: 'Z',
      supportBigNumbers: true,
      bigNumberStrings: false,
    },
    pool: { min: 0, max: 10 },
    migrations: {
      directory,
      tableName: 'knex_migrations',
    },
    // Read by migrations through `resolveCollation` (src/db/collation.js) —
    // knex exposes its config as `knex.client.config`, which is how a migration
    // gets a deployment setting without reading the environment itself
    // (AGENTS.md §4: config.js owns env). Null = auto-detect MySQL vs MariaDB.
    alliswellCollation: config.database.collation,
  };
}
