/**
 * OPH-380 — the CalDAV connector's account columns (CALDAV.md §5, ADR-0059).
 *
 * `calendar_accounts` was shaped for CalDAV in OPH-015 (`provider` already
 * enumerates `apple_caldav`; `sync_token`, the link table's `etag` and
 * `provider_event_uid` carry over verbatim). What is genuinely new:
 *
 * - `encrypted_app_password` — AES-256-GCM ciphertext under
 *   `CALENDAR_TOKEN_KEY` (lib/crypto.js, ADR-0006). A password, not a token:
 *   the column name does not lie about what a leak would hand over.
 * - `caldav_kind` — 'icloud' | 'generic'. Every CalDAV account uses the
 *   existing `apple_caldav` provider value (no ENUM change, ADR-0059 §2);
 *   this column says which server it really is.
 * - `caldav_server_url` — where discovery started (what the user typed).
 * - `principal_url`, `calendar_home_url` — what discovery found; iCloud's
 *   per-account partition host lives in the home URL.
 * - `calendar_display_name` — the chosen calendar's name, for the card.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

export async function up(knex) {
  await knex.schema.alterTable('calendar_accounts', (t) => {
    t.text('encrypted_app_password').nullable();
    t.string('caldav_kind', 16).nullable();
    t.string('caldav_server_url', 500).nullable();
    t.string('principal_url', 500).nullable();
    t.string('calendar_home_url', 500).nullable();
    t.string('calendar_display_name', 255).nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('calendar_accounts', (t) => {
    t.dropColumn('calendar_display_name');
    t.dropColumn('calendar_home_url');
    t.dropColumn('principal_url');
    t.dropColumn('caldav_server_url');
    t.dropColumn('caldav_kind');
    t.dropColumn('encrypted_app_password');
  });
}
