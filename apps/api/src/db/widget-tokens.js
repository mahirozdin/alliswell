/**
 * Widget tokens (OPH-458, ADR-0070): one read-only `aww_` credential per
 * notification device, bound to the session family that minted it.
 *
 * A token is good while all of these hold — `findLiveWidgetToken` checks them
 * in one place, and every refusal is the same 401 to the caller:
 *   • its row matches the digest and is neither revoked nor expired;
 *   • its device row still exists for that user;
 *   • its minting family still has a LIVE row (neither rotated, revoked nor
 *     expired). A rotation keeps the family and commits the new row in the
 *     same transaction as it retires the old one, so an app refresh never
 *     makes a widget request fail; every event that ends the family (sign-out,
 *     session revoke, reuse, password change) ends the token with it, even on
 *     a path that does not stamp `revoked_at` here;
 *   • the user is not deleted.
 *
 * The explicit revocations below stamp `revoked_at` as well, so the row says
 * when it stopped working rather than leaving it to be inferred.
 */

import { newId } from '../lib/ids.js';
import { hashWidgetToken, newWidgetToken } from '../lib/tokens.js';

/** Life of a widget token from its minting (ADR-0070 §4). */
export const WIDGET_TOKEN_TTL_DAYS = 90;

/**
 * Whether the caller's session — the family its access token names (`sid`)
 * — is still live AND runs on this device (`refresh_tokens.device_id`,
 * OPH-434). The mint asks this rather than "does the device have some live
 * session": an access token keeps verifying for its 15 minutes after its
 * family is revoked, and a removed device must not use that window to mint
 * a token tied to another device's session that would outlive it.
 */
export async function sessionRunsOnDevice(
  db,
  userId,
  familyId,
  deviceId,
  { at = new Date() } = {},
) {
  if (!familyId) return false;
  const row = await db('refresh_tokens')
    .where({ user_id: userId, family_id: familyId, device_id: deviceId })
    .whereNull('revoked_at')
    .whereNull('rotated_at')
    .where('expires_at', '>', at)
    .first('id');
  return Boolean(row);
}

/**
 * Mints the device's token, replacing the one it had: the row is keyed by
 * (user, device), so the previous digest is overwritten in the same statement
 * and the previous token stops matching at once.
 *
 * @returns {Promise<{ token: string, expiresAt: Date }>}
 */
export async function mintWidgetToken(db, secret, { userId, deviceId, familyId, at = new Date() }) {
  const token = newWidgetToken();
  const expiresAt = new Date(at.getTime() + WIDGET_TOKEN_TTL_DAYS * 86_400_000);
  const fresh = {
    session_family_id: familyId,
    token_hash: hashWidgetToken(token, secret),
    created_at: at,
    expires_at: expiresAt,
    last_used_at: null,
    revoked_at: null,
  };
  await db('widget_tokens')
    .insert({ id: newId(), user_id: userId, device_id: deviceId, ...fresh })
    .onConflict(['user_id', 'device_id'])
    .merge(fresh);
  return { token, expiresAt };
}

/**
 * The live token row behind a raw `aww_…` value, with its user, or null for
 * any reason it does not work (see the file comment).
 */
export async function findLiveWidgetToken(db, secret, token, { at = new Date() } = {}) {
  const row = await db('widget_tokens')
    .where({ token_hash: hashWidgetToken(token, secret) })
    .whereNull('revoked_at')
    .where('expires_at', '>', at)
    .first();
  if (!row) return null;
  const device = await db('notification_devices')
    .where({ id: row.device_id, user_id: row.user_id })
    .first('id');
  if (!device) return null;
  const family = await db('refresh_tokens')
    .where({ user_id: row.user_id, family_id: row.session_family_id })
    .whereNull('revoked_at')
    .whereNull('rotated_at')
    .where('expires_at', '>', at)
    .first('id');
  if (!family) return null;
  const user = await db('users')
    .where({ id: row.user_id })
    .whereNull('deleted_at')
    .first('id', 'email');
  if (!user) return null;
  return { row, user };
}

/**
 * Revokes the user's widget tokens minted by these session families or held
 * by these devices. `db` may be an open transaction.
 *
 * @returns {Promise<number>} tokens revoked
 */
export async function revokeWidgetTokens(
  db,
  { userId, familyIds = [], deviceIds = [], at = new Date() },
) {
  const families = [...new Set(familyIds.filter(Boolean))];
  const devices = [...new Set(deviceIds.filter(Boolean))];
  if (families.length === 0 && devices.length === 0) return 0;
  return db('widget_tokens')
    .where({ user_id: userId })
    .whereNull('revoked_at')
    .where((q) => {
      if (families.length > 0) q.orWhereIn('session_family_id', families);
      if (devices.length > 0) q.orWhereIn('device_id', devices);
    })
    .update({ revoked_at: at });
}

/** Every widget token of the user (a password change, sign-out everywhere). */
export function revokeAllWidgetTokens(db, { userId, at = new Date() }) {
  return db('widget_tokens')
    .where({ user_id: userId })
    .whereNull('revoked_at')
    .update({ revoked_at: at });
}
