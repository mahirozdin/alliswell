/**
 * OPH-215 — the AI foundation (Epic 20, ADR-0019, BLUEPRINT §4.13, AI.md §2).
 *
 * Three tables, none of them sync entities:
 *
 * `ai_connections` — one BYOK/instance-env provider connection per user per
 * workspace. Key material must never reach the drift replica, so this rides
 * REST only (settings screens read it directly). `encrypted_key` uses the
 * ADR-0006 AES-256-GCM wire format under the new AI_TOKEN_KEY; `key_last4` is
 * computed from the plaintext at write time so serializers never touch the
 * ciphertext. `auth_mode = 'oauth_subscription'` is a RESERVED value: every
 * provider forbids consumer-subscription auth for third parties today
 * (AI.md §1), and reserving the enum means a sanctioned program later is a
 * new auth mode, not a schema change.
 *
 * `ai_usage_events` — per-request accounting (tokens/model/duration), never
 * content (AI.md §2). Append-only: no updated_at, no soft delete.
 *
 * `ai_action_log` — AI-proposed + user-confirmed mutations (the Epic 16
 * alarm-log lesson: evidence, not memory). `accepted` is NULL until the user
 * decides; `entity_refs` is filled on accept with the created entity ids.
 * `proposal` is polymorphic JSON and the referenced entities live in other
 * tables, so it carries no FK to them (the quick_links precedent).
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export const AI_PROVIDERS = ['anthropic', 'openai', 'gemini', 'openrouter', 'ollama'];

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('ai_connections', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    t.enu('provider', AI_PROVIDERS).notNullable();
    t.enu('auth_mode', ['api_key', 'instance_env', 'oauth_subscription'])
      .notNullable()
      .defaultTo('api_key');
    t.text('encrypted_key').nullable();
    t.string('key_last4', 4).nullable();
    t.string('base_url', 2048).nullable();
    t.string('default_chat_model', 128).nullable();
    t.string('default_fast_model', 128).nullable();
    t.enu('status', ['active', 'error']).notNullable().defaultTo('active');
    t.datetime('last_used_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('deleted_at', { precision: 3 }).nullable();

    // One connection per provider per user+workspace: the settings UI is a
    // per-provider list, and "which connection does the bubble use" must never
    // be ambiguous. Deletes are soft AND the tuple stays occupied — a re-add
    // revives the tombstone (routes/ai.js), the calendar_accounts precedent.
    t.unique(['workspace_id', 'user_id', 'provider'], {
      indexName: 'uq_ai_connections_user_provider',
    });
    t.index(['workspace_id', 'user_id', 'deleted_at'], 'idx_ai_connections_workspace_user');
    t.foreign('workspace_id', 'fk_ai_connections_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_ai_connections_user').references('users.id').onDelete('CASCADE');
  });

  await knex.schema.createTable('ai_usage_events', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    // SET NULL, not CASCADE: the usage meter must survive a disconnect, which
    // is why `provider` is denormalized alongside.
    t.specificType('connection_id', 'char(26)').nullable();
    t.enu('provider', AI_PROVIDERS).notNullable();
    t.enu('kind', ['chat', 'extract', 'transcribe', 'mcp']).notNullable();
    t.string('model', 128).notNullable();
    // NULL = the provider did not report it; accounting never blocks a reply.
    t.integer('input_tokens').unsigned().nullable();
    t.integer('output_tokens').unsigned().nullable();
    t.integer('duration_ms').unsigned().nullable();
    t.specificType('request_id', 'char(26)').nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    // The monthly meter (OPH-220) and the instance-env daily-cap recovery scan.
    t.index(['workspace_id', 'user_id', 'created_at'], 'idx_ai_usage_user_time');
    t.foreign('workspace_id', 'fk_ai_usage_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_ai_usage_user').references('users.id').onDelete('CASCADE');
    t.foreign('connection_id', 'fk_ai_usage_connection')
      .references('ai_connections.id')
      .onDelete('SET NULL');
  });

  await knex.schema.createTable('ai_action_log', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    // TASKS names four sources; quick_add and voice are the two extract
    // surfaces the schema itself distinguishes. Widening an ENUM later is a
    // migration, so the full known surface list ships now.
    t.enu('source', ['bubble', 'share', 'chat', 'mcp', 'quick_add', 'voice']).notNullable();
    t.specificType('request_id', 'char(26)').nullable();
    t.json('proposal').notNullable();
    t.boolean('accepted').nullable();
    t.json('entity_refs').nullable();
    t.datetime('decided_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.index(['workspace_id', 'user_id', 'created_at'], 'idx_ai_action_user_time');
    t.foreign('workspace_id', 'fk_ai_action_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_ai_action_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('ai_action_log');
  await knex.schema.dropTableIfExists('ai_usage_events');
  await knex.schema.dropTableIfExists('ai_connections');
}
