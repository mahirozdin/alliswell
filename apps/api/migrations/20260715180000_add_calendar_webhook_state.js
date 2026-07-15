/**
 * OPH-074 — Google push-notification channel state on calendar_accounts.
 * BLUEPRINT §7.2 steps 6-7: a channel is created per watched calendar, Google
 * POSTs to our webhook, and the account is marked "dirty" for the incremental
 * sync worker (OPH-075).
 *
 * `webhook_channel_id` / `webhook_resource_id` / `webhook_expires_at` already
 * shipped in OPH-015; this adds the two columns that flow needs:
 *
 * - `webhook_channel_token_hash` — the channel token is the shared secret
 *   Google echoes back in `X-Goog-Channel-Token`. Only its HMAC lands in the
 *   database (same posture as refresh_tokens): we generate the token, hand it
 *   to Google once, and never need the plaintext again — so a database dump
 *   cannot forge notifications.
 * - `sync_dirty_at` — set by the webhook, cleared by the worker once the
 *   changes it announced have been consumed.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

export async function up(knex) {
  await knex.schema.alterTable('calendar_accounts', (t) => {
    t.specificType('webhook_channel_token_hash', 'char(64)').nullable();
    t.datetime('sync_dirty_at', { precision: 3 }).nullable();
    // The webhook arrives unauthenticated and looks the account up by channel
    // id alone — that lookup must be indexed, and channel ids are ours (UUIDs)
    // so uniqueness is a real invariant, not just an access path.
    t.unique(['webhook_channel_id'], { indexName: 'uq_calendar_accounts_channel' });
    // The renewal/dirty sweep scans for expiring channels and pending work.
    t.index(['webhook_expires_at'], 'idx_calendar_accounts_channel_expiry');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('calendar_accounts', (t) => {
    t.dropIndex(['webhook_expires_at'], 'idx_calendar_accounts_channel_expiry');
    t.dropUnique(['webhook_channel_id'], 'uq_calendar_accounts_channel');
    t.dropColumn('sync_dirty_at');
    t.dropColumn('webhook_channel_token_hash');
  });
}
