/**
 * Which of a user's devices rings urgent alarms (OPH-433, #48, ADR-0069 #2).
 *
 * `notification_devices.rings_urgent` is the per-device switch and
 * `rings_urgent_source` says who set it: 'auto' (this rule), 'user'
 * (`PATCH /notification-devices/:id`) or 'backfill' (the OPH-432 migration).
 *
 * The rule runs only when a row is created for a user — a fresh insert, or a
 * takeover of an install another account had registered — never on a
 * heartbeat. Every write here runs inside a transaction that first locks the
 * user's `users` row (`lockUsers`), so two devices registering at the same
 * instant are serialised and cannot both see "nothing rings yet".
 */

export const RINGS_URGENT_SOURCES = ['auto', 'user', 'backfill'];

const PLATFORM_LABELS = {
  ios: 'iPhone',
  android: 'Android',
  macos: 'Mac',
  windows: 'Windows',
  linux: 'Linux',
  web: 'Web',
};

/** The name a device gets when its user clears the name they gave it. */
export function platformLabel(platform) {
  return PLATFORM_LABELS[platform] ?? platform;
}

const time = (value) => (value instanceof Date ? value.getTime() : new Date(value).getTime());

/**
 * The pure rule (ADR-0069 #2 table).
 *
 * @param {Array<{id: string, platform: string, rings_urgent_source: string|null}>} ringingRows
 *   the user's OTHER rows that ring now
 * @param {string} platform the new device's platform
 * @returns {{ ringsUrgent: boolean, handOver: string[] }} whether the new row
 *   rings, and which automatically chosen web rows it takes the alarm from
 */
export function decideNewDeviceRinging(ringingRows, platform) {
  if (ringingRows.length === 0) return { ringsUrgent: true, handOver: [] };
  const allAutomaticWeb = ringingRows.every(
    (row) =>
      row.platform === 'web' &&
      (row.rings_urgent_source === 'auto' || row.rings_urgent_source === 'backfill'),
  );
  if (allAutomaticWeb && platform !== 'web') {
    return { ringsUrgent: true, handOver: ringingRows.map((row) => row.id) };
  }
  return { ringsUrgent: false, handOver: [] };
}

/**
 * The device that inherits the alarm when the last ringing one goes: the most
 * recently seen non-web device, else the most recently seen web one. Ties go
 * to the higher id (the later registration).
 * @param {Array<{id: string, platform: string, last_seen_at: Date|string}>} rows
 */
export function pickPromotion(rows) {
  const newestFirst = [...rows].sort(
    (a, b) => time(b.last_seen_at) - time(a.last_seen_at) || (a.id < b.id ? 1 : -1),
  );
  return newestFirst.find((row) => row.platform !== 'web') ?? newestFirst[0] ?? null;
}

/**
 * Locks the given users' rows for the rest of the transaction, in id order so
 * two transactions that lock the same pair cannot deadlock on each other.
 */
export async function lockUsers(trx, userIds) {
  const ids = [...new Set(userIds.filter(Boolean))].sort();
  if (ids.length === 0) return;
  await trx('users').whereIn('id', ids).orderBy('id').forUpdate().select('id');
}

/** The user's rows that ring now, optionally without one device. */
export async function ringingDevices(trx, userId, { exceptId } = {}) {
  const rows = await trx('notification_devices')
    .where({ user_id: userId, rings_urgent: true })
    .select('id', 'platform', 'rings_urgent_source');
  return exceptId ? rows.filter((row) => row.id !== exceptId) : rows;
}

/**
 * Applies the rule for a row about to be created for `userId`: switches off
 * the web rows it takes over and returns the flags the new row is written
 * with. Call inside a transaction that holds `lockUsers(trx, [userId])`.
 */
export async function decideForNewRow(trx, userId, deviceId, platform) {
  const ringing = await ringingDevices(trx, userId, { exceptId: deviceId });
  const { ringsUrgent, handOver } = decideNewDeviceRinging(ringing, platform);
  if (handOver.length > 0) {
    await trx('notification_devices')
      .whereIn('id', handOver)
      .update({ rings_urgent: false, rings_urgent_source: 'auto', updated_at: new Date() });
  }
  return { rings_urgent: ringsUrgent, rings_urgent_source: 'auto' };
}

/**
 * After a ringing row left the user (deleted, or taken over by another
 * account): if nothing of theirs rings any more, the most recently seen
 * non-web device (else web) rings, source 'auto'. A user who has another
 * ringing device keeps exactly what they chose.
 * @returns {Promise<string|null>} the promoted device id
 */
export async function promoteIfNoneRings(trx, userId) {
  if ((await ringingDevices(trx, userId)).length > 0) return null;
  const rows = await trx('notification_devices')
    .where({ user_id: userId })
    .select('id', 'platform', 'last_seen_at');
  const pick = pickPromotion(rows);
  if (!pick) return null;
  await trx('notification_devices')
    .where({ id: pick.id })
    .update({ rings_urgent: true, rings_urgent_source: 'auto', updated_at: new Date() });
  return pick.id;
}

/** Does any of the user's devices ring urgent alarms? */
export async function anyRinging(trx, userId) {
  return (await ringingDevices(trx, userId)).length > 0;
}
