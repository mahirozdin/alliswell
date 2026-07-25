/**
 * The utf8mb4 collation the schema is created with — resolved against the
 * SERVER, because MySQL and MariaDB do not share one (ADR-0004 conventions).
 *
 * - **MySQL 8.0+** has `utf8mb4_0900_ai_ci` (UCA 9.0). It is what this project
 *   was built and tested on, so it stays the preferred choice.
 * - **MariaDB** has no `*_0900_*` collation at all — creating a table with one
 *   fails outright ("Unknown collation"). Its universal equivalent is
 *   `utf8mb4_unicode_ci`, which MySQL also has, so it is the safe fallback.
 *
 * Both are accent- and case-insensitive, which is all the schema relies on
 * (e.g. `uq_users_email`, `uq_tags_workspace_slug`). Search does NOT depend on
 * this: Turkish folding is app-owned precisely because neither engine folds
 * `ı→i` (ADR-0013), so the collation choice cannot change search results.
 *
 * A deployment can pin one explicitly with `DATABASE_COLLATION` (e.g.
 * `utf8mb4_uca1400_ai_ci` on MariaDB 10.10+); otherwise this auto-detects, so
 * self-hosters need no database knowledge at all.
 */

export const CHARSET = 'utf8mb4';

/** MySQL 8.0+ (UCA 9.0) — the collation this project is developed against. */
export const PREFERRED_COLLATION = 'utf8mb4_0900_ai_ci';

/** Present on every MySQL AND MariaDB worth deploying on. */
export const FALLBACK_COLLATION = 'utf8mb4_unicode_ci';

/** One probe per knex instance — nine migrations must not mean nine round trips. */
const resolved = new WeakMap();

/**
 * The collation to create tables with on THIS server.
 *
 * Order: an explicit `DATABASE_COLLATION` (carried on the knex config by
 * `buildKnexConfig`, already validated in config.js) → the preferred MySQL 8
 * collation when the server supports it → the universal fallback.
 *
 * @param {import('knex').Knex} knex
 * @returns {Promise<string>}
 */
export async function resolveCollation(knex) {
  const pinned = knex.client?.config?.alliswellCollation;
  if (pinned) return pinned;

  if (resolved.has(knex)) return resolved.get(knex);

  let collation = FALLBACK_COLLATION;
  try {
    // Works on both engines; MariaDB simply returns no rows for a *_0900_* name.
    const [rows] = await knex.raw('SHOW COLLATION LIKE ?', [PREFERRED_COLLATION]);
    if (Array.isArray(rows) && rows.length > 0) collation = PREFERRED_COLLATION;
  } catch {
    // Probe failed (odd permissions, exotic proxy): the fallback exists
    // everywhere, so degrade to it rather than failing the migration.
  }
  resolved.set(knex, collation);
  return collation;
}
