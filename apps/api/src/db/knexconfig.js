/**
 * Shared knex configuration used by both the runtime plugin (src/plugins/mysql.js)
 * and the knex CLI (knexfile.js). Timestamps are stored as UTC (`timezone: 'Z'`).
 *
 * @param {ReturnType<import('../config.js')['loadConfig']>} config
 */
export function buildKnexConfig(config) {
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
      directory: './migrations',
      tableName: 'knex_migrations',
    },
  };
}
