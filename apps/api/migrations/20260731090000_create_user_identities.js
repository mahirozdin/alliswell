/**
 * Epic 21 — Sign in with Google / Apple (ADR-0026).
 *
 * One row per external identity a user has linked. The user still lives in
 * `users`; this table only records "the Google account with subject X, or the
 * Apple account with subject Y, is that user".
 *
 * **Why a separate table rather than columns on `users`.** One person legitimately
 * has several: the same account may be reachable through Google *and* Apple, and
 * they must resolve to one AllisWell user rather than to two half-populated ones.
 * Columns would cap it at one provider and force a schema change per provider added.
 *
 * **`subject` is the identity, not `email`.** Apple sends the address only on the
 * FIRST authorisation, and only if the user agreed to share it — every later sign-in
 * carries `sub` and nothing else. An account keyed on e-mail would therefore lose
 * Apple users the second time they signed in. `email` is stored for display and for
 * first-time linking, and is explicitly allowed to be null and to go stale.
 *
 * **Uniqueness is (provider, subject).** Not `subject` alone: the providers mint
 * subjects in their own namespaces and there is no guarantee they never collide.
 *
 * `password_hash` on `users` has been nullable since the first migration, so an
 * account created purely through a provider needs no schema change — it simply has
 * no password until the user sets one.
 *
 * **Column types are not incidental.** `char(26)` with an explicit charset and
 * collation, exactly like every other table here: a `varchar` id, or one that
 * inherits a different collation, makes the foreign key to `users.id`
 * "incorrectly formed" (errno 150) — which MySQL 8 tolerated and MariaDB caught
 * in CI.
 */
import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

// Resolved against the live server in up(): MySQL 8 keeps utf8mb4_0900_ai_ci,
// MariaDB has no *_0900_* collation and gets utf8mb4_unicode_ci instead.
let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);
  await knex.schema.createTable('user_identities', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    // 'google' | 'apple'. A string rather than an enum so adding a provider is a
    // deploy, not a migration with a table lock.
    t.string('provider', 32).notNullable();
    // The provider's own subject claim. Apple's is 44 chars; Google's is 21 and
    // documented as growing. 255 is room to spare, not a guess at the maximum.
    t.string('subject', 255).notNullable();
    // What the provider told us at link time. Display and first-match only —
    // never an authorisation input, and never assumed current.
    t.string('email', 255).nullable();
    t.boolean('email_verified').notNullable().defaultTo(false);
    t.datetime('last_used_at', { precision: 3 }).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.foreign('user_id').references('users.id').onDelete('CASCADE');
    t.unique(['provider', 'subject'], { indexName: 'uq_user_identities_provider_subject' });
    t.index(['user_id'], 'ix_user_identities_user');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('user_identities');
}
