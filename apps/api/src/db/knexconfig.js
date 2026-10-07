import { existsSync } from 'node:fs';
import path from 'node:path';

import { resolveEeDir } from '../lib/ee.js';
import { coreMigrationsDir } from './migration-dirs.js';

/**
 * `timezone: 'Z'` only tells mysql2 how to write and read JS Dates; a column
 * default (`CURRENT_TIMESTAMP(3)`, `ON UPDATE`) and every `NOW()` are computed by
 * the server in the session's time zone. A MySQL whose `time_zone` is `SYSTEM` on
 * a non-UTC host stamps local wall time that the API then reads back as UTC — an
 * `updated_at` hours in the future, which sync's last-write-wins treats as newer
 * than any device. Every pooled connection is pinned to UTC before its first query.
 *
 * @param {{ query: Function }} conn a mysql2 connection
 * @param {(err: Error | null, conn: unknown) => void} done
 */
export function pinSessionToUtc(conn, done) {
  conn.query("SET time_zone = '+00:00'", (err) => done(err ?? null, conn));
}

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
  const coreMigrations = coreMigrationsDir();
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
    pool: { min: 0, max: 10, afterCreate: pinSessionToUtc },
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
