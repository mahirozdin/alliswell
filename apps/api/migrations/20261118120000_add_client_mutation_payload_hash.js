/**
 * OPH-487 (ADR-0072) — what a recorded client mutation SAID, not only its id.
 *
 * `client_mutations` made a push idempotent by `(client_id,
 * client_mutation_id)` alone: a resend got the first answer back. An installed
 * client could rewrite an outbox row it had already sent (coalescing a newer
 * note body into it) and resend it under the same id — the server replayed the
 * old answer and the newer text was lost without a trace.
 *
 * `payload_hash` is a SHA-256 of the mutation's operation, entity, patch and
 * base. A resend with the same hash replays as before; a different hash is a
 * new write that reused an id, and is processed as one.
 *
 * Nullable and NOT backfilled: rows recorded before this column cannot be
 * compared, so they keep today's behaviour (replay). No collation is pinned:
 * CHAR(64) takes the table's.
 */

export async function up(knex) {
  await knex.schema.alterTable('client_mutations', (table) => {
    table.specificType('payload_hash', 'char(64)').nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('client_mutations', (table) => {
    table.dropColumn('payload_hash');
  });
}
