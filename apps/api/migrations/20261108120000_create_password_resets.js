/**
 * OPH-406 — "I forgot my password" (ADR-0064).
 *
 * One row per reset link. The link carries an opaque random token; this table
 * keeps only its keyed digest (`lib/tokens.js` `hashPasswordResetToken`), the
 * same storage `refresh_tokens.token_hash` and `api_keys.key_hash` use — a
 * database dump can neither read a live link nor forge one.
 *
 * ── WHY ROWS STAY AFTER THEY ARE SPENT ────────────────────────────────────
 *
 * `used_at` is the single-use marker and `expires_at` the lifetime. A spent or
 * expired row is not deleted at once because the per-account throttle counts
 * the links issued in the last hour from these rows: deleting them would let
 * somebody fill a person's mailbox by asking again. Old rows go with the
 * account (CASCADE); the table stays small because each account can only add
 * a handful an hour.
 *
 * `source` says who issued the link — `email` (the forgot form) or `admin`
 * (the server-side command for an install with no outgoing mail). The admin
 * link lives longer and is never counted against the person's throttle.
 *
 * Migrations are append-only (AGENTS.md I-08).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('password_resets', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    // HMAC-SHA256 hex digest — 64 chars, like `refresh_tokens.token_hash`.
    t.specificType('token_hash', 'char(64)').notNullable();
    t.string('source', 16).notNullable().defaultTo('email');
    t.datetime('expires_at', { precision: 3 }).notNullable();
    // NULL until the link sets a password. A link that works twice is a
    // password somebody left in an inbox.
    t.datetime('used_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.unique(['token_hash'], { indexName: 'uq_password_resets_token' });
    // The throttle's question: this person's links since an hour ago.
    t.index(['user_id', 'created_at'], 'idx_password_resets_user_created');
    t.foreign('user_id', 'fk_password_resets_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('password_resets');
}
