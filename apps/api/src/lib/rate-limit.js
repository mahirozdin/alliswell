import crypto from 'node:crypto';
import { apiKeyRateBucket } from './api-keys.js';

/**
 * Rate-limit buckets and the 429 body (OPH-357, ADR-0045).
 *
 * The limiter used to count every request by `request.ip`. Behind a factory's
 * NAT that is ONE bucket for every person there: a dozen people signing in at
 * the start of a shift shared the 10/min credential budget, and one member's
 * nine sync engines shared the 300/min budget with all of their colleagues.
 * A bucket is now WHO is asking, as far as the limiter can prove it before
 * authentication runs:
 *
 * - an API key → its own bucket (ADR-0032 §5, unchanged);
 * - a valid access token → its user (`user:<sub>`) — the signature is checked
 *   here, so a forged or expired token does not mint a fresh bucket; it falls
 *   back to the IP like any anonymous request;
 * - anything else → the IP.
 *
 * Credential endpoints (register, login, refresh, OAuth sign-in) have no
 * identity yet: they count per IP + a digest of the account they name, so one
 * person's wrong passwords still trip at RATE_LIMIT_AUTH_MAX while their
 * colleagues behind the same address are unaffected. A per-IP ceiling
 * (RATE_LIMIT_AUTH_IP_MAX) keeps password spraying — many accounts from one
 * address — bounded.
 */

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

/** The bearer token, when it is not an API key. */
function bearerToken(request) {
  const header = request.headers?.authorization ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  return token || null;
}

/**
 * The global key generator: API key, then verified user, then IP.
 *
 * @param {import('fastify').FastifyInstance} app
 * @param {import('fastify').FastifyRequest} request
 */
export function identityRateKey(app, request) {
  const keyBucket = apiKeyRateBucket(request);
  if (keyBucket) return keyBucket;
  const token = bearerToken(request);
  if (token && app.jwt) {
    try {
      const payload = app.jwt.verify(token);
      if (payload?.sub) return `user:${payload.sub}`;
    } catch {
      // Forged, expired or for another audience: no identity, so the IP.
    }
  }
  return `ip:${request.ip}`;
}

/**
 * The account a credential request names: the e-mail on register/login, the
 * refresh token on refresh/logout, the identity token on OAuth sign-in. Read
 * from the parsed body, which is why the credential limiter runs at
 * `preValidation` rather than `onRequest`.
 */
function credentialSubject(body) {
  if (!body || typeof body !== 'object') return '';
  if (typeof body.email === 'string') return `email:${body.email.trim().toLowerCase()}`;
  if (typeof body.refreshToken === 'string') return `refresh:${body.refreshToken}`;
  if (typeof body.idToken === 'string') return `oauth:${body.idToken}`;
  return '';
}

/** IP + a digest of the account — the secret never becomes a bucket name. */
export function credentialRateKey(request) {
  return `cred:${request.ip}:${sha256(credentialSubject(request.body))}`;
}

/**
 * The 429 every limiter answers: a stable code the clients translate and the
 * wait in whole seconds (the `Retry-After` header carries the same number).
 *
 * @param {import('fastify').FastifyInstance} app
 * @param {number} ttlMs
 */
export function rateLimitedError(app, ttlMs) {
  const retryAfter = Math.max(1, Math.ceil(ttlMs / 1000));
  const err = app.httpErrors.tooManyRequests(`Rate limit exceeded, retry in ${retryAfter} seconds`);
  err.code = 'RATE_LIMITED';
  err.retryAfter = retryAfter;
  return err;
}

/**
 * Route config for the credential endpoints: the per-account bucket, plus the
 * per-IP ceiling as an `onRequest` hook (spread both into the route options).
 *
 * @param {import('fastify').FastifyInstance} app
 */
export function credentialRateLimit(app) {
  return {
    rateLimit: {
      max: app.config.rateLimitAuthMax,
      timeWindow: '1 minute',
      hook: 'preValidation',
      keyGenerator: credentialRateKey,
    },
  };
}

/**
 * The per-IP ceiling across every credential endpoint. One shared bucket per
 * address (not per route), built once at boot.
 *
 * @param {import('fastify').FastifyInstance} app
 */
export function credentialIpCeiling(app) {
  const check = app.createRateLimit({
    max: app.config.rateLimitAuthIpMax,
    timeWindow: '1 minute',
    keyGenerator: (request) => `credip:${request.ip}`,
  });
  return async function credentialIpCeilingHook(request, reply) {
    const result = await check(request);
    if (result.isAllowed || !result.isExceeded) return;
    reply.header('x-ratelimit-limit', result.max);
    reply.header('x-ratelimit-remaining', 0);
    reply.header('x-ratelimit-reset', result.ttlInSeconds);
    reply.header('retry-after', Math.max(1, result.ttlInSeconds));
    throw rateLimitedError(app, result.ttl);
  };
}
