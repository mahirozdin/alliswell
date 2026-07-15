/**
 * OPH-082 — the user's OWN calendar events, cached for display (ADR-0008).
 *
 * Not to be confused with `calendar_event_links`: that maps OUR tasks to events
 * we created. This is the other half of the feed — the meetings and
 * appointments AllisWell did not create and must never edit. They are a
 * read-only cache of someone else's system (hence CASCADE from the account:
 * disconnect, and they go).
 *
 * `external_sync_token` is a SECOND cursor on purpose (ADR-0008 §3): the task
 * mirror needs `singleEvents=false` to see recurrence masters, this feed needs
 * `singleEvents=true` to see instances, and one Google sync token cannot carry
 * both parameter sets.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

export async function up(knex) {
  await knex.schema.alterTable('calendar_accounts', (t) => {
    t.string('external_sync_token', 500).nullable();
  });

  await knex.schema.createTable('calendar_external_events', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('calendar_account_id', 'char(26)').notNullable();
    t.enu('provider', ['google', 'apple_eventkit', 'apple_caldav', 'local_device']).notNullable();
    t.string('provider_calendar_id', 255).notNullable();
    t.string('provider_event_id', 255).notNullable();

    t.string('summary', 500).nullable(); // Google allows untitled events
    t.string('location', 500).nullable();
    t.datetime('starts_at', { precision: 3 }).notNullable();
    t.datetime('ends_at', { precision: 3 }).notNullable();
    t.boolean('is_all_day').notNullable().defaultTo(false);
    // `transparency: transparent` — on the calendar but not really busy.
    t.boolean('is_busy').notNullable().defaultTo(true);
    t.string('html_link', 1000).nullable(); // "open in Google Calendar"

    t.string('etag', 255).nullable();
    t.datetime('provider_updated_at', { precision: 3 }).nullable();
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('deleted_at', { precision: 3 }).nullable();

    t.unique(['calendar_account_id', 'provider_event_id'], { indexName: 'uq_cee_account_event' });
    // The calendar view asks "what is in this range for this workspace".
    t.index(['workspace_id', 'starts_at'], 'idx_cee_workspace_start');
    t.foreign('workspace_id', 'fk_cee_workspace').references('workspaces.id').onDelete('CASCADE');
    t.foreign('calendar_account_id', 'fk_cee_account')
      .references('calendar_accounts.id')
      .onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('calendar_external_events');
  await knex.schema.alterTable('calendar_accounts', (t) => {
    t.dropColumn('external_sync_token');
  });
}
