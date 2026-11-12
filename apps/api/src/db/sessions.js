/**
 * Sessions, as a person would recognise them (OPH-284).
 *
 * ── A SESSION IS A FAMILY, NOT A ROW ──────────────────────────────────────
 *
 * `refresh_tokens` holds one row per ROTATION: every refresh marks the old row
 * `rotated_at` and inserts a new one carrying the same `family_id`. A phone
 * that refreshes every fifteen minutes therefore produces ~100 rows a day, and
 * a screen listing rows would tell somebody they are signed in on ninety-six
 * devices. The thing they mean by "session" — one sign-in, still alive — is
 * the FAMILY, so that is the unit here.
 *
 * The live row of a family is the one with neither `rotated_at` nor
 * `revoked_at`. There is at most one, and the rotation handler's atomic claim
 * is what guarantees it.
 *
 * ── REVOKING IS PER FAMILY TOO, AND THAT IS NOT A CHOICE ──────────────────
 *
 * Revoking one row would leave the family's newer rows alive, so "I closed
 * that session" would be false the moment the client refreshed. `revokeFamily`
 * is the existing primitive for exactly this and it predates the screen: reuse
 * detection has always killed the whole chain.
 */

import { newId } from '../lib/ids.js';
import { hashRefreshToken, newRefreshToken } from '../lib/tokens.js';
import { lockUsers, promoteIfNoneRings } from './notification-devices.js';
import { transactionWithRetry } from './tx.js';

/** What a client shows about one session. Never the token, never its digest. */
function serialize(rows, { currentFamilyId = null } = {}) {
  const live = rows.find((r) => !r.rotated_at && !r.revoked_at) ?? rows.at(-1);
  const first = rows[0];
  return {
    // The family IS the session id. It is already what a revoke takes, and it
    // is not a credential — knowing it lets you name a session, not use one.
    id: live.family_id,
    deviceName: live.device_name ?? first.device_name ?? null,
    // Where it started, and where it was last seen. Both, because a session
    // that begins in Ankara and refreshes from São Paulo is the one somebody
    // is looking for.
    createdIp: first.created_ip ?? null,
    lastIp: live.created_ip ?? null,
    createdAt: new Date(first.created_at).toISOString(),
    // The newest row's birth IS the last refresh — no extra column needed.
    lastSeenAt: new Date(live.created_at).toISOString(),
    expiresAt: new Date(live.expires_at).toISOString(),
    revokedAt: live.revoked_at ? new Date(live.revoked_at).toISOString() : null,
    current: currentFamilyId != null && live.family_id === currentFamilyId,
  };
}

/**
 * One person's live sessions, newest first.
 *
 * Expired and revoked families are left out rather than shown greyed: this
 * list exists to answer "where am I signed in?", and a dead session is not an
 * answer to it. The audit trail is where history belongs.
 */
export async function listUserSessions(
  db,
  userId,
  { at = new Date(), currentFamilyId = null } = {},
) {
  const rows = await db('refresh_tokens')
    .where({ user_id: userId })
    .orderBy('created_at', 'asc')
    .select();

  const families = new Map();
  for (const row of rows) {
    if (!families.has(row.family_id)) families.set(row.family_id, []);
    families.get(row.family_id).push(row);
  }

  const out = [];
  for (const group of families.values()) {
    const live = group.find((r) => !r.rotated_at && !r.revoked_at);
    // No live row: the family was revoked, or its last token expired without
    // being rotated. Either way it is not somewhere anybody is signed in.
    if (!live || new Date(live.expires_at) <= at) continue;
    out.push(serialize(group, { currentFamilyId }));
  }
  return out.sort((a, b) => (a.lastSeenAt < b.lastSeenAt ? 1 : -1));
}

/** The family a raw refresh token belongs to, or null. */
export async function familyOfToken(db, tokenHash) {
  const row = await db('refresh_tokens').where({ token_hash: tokenHash }).first('family_id');
  return row?.family_id ?? null;
}

/** The distinct non-null values of one column (rows come back whole from the unit fake). */
const distinctOf = (rows, col) => [...new Set(rows.map((row) => row[col]).filter(Boolean))];

/** Runs `fn` inside the transaction `db` already is, or in a fresh retrying one. */
function inTransaction(db, fn) {
  return db.isTransaction ? fn(db) : transactionWithRetry(db, fn);
}

/**
 * ── A SESSION THAT ENDS TAKES ITS DEVICE WITH IT (OPH-435, #48) ───────────
 *
 * A family may be bound to one `notification_devices` row (`device_id`,
 * OPH-434). When the family is revoked, that row is the install it was
 * signed in on, and leaving it registered means the server keeps sending
 * fallback pushes to somebody who signed out. So every door that revokes
 * families — closing a session, "everywhere else", a password change or
 * reset, refresh reuse, `logout?all` — removes the devices bound to them.
 *
 * A device is kept when another live family is still bound to it: a device
 * signed in again after an old session expired must not lose its row because
 * the old family's leftover rows were stamped. Devices no family names (older
 * clients that sent no `deviceId`) are never touched here — nothing says
 * which session they belong to.
 *
 * Call with the user's row locked (`lockUsers`): removing the ringing device
 * runs the OPH-433 promotion, which must not race a registration.
 *
 * @returns {Promise<string[]>} the ids of the device rows removed
 */
export async function dropDevicesOfFamilies(trx, userId, familyIds, { at = new Date() } = {}) {
  const families = [...new Set(familyIds.filter(Boolean))];
  if (families.length === 0) return [];
  const bound = distinctOf(
    await trx('refresh_tokens')
      .where({ user_id: userId })
      .whereIn('family_id', families)
      .whereNotNull('device_id')
      .select('device_id'),
    'device_id',
  );
  if (bound.length === 0) return [];
  const stillLive = await devicesWithSession(trx, userId, bound, { at });
  const drop = bound.filter((id) => !stillLive.has(id));
  if (drop.length === 0) return [];
  const rows = await trx('notification_devices')
    .where({ user_id: userId })
    .whereIn('id', drop)
    .select('id', 'rings_urgent');
  if (rows.length === 0) return [];
  await trx('notification_devices')
    .where({ user_id: userId })
    .whereIn(
      'id',
      rows.map((row) => row.id),
    )
    .delete();
  if (rows.some((row) => Number(row.rings_urgent) === 1)) {
    await promoteIfNoneRings(trx, userId);
  }
  return rows.map((row) => row.id);
}

/**
 * Which of these devices still have somebody signed in on them — a live
 * (neither rotated, revoked nor expired) family bound to the device
 * (`GET /notification-devices` `hasSession`, OPH-435).
 * @returns {Promise<Set<string>>}
 */
export async function devicesWithSession(db, userId, deviceIds, { at = new Date() } = {}) {
  if (deviceIds.length === 0) return new Set();
  const rows = await db('refresh_tokens')
    .where({ user_id: userId })
    .whereIn('device_id', deviceIds)
    .whereNull('revoked_at')
    .whereNull('rotated_at')
    .where('expires_at', '>', at)
    .select('device_id');
  return new Set(distinctOf(rows, 'device_id'));
}

/**
 * Was somebody signed in on this device and is nobody any more? True when at
 * least one family of this user is bound to the device and none of them is
 * live (OPH-435): the device was removed or its session ended. A device no
 * family names (an older client) is never "signed out" by this test.
 *
 * `PUT /notification-devices/:id` asks it before it creates a row, so a
 * removed device cannot register itself again with the access token it still
 * holds for a few minutes and keep receiving pushes after the sign-out.
 */
export async function deviceSignedOut(db, userId, deviceId, { at = new Date() } = {}) {
  const bound = await db('refresh_tokens')
    .where({ user_id: userId, device_id: deviceId })
    .first('id');
  if (!bound) return false;
  const live = await devicesWithSession(db, userId, [deviceId], { at });
  return !live.has(deviceId);
}

/**
 * Signs one device out (OPH-435): every family bound to it is revoked, every
 * row of it at once, the same single UPDATE `revokeOtherSessions` uses. The
 * caller removes the device row itself. Call inside a transaction holding
 * `lockUsers(trx, [userId])`.
 * @returns {Promise<number>} rows revoked; 0 when no live session was bound
 */
export function revokeDeviceSessions(trx, { userId, deviceId, at = new Date() }) {
  return trx('refresh_tokens')
    .where({ user_id: userId, device_id: deviceId })
    .whereNull('revoked_at')
    .update({ revoked_at: at });
}

/**
 * Closes one session. Scoped by user as well as family so that knowing a
 * family id — which the owner's own screen shows them — can never end
 * somebody else's session. Also the reuse response: a rotated token coming
 * back burns its whole family. The device bound to the family goes with it,
 * also when the family was already revoked.
 *
 * `db` may be an open transaction (it is used as is) or the pool.
 *
 * @returns {Promise<number>} rows revoked; 0 means "no such live session".
 */
export function revokeSession(db, { userId, familyId, at = new Date() }) {
  return inTransaction(db, async (trx) => {
    await lockUsers(trx, [userId]);
    const revoked = await trx('refresh_tokens')
      .where({ user_id: userId, family_id: familyId })
      .whereNull('revoked_at')
      .update({ revoked_at: at });
    // Even when nothing was left to revoke: a family revoked earlier (a
    // removed device, say) may have had its device registered again while
    // its access token still worked, and this — a refused refresh of that
    // family — is the last moment the server hears from it.
    await dropDevicesOfFamilies(trx, userId, [familyId], { at });
    return revoked;
  });
}

/**
 * Closes every session except one. `keepFamilyId` null closes all of them —
 * which is what an administrator's force-logout means, what a password change
 * does, and what a person who did not name their own session gets. The
 * devices bound to the closed families go with them.
 *
 * `db` may be an open transaction (it is used as is) or the pool.
 */
export function revokeOtherSessions(db, { userId, keepFamilyId = null, at = new Date() }) {
  return inTransaction(db, async (trx) => {
    await lockUsers(trx, [userId]);
    const open = () => {
      const q = trx('refresh_tokens').where({ user_id: userId }).whereNull('revoked_at');
      return keepFamilyId ? q.whereNot('family_id', keepFamilyId) : q;
    };
    const families = distinctOf(await open().select('family_id'), 'family_id');
    const revoked = await open().update({ revoked_at: at });
    await dropDevicesOfFamilies(trx, userId, families, { at });
    return revoked;
  });
}

/** How many live sessions a person has — the count an admin screen leads with. */
export async function countUserSessions(db, userId, { at = new Date() } = {}) {
  const sessions = await listUserSessions(db, userId, { at });
  return sessions.length;
}

/**
 * ── ISSUING ONE, WHICH USED TO LIVE IN THE ROUTE (OPH-288) ────────────────
 *
 * The three functions below were private to `routes/auth.js` and are about
 * SESSIONS rather than about routing, which stopped being a stylistic point
 * the moment something outside that file needed to start one: a redirect-based
 * sign-in ends at an endpoint the route file does not own, and the alternative
 * was a second place that writes `refresh_tokens` — the exact thing every
 * other caller in this product has been careful not to do.
 *
 * Moved VERBATIM, signatures included, so every existing call site changed by
 * one import line and nothing else. A refactor that also improved them would
 * have made the diff a place where a behaviour change could hide.
 */
/**
 * Inserts a refresh-token row (via `db` or an open trx) and returns the raw token.
 * Every login/register starts a new rotation family; refresh (OPH-022) keeps the family.
 */
/**
 * What to write in `device_name` (OPH-284).
 *
 * The column has existed since the first migration and NOTHING had ever
 * written to it — measured, not assumed. A session list whose every row says
 * "unknown device" answers no question, so sign-in now records the
 * User-Agent, truncated to the column.
 *
 * Stored RAW rather than parsed into "Chrome on macOS". Parsing a User-Agent
 * is guessing, the guesses rot as browsers change their strings, and a wrong
 * guess in this list is worse than a long one: the whole point is that
 * somebody recognises their own device, and a client can shorten a string it
 * can see. It cannot recover one we threw away.
 */
export function deviceLabel(request) {
  const ua = request?.headers?.['user-agent'];
  if (typeof ua !== 'string' || ua.trim() === '') return null;
  return ua.trim().slice(0, 255);
}

export async function createRefreshRecord(
  executor,
  auth,
  { userId, familyId, ip, deviceName = null, deviceId = null },
) {
  const token = newRefreshToken();
  const expiresAt = new Date(Date.now() + auth.refreshTtlDays * 24 * 60 * 60 * 1000);
  await executor('refresh_tokens').insert({
    id: newId(),
    user_id: userId,
    family_id: familyId,
    token_hash: hashRefreshToken(token, auth.refreshSecret),
    expires_at: expiresAt,
    created_ip: ip ?? null,
    device_name: deviceName,
    // OPH-434 — the notification device this family is bound to, or null.
    device_id: deviceId,
  });
  return { token, expiresAt };
}

export function sessionTokens(app, user, refresh) {
  return {
    accessToken: app.signAccessToken(user),
    accessTokenExpiresInSec: app.config.auth.accessTtlSec,
    refreshToken: refresh.token,
    refreshTokenExpiresAt: refresh.expiresAt.toISOString(),
  };
}
