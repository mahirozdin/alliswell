/**
 * OPH-210 — the calendar mirror stops being opt-in (ADR-0021, BLUEPRINT §7.1).
 *
 * `tasks.calendar_mirror_enabled` cannot become the "do not mirror" flag the
 * new rule needs: it defaults to FALSE, so every task that already exists would
 * read as suppressed the moment the meaning flipped. So suppression gets its
 * own nullable column, and the old one is left where it is — dead, but honest,
 * and append-only (AGENTS.md rule 8).
 *
 * Who writes it: only `src/lib/inbound.js`, when the user deletes one of our
 * events inside Google. That is the single case where "no event" is the user's
 * wish rather than our derivation, and without a place to record it we would
 * re-create the event they just removed, forever.
 */

export async function up(knex) {
  await knex.schema.alterTable('tasks', (t) => {
    t.datetime('calendar_mirror_suppressed_at', { precision: 3 }).nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('tasks', (t) => {
    t.dropColumn('calendar_mirror_suppressed_at');
  });
}
