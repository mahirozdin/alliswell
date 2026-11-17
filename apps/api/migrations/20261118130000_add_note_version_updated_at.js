/**
 * OPH-494 — when a version's body was LAST written.
 *
 * A same-device editing session rolls into one version row (ADR-0031 §4): the
 * row keeps its `created_at` — when the session started — and takes each newer
 * body. History could therefore only say "14:02" for a body last typed at
 * 14:09, and the conflict banner could not say exactly when the two sides were
 * written. `updated_at` is set on insert and on every roll-up.
 *
 * Nullable and NOT backfilled: an old row's last write is unknown, and the API
 * answers `created_at` for it, which is what history showed until now.
 */

export async function up(knex) {
  await knex.schema.alterTable('note_versions', (table) => {
    table.datetime('updated_at', { precision: 3 }).nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('note_versions', (table) => {
    table.dropColumn('updated_at');
  });
}
