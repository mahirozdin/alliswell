/**
 * OPH-309 — a device says which language it is in.
 *
 * The visible fallback push (Epic 30) carries identifiers and the NAME of a
 * fixed message, never the message (ADR-0038). Something still has to choose
 * which language that fixed string is rendered in, and `users.locale` is the
 * wrong answer: the account is one thing, the install is another. A phone set
 * to Turkish and a work laptop set to English belong to the same person.
 *
 * Nullable on purpose. A device that has not said is not a device to guess
 * about — the sender falls back to the account, and the column being empty
 * says honestly that nobody told us.
 *
 * Deliberately NOT an enum. `assets/i18n/` is where the shipped languages are
 * decided, and an enum here would make adding one a schema migration. 16
 * characters holds any BCP-47 tag we would ever ship (`pt-BR`, `zh-Hant-TW`).
 */
export async function up(knex) {
  await knex.schema.alterTable('notification_devices', (table) => {
    table.string('locale', 16).nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('notification_devices', (table) => {
    table.dropColumn('locale');
  });
}
