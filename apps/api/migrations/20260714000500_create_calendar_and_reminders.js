/**
 * OPH-015 — calendar_accounts, calendar_event_links, reminders.
 * Calendar mapping model per BLUEPRINT §4.7/§4.8/§7; reminder lifecycle per §4.9.
 * OAuth token columns hold AES-256-GCM ciphertext (never plaintext — SECURITY.md).
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

const PROVIDERS = ['google', 'apple_eventkit', 'apple_caldav', 'local_device'];

function base(table) {
  table.charset(CHARSET);
  table.collate(COLLATION);
  table.specificType('id', 'char(26)').primary();
}

function timestamps(knex, table, { softDelete = true } = {}) {
  table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  if (softDelete) table.datetime('deleted_at', { precision: 3 }).nullable();
}

export async function up(knex) {
  await knex.schema.createTable('calendar_accounts', (t) => {
    base(t);
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.enu('provider', PROVIDERS).notNullable();
    t.string('provider_account_id', 255).notNullable();
    t.text('encrypted_access_token').nullable();
    t.text('encrypted_refresh_token').nullable();
    t.datetime('token_expires_at', { precision: 3 }).nullable();
    t.string('sync_token', 500).nullable();
    t.string('webhook_channel_id', 255).nullable();
    t.string('webhook_resource_id', 255).nullable();
    t.datetime('webhook_expires_at', { precision: 3 }).nullable();
    t.string('default_calendar_id', 255).nullable();
    t.enu('status', ['active', 'error', 'revoked', 'disconnected'])
      .notNullable()
      .defaultTo('active');
    t.datetime('last_synced_at', { precision: 3 }).nullable();
    t.text('last_error').nullable();
    timestamps(knex, t);
    t.unique(['user_id', 'provider', 'provider_account_id'], {
      indexName: 'uq_calendar_accounts_identity',
    });
    t.index(['workspace_id'], 'idx_calendar_accounts_workspace');
    t.foreign('user_id', 'fk_ca_user').references('users.id').onDelete('CASCADE');
    t.foreign('workspace_id', 'fk_ca_workspace').references('workspaces.id').onDelete('CASCADE');
  });

  await knex.schema.createTable('calendar_event_links', (t) => {
    base(t);
    t.specificType('task_id', 'char(26)').notNullable();
    t.specificType('calendar_account_id', 'char(26)').notNullable();
    t.enu('provider', PROVIDERS).notNullable();
    t.string('provider_calendar_id', 255).notNullable();
    t.string('provider_event_id', 255).notNullable();
    t.string('provider_event_uid', 255).nullable();
    t.string('etag', 255).nullable();
    t.datetime('last_provider_updated_at', { precision: 3 }).nullable();
    t.datetime('last_local_updated_at', { precision: 3 }).nullable();
    t.enu('sync_direction', ['both', 'push_only', 'pull_only']).notNullable().defaultTo('both');
    t.enu('conflict_status', [
      'none',
      'local_changed_provider_changed',
      'provider_deleted_local_exists',
      'local_deleted_provider_exists',
      'time_conflict',
    ])
      .notNullable()
      .defaultTo('none');
    timestamps(knex, t, { softDelete: false });
    t.unique(['calendar_account_id', 'provider_event_id'], {
      indexName: 'uq_cel_account_event',
    });
    t.index(['task_id'], 'idx_cel_task');
    t.foreign('task_id', 'fk_cel_task').references('tasks.id').onDelete('CASCADE');
    t.foreign('calendar_account_id', 'fk_cel_account')
      .references('calendar_accounts.id')
      .onDelete('CASCADE');
  });

  await knex.schema.createTable('reminders', (t) => {
    base(t);
    t.specificType('task_id', 'char(26)').notNullable();
    t.datetime('remind_at', { precision: 3 }).notNullable();
    t.string('timezone', 64).notNullable().defaultTo('Europe/Istanbul');
    t.enu('alarm_level', ['normal', 'urgent']).notNullable().defaultTo('normal');
    t.boolean('requires_acknowledgement').notNullable().defaultTo(false);
    t.enu('status', ['scheduled', 'delivered', 'acknowledged', 'snoozed', 'cancelled', 'completed'])
      .notNullable()
      .defaultTo('scheduled');
    t.datetime('delivered_at', { precision: 3 }).nullable();
    t.datetime('acknowledged_at', { precision: 3 }).nullable();
    t.datetime('snoozed_until', { precision: 3 }).nullable();
    t.text('repeat_rule').nullable();
    timestamps(knex, t);
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.index(['status', 'remind_at'], 'idx_reminders_due');
    t.index(['task_id'], 'idx_reminders_task');
    t.foreign('task_id', 'fk_reminders_task').references('tasks.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('reminders');
  await knex.schema.dropTableIfExists('calendar_event_links');
  await knex.schema.dropTableIfExists('calendar_accounts');
}
