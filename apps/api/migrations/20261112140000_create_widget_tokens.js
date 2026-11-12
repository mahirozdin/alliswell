/**
 * OPH-458 (#50, ADR-0070) — the read-only widget token.
 *
 * One row per (user, notification device): the home-screen widget's own
 * credential, opened only by `app.authenticateWidget` for the widget snapshot.
 * The raw `aww_…` value leaves the server once, in the mint response; this
 * table keeps only its keyed digest (`lib/tokens.js` `hashWidgetToken`), the
 * storage `api_keys.key_hash` and `refresh_tokens.token_hash` use.
 *
 * `UNIQUE(user_id, device_id)` is the "one live token per device" rule: a
 * re-mint overwrites the row's digest in place, so the previous token stops
 * matching anything at that instant.
 *
 * `session_family_id` names the session (`refresh_tokens.family_id`) that
 * minted the token; the token is only good while that family has a live row.
 * No foreign key to `refresh_tokens` (a family is not a row) and none to
 * `notification_devices` (a device row is deleted on sign-out while this row
 * stays as a revoked record; `authenticateWidget` checks the device exists).
 * The user FK cascades: deleting an account takes its widget tokens with it.
 *
 * No push columns: WidgetKit push is not in this round (ADR-0070 §1).
 * No collation is pinned (MariaDB in production): `resolveCollation`.
 *
 * Migrations are append-only (AGENTS.md I-08).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('widget_tokens', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('device_id', 'char(26)').notNullable();
    t.specificType('session_family_id', 'char(26)').notNullable();
    // HMAC-SHA256 hex digest — 64 chars, like `api_keys.key_hash`.
    t.specificType('token_hash', 'char(64)').notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('expires_at', { precision: 3 }).notNullable();
    // Throttled to about once a minute, like `api_keys.last_used_at`.
    t.datetime('last_used_at', { precision: 3 }).nullable();
    t.datetime('revoked_at', { precision: 3 }).nullable();

    t.unique(['token_hash'], { indexName: 'uq_widget_tokens_token' });
    t.unique(['user_id', 'device_id'], { indexName: 'uq_widget_tokens_user_device' });
    // Revocation by session family (sign-out, session revoke, reuse).
    t.index(['user_id', 'session_family_id'], 'idx_widget_tokens_user_family');
    t.foreign('user_id', 'fk_widget_tokens_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('widget_tokens');
}
