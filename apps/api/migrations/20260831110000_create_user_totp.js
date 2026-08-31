/**
 * OPH-283 — the second factor, and the codes that survive losing the phone.
 *
 * ── WHY A TABLE AND NOT COLUMNS ON `users` ────────────────────────────────
 *
 * The admin realm keeps its TOTP in columns on its own row, and for one table
 * with one reader that is fine. `users` is different: it is read by a dozen
 * paths, some of which select `*` and hand the row onward. A secret that can
 * be computed with does not belong in a row that travels — so it lives in a
 * table nothing selects by accident, joined only where a factor is actually
 * being checked.
 *
 * ── THE SECRET IS ENCRYPTED, THE RECOVERY CODES ARE HASHED ────────────────
 *
 * Different obligations, so different treatments, and neither is a preference:
 *
 *   • The TOTP secret must be READ BACK to compute a code, so it cannot be
 *     hashed. It is encrypted at rest under its own key (ADR-0006's pattern,
 *     `AUTH_TOTP_KEY`) — its own, because a calendar-key or AI-key compromise
 *     must not hand somebody every second factor in the install.
 *   • A recovery code is only ever COMPARED, so it is stored as a keyed
 *     digest, exactly like `api_keys.key_hash` and `refresh_tokens.token_hash`.
 *     A database dump can neither read nor forge one.
 *
 * ── `enrolled_at` NULL IS A REAL STATE, NOT A MISSING VALUE ───────────────
 *
 * Enrolment is two steps: the server mints a secret and shows it, then the
 * person proves their authenticator computed the same code. Between those the
 * row exists with `enrolled_at` NULL, and a NULL row protects nothing and
 * blocks nothing — sign-in ignores it. Without the staged state, either the
 * secret is held in a session (which the API does not have) or a person who
 * closes the tab mid-setup is locked out by a factor they never confirmed.
 *
 * ── `last_step` IS THE REPLAY REFUSAL ─────────────────────────────────────
 *
 * A TOTP code is a bearer credential for its whole window. Without recording
 * the step it matched and refusing anything at or below it, a code read over
 * somebody's shoulder works again for up to ninety seconds.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('user_totp', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    // `v1:<iv>:<tag>:<ciphertext>` — the wire format lib/crypto.js writes.
    t.text('encrypted_secret').notNullable();
    // NULL until the person proves their authenticator agrees. See above.
    t.datetime('enrolled_at', { precision: 3 }).nullable();
    // The highest step already spent. Unsigned big: steps are seconds/30 and
    // an int would run out in 2038 for no reason.
    t.bigInteger('last_step').unsigned().nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    // One factor per person. Re-enrolling replaces the row rather than adding
    // a second secret nobody could tell from the first.
    t.unique(['user_id'], { indexName: 'uq_user_totp_user' });
    t.foreign('user_id', 'fk_user_totp_user').references('users.id').onDelete('CASCADE');
  });

  await knex.schema.createTable('user_totp_recovery_codes', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    // HMAC-SHA256 hex digest — 64 chars, exactly like `api_keys.key_hash`.
    t.specificType('code_hash', 'char(64)').notNullable();
    // Single use is the whole point: a code that still works after it was
    // used is a password somebody wrote on a card.
    t.datetime('used_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    // One digest is one code, forever — a regenerated set cannot collide with
    // a spent one and quietly resurrect it.
    t.unique(['code_hash'], { indexName: 'uq_user_totp_recovery_hash' });
    // "How many has this person got left?" — the only other read.
    t.index(['user_id', 'used_at'], 'idx_user_totp_recovery_user');
    t.foreign('user_id', 'fk_user_totp_recovery_user').references('users.id').onDelete('CASCADE');
  });

  // When the password last changed. Needed by anything that wants to say "this
  // one is old" — and NULL is honest for every account that predates this
  // column, including the ones that have no password at all.
  await knex.schema.alterTable('users', (t) => {
    t.datetime('password_changed_at', { precision: 3 }).nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('users', (t) => {
    t.dropColumn('password_changed_at');
  });
  await knex.schema.dropTableIfExists('user_totp_recovery_codes');
  await knex.schema.dropTableIfExists('user_totp');
}
