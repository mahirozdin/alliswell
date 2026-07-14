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
