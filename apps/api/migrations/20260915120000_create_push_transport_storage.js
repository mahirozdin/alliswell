/**
 * OPH-311 — what a sender needs to reach a device, and what stops it sending
 * the same thing twice (Epic 30, ADR-0038).
 *
 * ── WHY A SUBSCRIPTION DOES NOT FIT IN `push_token` ───────────────────────
 *
 * `push_token` is one string because an FCM registration token is one string.
 * A Web Push subscription is three things — an endpoint URL and the two keys
 * that encrypt a payload to that browser (RFC 8291) — and the endpoint alone
 * can outgrow the 512 characters that column has. So the subscription gets its
 * own columns, `push_provider` says which of the two a row is carrying, and
 * `push_token` keeps meaning exactly what it always meant.
 *
 * ── THE TWO THE SENDER WRITES, AND NOBODY ELSE ────────────────────────────
 *
 * `invalid_at` is set when an endpoint answers 404/410 or FCM says UNREGISTERED
 * — a subscription the user revoked or a reinstall. Retrying it forever is how
 * a delivery log fills with noise that buries the failures worth reading, so a
 * marked device is skipped until it registers again, which clears the mark.
 * `last_push_at` is the other half of the same question, for diagnostics.
 *
 * ── AND THE LOG THAT MAKES SENDING IDEMPOTENT ─────────────────────────────
 *
 * The due sweep runs on a timer, and a timer that missed a tick looks back over
 * a window — so it will meet the same reminder more than once. `reminder_push_log`
 * is what lets it recognise one it has already handled: a row is CLAIMED by the
 * insert (the unique index makes that atomic and is why two instances sweeping
 * at once cannot both send), and the result is written onto it afterwards.
 *
 * Shaped like `client_mutations` rather than `task_tags`: a ULID primary key
 * with the natural key as a UNIQUE index. The plan asked for the triple as the
 * primary key, and the triple is still what enforces idempotency — but two
 * char(26) columns and a datetime make a wide clustered index that every
 * secondary index then carries a copy of, and ADR-0004 says an AllisWell row
 * has a ULID id.
 *
 * `reminders.status` is deliberately untouched. Writing `delivered` onto it at
 * fire time would be a revision per reminder per device, pulled down by every
 * client, at exactly the busiest minute — so delivery is recorded on a table
 * nobody syncs.
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export const PUSH_PROVIDERS = ['fcm', 'webpush'];
export const PUSH_RESULTS = ['pending', 'sent', 'failed'];

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.alterTable('notification_devices', (t) => {
    t.enu('push_provider', PUSH_PROVIDERS).nullable();
    // An endpoint has no useful upper bound in the spec; TEXT rather than a
    // guess that a push service later outgrows.
    t.text('push_endpoint').nullable();
    // Raw P-256 point (65 bytes) and the auth secret (16), both base64url.
    t.string('push_p256dh', 128).nullable();
    t.string('push_auth', 64).nullable();
    t.datetime('invalid_at', { precision: 3 }).nullable();
    t.datetime('last_push_at', { precision: 3 }).nullable();
  });

  await knex.schema.createTable('reminder_push_log', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('reminder_id', 'char(26)').notNullable();
    t.specificType('device_id', 'char(26)').notNullable();
    // The instant this row is about — a reminder that is snoozed and fires
    // again is a different delivery, not a repeat of the first.
    t.datetime('fire_at', { precision: 3 }).notNullable();
    t.enu('provider', PUSH_PROVIDERS).notNullable();
    t.enu('result', PUSH_RESULTS).notNullable().defaultTo('pending');
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('sent_at', { precision: 3 }).nullable();
    // The claim. Two sweeps racing: one insert wins, the other gets
    // ER_DUP_ENTRY and knows somebody else has this one.
    t.unique(['reminder_id', 'device_id', 'fire_at'], { indexName: 'uq_reminder_push' });
    // What the reaper scans. A delivery log is evidence for a few days, not
    // history — it grows with every reminder of every user otherwise.
    t.index(['created_at'], 'idx_reminder_push_log_created');
    t.foreign('reminder_id', 'fk_reminder_push_log_reminder')
      .references('reminders.id')
      .onDelete('CASCADE');
    t.foreign('device_id', 'fk_reminder_push_log_device')
      .references('notification_devices.id')
      .onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('reminder_push_log');
  await knex.schema.alterTable('notification_devices', (t) => {
    t.dropColumn('push_provider');
    t.dropColumn('push_endpoint');
    t.dropColumn('push_p256dh');
    t.dropColumn('push_auth');
    t.dropColumn('invalid_at');
    t.dropColumn('last_push_at');
  });
}
