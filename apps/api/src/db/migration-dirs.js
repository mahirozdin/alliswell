import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/**
 * The core migration directory, absolute. One definition for the two readers
 * that need it: the knex configuration (src/db/knexconfig.js) and the
 * extension loader's ledger check (src/lib/ee.js, OPH-343).
 */
export function coreMigrationsDir() {
  return fileURLToPath(new URL('../../migrations', import.meta.url));
}

/** The migration file names in `dir`, as knex records them in its ledger. */
export function migrationNamesIn(dir) {
  return readdirSync(dir).filter((name) => /\.(c|m)?js$/.test(name));
}
