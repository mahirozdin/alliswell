/**
 * ADR-0047 — OAuth clients identified by a metadata document URL (CIMD).
 *
 * A metadata client names itself by an https URL, but every token table keys
 * its client by the 26-character `oauth_clients.id`. So the URL gets a column
 * of its own and maps to an ordinary ULID row on first sight: codes and tokens
 * keep their foreign keys, and nothing downstream of /oauth/authorize can tell
 * a metadata client from a registered one.
 *
 *   - `metadata_url`        — the client_id as the client sends it; unique, so
 *                              two first authorizations racing each other end
 *                              up on one row. NULL for registered clients.
 *   - `metadata_expires_at` — when the cached redirect_uris and name must be
 *                              fetched again (the document's Cache-Control,
 *                              clamped to 5 min – 24 h).
 *
 * Additive only: every existing row reads NULL in both and behaves as before.
 */
export async function up(knex) {
  await knex.schema.alterTable('oauth_clients', (t) => {
    t.string('metadata_url', 500).nullable();
    t.datetime('metadata_expires_at', { precision: 3 }).nullable();
    t.unique(['metadata_url'], { indexName: 'uq_oauth_clients_metadata_url' });
  });
}

export async function down(knex) {
  await knex.schema.alterTable('oauth_clients', (t) => {
    t.dropUnique(['metadata_url'], 'uq_oauth_clients_metadata_url');
    t.dropColumn('metadata_url');
    t.dropColumn('metadata_expires_at');
  });
}
