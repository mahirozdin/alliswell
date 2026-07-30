/**
 * OPH-218 — the MCP track's OAuth 2.1 authorization server + write-idempotency
 * ledger (Epic 20 Track A, ADR-0022).
 *
 * `oauth_clients` — dynamically registered clients (RFC 7591). The ULID row id
 * IS the client_id. `redirect_uris` is JSON (1–10 exact-match strings);
 * `client_secret_hash` is a keyed digest, stored only when a client registers
 * a secret-bearing auth method (default is 'none' — public client + PKCE).
 *
 * `oauth_codes` — single-use authorization codes: keyed hash, 60 s TTL,
 * consumed_at claimed atomically; a consumed code presented again revokes the
 * tokens it minted (OAuth 2.1 §4.1.2).
 *
 * `oauth_tokens` — opaque access/refresh tokens as keyed digests (the
 * refresh_tokens pattern) with `family_id` rotation lineage: refresh reuse
 * revokes the whole family, access tokens included.
 *
 * `mcp_mutations` — the create_task idempotency ledger. Its own table, NOT
 * client_mutations: those keys are `char(26)` sync-protocol ULIDs, while an
 * MCP idempotencyKey is free-form host-side text.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('oauth_clients', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.string('name', 255).nullable();
    t.json('redirect_uris').notNullable();
    t.enu('token_endpoint_auth_method', ['none', 'client_secret_post', 'client_secret_basic'])
      .notNullable()
      .defaultTo('none');
    t.specificType('client_secret_hash', 'char(64)').nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('last_used_at', { precision: 3 }).nullable();
  });

  await knex.schema.createTable('oauth_codes', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('code_hash', 'char(64)').notNullable();
    t.specificType('client_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.string('scope', 100).notNullable();
    t.string('redirect_uri', 500).notNullable();
    t.string('code_challenge', 128).notNullable();
    t.string('resource', 500).nullable();
    t.datetime('expires_at', { precision: 3 }).notNullable();
    t.datetime('consumed_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.unique(['code_hash'], { indexName: 'uq_oauth_codes_hash' });
    t.foreign('client_id', 'fk_oauth_codes_client')
      .references('oauth_clients.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_oauth_codes_user').references('users.id').onDelete('CASCADE');
    t.foreign('workspace_id', 'fk_oauth_codes_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
  });

  await knex.schema.createTable('oauth_tokens', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.enu('kind', ['access', 'refresh']).notNullable();
    t.specificType('token_hash', 'char(64)').notNullable();
    t.specificType('client_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.string('scope', 100).notNullable();
    t.specificType('family_id', 'char(26)').notNullable();
    t.datetime('expires_at', { precision: 3 }).notNullable();
    t.datetime('rotated_at', { precision: 3 }).nullable();
    t.datetime('revoked_at', { precision: 3 }).nullable();
    t.datetime('last_used_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.unique(['token_hash'], { indexName: 'uq_oauth_tokens_hash' });
    t.index(['family_id'], 'idx_oauth_tokens_family');
    t.index(['user_id'], 'idx_oauth_tokens_user');
    t.foreign('client_id', 'fk_oauth_tokens_client')
      .references('oauth_clients.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_oauth_tokens_user').references('users.id').onDelete('CASCADE');
    t.foreign('workspace_id', 'fk_oauth_tokens_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
  });

  await knex.schema.createTable('mcp_mutations', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('client_id', 'char(26)').nullable();
    t.string('idempotency_key', 64).notNullable();
    t.string('entity_type', 32).notNullable();
    t.specificType('entity_id', 'char(26)').notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.unique(['workspace_id', 'user_id', 'idempotency_key'], { indexName: 'uq_mcp_mutation' });
    t.foreign('workspace_id', 'fk_mcp_mutations_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_mcp_mutations_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('mcp_mutations');
  await knex.schema.dropTableIfExists('oauth_tokens');
  await knex.schema.dropTableIfExists('oauth_codes');
  await knex.schema.dropTableIfExists('oauth_clients');
}
