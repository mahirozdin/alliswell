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
