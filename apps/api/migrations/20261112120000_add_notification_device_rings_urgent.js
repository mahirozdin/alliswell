/**
 * OPH-432 (#48) — urgent alarms ring only on the devices the user picked.
 *
 * `rings_urgent` is the per-device switch; `rings_urgent_source` says who set
 * it: 'auto' (the server's first-device rule), 'user' (Settings ▸ Devices) or
 * 'backfill' (this migration). Nullable on purpose — a row nobody has decided
 * about yet says so honestly.
 *
 * The false default is deliberate and dangerous: on its own it would silence
 * every existing install the moment the column appears (LESSONS migrations,
 * "false-default suppression flag"). So this same migration backfills, and
 * the backfill is exported for its integration test.
 *
 * Backfill rule (owner decision): per user, exactly ONE device keeps ringing —
 * the first-added one. Guarded so a long-dead install cannot swallow the
 * alarm: the oldest `created_at` among non-web devices seen in the last 14
 * days; else the oldest among web devices seen in 14 days; else the oldest of
 * all the user's devices. Ties break on `id`. Every row of a backfilled user
 * gets source 'backfill'.
 *
 * The choice is made in JS over a plain SELECT, not with window functions or
 * a dialect-specific UPDATE ... JOIN, so it runs the same on MySQL 8 and
 * MariaDB. No collation is touched (string column added with the table's).
 */

export const RINGS_URGENT_SOURCES = ['auto', 'user', 'backfill'];

const RECENT_MS = 14 * 24 * 60 * 60 * 1000;
const UPDATE_CHUNK = 500;

const time = (value) => (value instanceof Date ? value.getTime() : new Date(value).getTime());

/** Oldest created_at first, then the lower id. */
const firstAdded = (a, b) =>
  time(a.created_at) - time(b.created_at) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/**
 * Picks the one device of a user that keeps ringing.
 * @param {Array<{id: string, platform: string, created_at: Date, last_seen_at: Date}>} devices
 * @param {number} cutoffMs devices seen at or after this instant count as recent
 */
export function pickRingingDevice(devices, cutoffMs) {
  const recent = devices.filter((d) => time(d.last_seen_at) >= cutoffMs);
  const pool =
    [
      recent.filter((d) => d.platform !== 'web'),
      recent.filter((d) => d.platform === 'web'),
      devices,
    ].find((candidates) => candidates.length > 0) ?? [];
  return [...pool].sort(firstAdded)[0] ?? null;
}

/**
 * Sets `rings_urgent` / `rings_urgent_source` for every user that has devices.
 * @param {import('knex').Knex} knex
 * @param {{ now?: Date }} [options]
 * @returns {Promise<{ users: number, ringing: number }>}
 */
export async function backfillRingsUrgent(knex, { now = new Date() } = {}) {
  const cutoffMs = now.getTime() - RECENT_MS;
  const devices = await knex('notification_devices').select(
    'id',
    'user_id',
    'platform',
    'created_at',
    'last_seen_at',
  );

  const byUser = new Map();
  for (const device of devices) {
    const list = byUser.get(device.user_id) ?? [];
    list.push(device);
    byUser.set(device.user_id, list);
  }
  const chosen = [];
  for (const list of byUser.values()) {
    const pick = pickRingingDevice(list, cutoffMs);
    if (pick) chosen.push(pick.id);
  }

  await knex.transaction(async (trx) => {
    // Every existing row is a backfilled one; only the chosen rows ring.
    await trx('notification_devices').update({
      rings_urgent: false,
      rings_urgent_source: 'backfill',
    });
    for (let i = 0; i < chosen.length; i += UPDATE_CHUNK) {
      await trx('notification_devices')
        .whereIn('id', chosen.slice(i, i + UPDATE_CHUNK))
        .update({ rings_urgent: true });
    }
  });

  return { users: byUser.size, ringing: chosen.length };
}

export async function up(knex) {
  await knex.schema.alterTable('notification_devices', (table) => {
    table.boolean('rings_urgent').notNullable().defaultTo(false);
    table.string('rings_urgent_source', 16).nullable();
  });
  await backfillRingsUrgent(knex);
}

export async function down(knex) {
  await knex.schema.alterTable('notification_devices', (table) => {
    table.dropColumn('rings_urgent_source');
    table.dropColumn('rings_urgent');
  });
}
