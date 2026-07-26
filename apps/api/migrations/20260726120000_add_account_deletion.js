/**
 * Account deletion with a grace period (App Store guideline 5.1.1(v) and
 * Google Play's account-deletion policy both require in-app deletion).
 *
 * The request is a SCHEDULE, not an immediate erase: `deletion_scheduled_at`
 * is the instant after which the sweep purges the account for good. Until then
 * the account keeps working, so signing back in and cancelling undoes it — the
 * standard protection against a rage-tap or a stolen phone.
 *
 * Migrations are append-only (AGENTS.md rule 8) — never edit this file after it
 * has run.
 */

export async function up(knex) {
  await knex.schema.alterTable('users', (t) => {
    t.datetime('deletion_scheduled_at', { precision: 3 }).nullable();
    // The sweep asks "whose grace period has expired?" — one index answers it
    // without scanning the table.
    t.index(['deletion_scheduled_at'], 'idx_users_deletion_scheduled');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('users', (t) => {
    t.dropIndex(['deletion_scheduled_at'], 'idx_users_deletion_scheduled');
    t.dropColumn('deletion_scheduled_at');
  });
}
