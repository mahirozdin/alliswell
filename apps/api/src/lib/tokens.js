import crypto from 'node:crypto';

/**
 * Opaque refresh tokens (Epic 03). The client holds the raw token; the database
 * stores only a keyed hash (HMAC-SHA256 with JWT_REFRESH_SECRET), so a database
 * dump alone can neither reveal nor forge usable refresh tokens. The hex digest
 * is 64 chars — exactly the `refresh_tokens.token_hash` CHAR(64) column.
 */

/** 48 random bytes → 64-char base64url string. */
export function newRefreshToken() {
  return crypto.randomBytes(48).toString('base64url');
}

/**
 * @param {string} token - raw refresh token as sent to the client
 * @param {string} secret - config.auth.refreshSecret
 */
export function hashRefreshToken(token, secret) {
  return crypto.createHmac('sha256', secret).update(token).digest('hex');
}

/**
 * Google push-channel tokens (OPH-074) get the same treatment: we generate
 * one, hand it to Google when opening the channel, and store only the keyed
 * digest — so a database dump can neither read nor forge a notification. We
 * never need the plaintext back (a renewal mints a fresh token), which is
 * exactly what makes hash-only storage possible.
 *
 * Google caps channel tokens at 256 characters; 32 bytes of base64url is 43.
 */
export function newChannelToken() {
  return crypto.randomBytes(32).toString('base64url');
}

/**
 * @param {string} token - raw channel token as handed to Google
 * @param {string} secret - config.auth.refreshSecret
 */
export function hashChannelToken(token, secret) {
  // Domain separator: the two token kinds share a secret and must never
  // produce colliding digests.
  return crypto.createHmac('sha256', secret).update(`channel:${token}`).digest('hex');
}
