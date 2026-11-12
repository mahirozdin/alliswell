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

/**
 * MCP OAuth tokens (OPH-218, ADR-0022): access/refresh tokens, authorization
 * codes and client secrets are all opaque randoms whose keyed digests are the
 * only thing stored — the refresh-token pattern with per-kind domain
 * separators ("I removed the connector" must genuinely revoke).
 */
export function newOpaqueToken(bytes = 48) {
  return crypto.randomBytes(bytes).toString('base64url');
}

/**
 * @param {'access'|'refresh'|'code'|'client_secret'} kind
 * @param {string} token
 * @param {string} secret - config.auth.refreshSecret
 */
export function hashMcpToken(kind, token, secret) {
  return crypto.createHmac('sha256', secret).update(`mcp-${kind}:${token}`).digest('hex');
}

/**
 * API keys (OPH-264, ADR-0032 §2): the same hash-only storage, with their own
 * domain separator.
 *
 * Deliberately not `hashMcpToken('api_key', …)` as the backlog sketched: same
 * pattern, same file, same secret — but an API key is not an MCP token, and a
 * digest separated as `mcp-api_key:` would tell every future reader something
 * untrue about where these keys come from.
 *
 * @param {string} token - the raw `awk_…` secret as handed to the user, once
 * @param {string} secret - config.auth.refreshSecret
 */
export function hashApiKey(token, secret) {
  return crypto.createHmac('sha256', secret).update(`api-key:${token}`).digest('hex');
}

/**
 * TOTP recovery codes (OPH-283): the same hash-only storage, its own separator.
 *
 * A recovery code is only ever COMPARED, never read back, so it is stored
 * exactly like the two above and for the same reason — a database dump can
 * neither read one nor forge one.
 *
 * The code is normalised before hashing (upper-cased, dashes and spaces
 * dropped) because somebody is typing this off a printout under stress, and
 * "the dashes matter" is a rule nobody should have to know. The normalisation
 * belongs HERE rather than at the call sites: two call sites that disagree
 * about it would store a digest neither could match.
 *
 * @param {string} code - as the person typed it
 * @param {string} secret - config.auth.totpKey
 */
export function hashRecoveryCode(code, secret) {
  const normalised = String(code).toUpperCase().replace(/[\s-]/g, '');
  return crypto.createHmac('sha256', secret).update(`totp-recovery:${normalised}`).digest('hex');
}

/**
 * Password-reset links (OPH-406, ADR-0064): the same hash-only storage with
 * their own separator. 32 random bytes (43 base64url chars) — the link is a
 * bearer credential for one password change, and guessing 256 bits under a
 * per-IP rate limit is not a plan anybody has.
 *
 * @param {string} token - the raw token as it sits in the link
 * @param {string} secret - config.auth.refreshSecret
 */
export function hashPasswordResetToken(token, secret) {
  return crypto.createHmac('sha256', secret).update(`password-reset:${token}`).digest('hex');
}

/**
 * Widget tokens (OPH-458, ADR-0070): the home-screen widget's read-only
 * credential. The API-key pattern — an opaque random with a load-bearing
 * prefix, shown once, stored as a keyed digest with its own separator.
 *
 * The prefix is what `authenticateWidget` tests before any work, and it is
 * deliberately not `awk_`: `app.authenticate` therefore hands an `aww_` value
 * to `jwtVerify`, which refuses it, so no other route can ever take one.
 */
export const WIDGET_TOKEN_PREFIX = 'aww_';

/** `aww_` + 32 random bytes (43 base64url chars). Shown to the app ONCE. */
export function newWidgetToken() {
  return `${WIDGET_TOKEN_PREFIX}${newOpaqueToken(32)}`;
}

/**
 * @param {string} token - the raw `aww_…` value as handed to the app, once
 * @param {string} secret - config.auth.refreshSecret
 */
export function hashWidgetToken(token, secret) {
  return crypto.createHmac('sha256', secret).update(`widget:${token}`).digest('hex');
}

/** The raw `aww_…` value from an Authorization header, or null. */
export function bearerWidgetToken(request) {
  const header = request.headers?.authorization ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  return token.startsWith(WIDGET_TOKEN_PREFIX) ? token : null;
}

/**
 * The rate-limit bucket of a widget request (ADR-0070 §3, ADR-0045): the
 * token, read from the header because the limiter runs before
 * authentication, and hashed so the secret never becomes a bucket name.
 * Null without a widget token (the route's limiter then uses the IP).
 */
export function widgetTokenRateBucket(request) {
  const token = bearerWidgetToken(request);
  if (!token) return null;
  return `widget:${crypto.createHash('sha256').update(token).digest('hex')}`;
}
