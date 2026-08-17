import crypto from 'node:crypto';
import { newOpaqueToken } from './tokens.js';

/**
 * API-key shape (OPH-264, ADR-0032 §1).
 *
 * The prefix is load-bearing, not decoration: `authenticate` reads it to tell
 * a key from a JWT before doing any work, the rate limiter reads it before
 * authentication has run at all, and a leaked key is greppable — in logs, in a
 * paste, and by GitHub secret scanning.
 */

export const API_KEY_PREFIX = 'awk_';
/** How much of the secret is stored in the clear, for recognition only. */
export const API_KEY_VISIBLE_CHARS = 12;

/** `awk_` + 32 random bytes (43 base64url chars). Shown to the user ONCE. */
export function newApiKey() {
  return `${API_KEY_PREFIX}${newOpaqueToken(32)}`;
}

/** The part a list screen may show: `awk_` plus the first characters after it. */
export function apiKeyPrefixOf(token) {
  return token.slice(0, API_KEY_VISIBLE_CHARS);
}

/** The raw `awk_…` secret from an Authorization header, or null. */
export function bearerApiKey(request) {
  const header = request.headers?.authorization ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7);
  return token.startsWith(API_KEY_PREFIX) ? token : null;
}

/**
 * The rate-limit bucket for a key-authenticated request (ADR-0032 §5).
 *
 * Computed from the header rather than from `request.apiKeyAuth`, because the
 * limiter runs before authentication: a script must not spend its user's
 * per-IP budget, and one runaway key must not throttle the instance. Hashed so
 * the secret never becomes a bucket name in memory or in a log line.
 */
export function apiKeyRateBucket(request) {
  const token = bearerApiKey(request);
  if (!token) return null;
  return `apikey:${crypto.createHash('sha256').update(token).digest('hex')}`;
}
