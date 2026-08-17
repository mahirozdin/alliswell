/**
 * OPH-264 — API keys (ADR-0032, issue #3).
 *
 * The `refresh_tokens` / `oauth_tokens` shape once more: the client keeps the
 * secret, we keep only its keyed digest, so a database dump can neither read
 * nor forge a working key. `key_prefix` is the one part stored in the clear —
 * twelve characters is enough for a person to recognise which key a row is,
 * and useless for authenticating with.
 *
 * A key belongs to a user AND a workspace: the workspace binding is the blast
 * radius (ADR-0032 §3), so it is a column, not a scope string to be parsed.
 * No `deleted_at`: revocation is `revoked_at` and it is permanent — a revoked
 * key row stays as evidence, and its digest stays unique so the same secret
 * can never be re-registered.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('api_keys', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('workspace_id', 'char(26)').notNullable();
    // What the user called it ("Home Assistant", "yedekleme script'i").
    t.string('name', 100).notNullable();
    // HMAC-SHA256 hex digest — 64 chars, exactly like refresh_tokens.
    t.specificType('key_hash', 'char(64)').notNullable();
    // First 12 characters of the secret: recognition, never authentication.
    t.string('key_prefix', 16).notNullable();
    // NULL means "no expiry" — the user chose an open-ended key.
    t.datetime('expires_at', { precision: 3 }).nullable();
    t.datetime('revoked_at', { precision: 3 }).nullable();
    // Throttled to ~1/min (ADR-0032 §6): "can I revoke this?" needs a date,
    // not a counter.
    t.datetime('last_used_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    // The authentication lookup, and the guarantee that one secret is one row.
    t.unique(['key_hash'], { indexName: 'uq_api_keys_hash' });
    // The list screen: this user's keys in this workspace.
    t.index(['workspace_id', 'user_id'], 'idx_api_keys_workspace_user');
    t.foreign('user_id', 'fk_api_keys_user').references('users.id').onDelete('CASCADE');
    t.foreign('workspace_id', 'fk_api_keys_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('api_keys');
}
