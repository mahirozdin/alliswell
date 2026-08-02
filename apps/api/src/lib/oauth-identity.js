import { createRemoteJWKSet, jwtVerify } from 'jose';

/**
 * Verifying a Google or Apple **ID token** (ADR-0026).
 *
 * The shape of the whole feature in one paragraph: the app performs the native
 * sign-in, gets an ID token from the provider, and posts it here. This module
 * proves the token is genuine and says who it belongs to. It does NOT create
 * sessions, users or anything else — AllisWell's own account in MySQL stays the
 * source of truth, and the caller decides what to do with a verified identity.
 *
 * Why not just trust Firebase Auth: because a self-hoster has no Firebase. The
 * provider's own ID token is the one credential available on every deployment,
 * so it is the one this server accepts. Firebase remains optional on the client
 * (docs/FIREBASE.md); nothing on the server depends on it.
 *
 * Three things are checked, and all three matter:
 *
 * 1. **Signature** against the provider's live JWKS. `createRemoteJWKSet`
 *    caches keys and refetches on an unknown `kid`, which is what makes key
 *    rotation a non-event.
 * 2. **Issuer** — pinned per provider.
 * 3. **Audience** — pinned to OUR client IDs. This is the check people skip and
 *    it is the one that matters most: a token is signed by Google for *some*
 *    application, and without an audience check any Google-issued token for any
 *    app in the world would sign its bearer in here as whoever it names.
 */

const GOOGLE = {
  jwksUri: 'https://www.googleapis.com/oauth2/v3/certs',
  // Google emits both spellings and has done for years; both are legitimate.
  issuers: ['https://accounts.google.com', 'accounts.google.com'],
};

const APPLE = {
  jwksUri: 'https://appleid.apple.com/auth/keys',
  issuers: ['https://appleid.apple.com'],
};

/** One JWKS client per provider, kept for the process — they cache internally. */
const jwks = new Map();

function jwksFor(uri) {
  if (!jwks.has(uri)) {
    jwks.set(
      uri,
      createRemoteJWKSet(new URL(uri), {
        cooldownDuration: 30_000,
        cacheMaxAge: 10 * 60_000,
        timeoutDuration: 5_000,
      }),
    );
  }
  return jwks.get(uri);
}

export class OauthIdentityError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/**
 * Which audiences count as ours, per provider.
 *
 * Every platform's client ID is accepted for the same provider: one Google
 * project issues a different client ID to the Android app, the iOS app and the
 * web app, and all three are equally us. A deployment that configures none of
 * them has the provider switched off — refusing is the only safe default,
 * because an empty audience list would otherwise mean "accept anything".
 */
export function audiencesFor(config, provider) {
  // `config.signIn`, exactly as config.js builds it. Reading a flattened shape
  // here silently produced an empty list against the real config — which the
  // caller correctly reads as "provider switched off", so sign-in failed with
  // OAUTH_PROVIDER_NOT_CONFIGURED no matter what was in the environment. A test
  // that passes its own object cannot catch that; the one below uses loadConfig().
  const signIn = config?.signIn ?? {};
  const raw =
    provider === 'google'
      ? [signIn.googleWebClientId, signIn.googleIosClientId, signIn.googleAndroidClientId]
      : [signIn.appleServiceId, signIn.appleBundleId];
  return raw.filter((value) => typeof value === 'string' && value.length > 0);
}

/**
 * Verify an ID token and return the identity it asserts.
 *
 * @returns {Promise<{provider: string, subject: string, email: string|null,
 *                    emailVerified: boolean, name: string|null}>}
 * @throws {OauthIdentityError} on anything that is not a valid token for us.
 */
export async function verifyIdentityToken(config, { provider, idToken }) {
  const spec = provider === 'google' ? GOOGLE : provider === 'apple' ? APPLE : null;
  if (!spec) {
    throw new OauthIdentityError('OAUTH_PROVIDER_UNSUPPORTED', `Unknown provider: ${provider}`);
  }

  const audience = audiencesFor(config, provider);
  if (audience.length === 0) {
    throw new OauthIdentityError(
      'OAUTH_PROVIDER_NOT_CONFIGURED',
      `Sign in with ${provider} is not configured on this server`,
    );
  }

  let payload;
  try {
    ({ payload } = await jwtVerify(idToken, jwksFor(spec.jwksUri), {
      issuer: spec.issuers,
      audience,
      // The providers' own tokens are short-lived; jose enforces `exp` by
      // default. A minute of slack absorbs clock skew between the device that
      // was issued the token and this server.
      clockTolerance: 60,
    }));
  } catch (err) {
    throw new OauthIdentityError('OAUTH_TOKEN_INVALID', `Token rejected: ${err.message}`);
  }

  const subject = payload.sub;
  if (!subject) {
    throw new OauthIdentityError('OAUTH_TOKEN_INVALID', 'Token carries no subject');
  }

  // Apple sends the e-mail only on the FIRST authorisation, and only when the
  // user agreed to share it; on every later sign-in the token has `sub` and
  // nothing else. So `sub` is the identity, and e-mail is a bonus — an account
  // keyed on e-mail alone would lose Apple users on their second sign-in.
  const email = typeof payload.email === 'string' ? payload.email.toLowerCase() : null;

  // Google sends a boolean, Apple a string. Both are the provider telling us
  // whether IT verified the address; anything else is treated as unverified.
  const rawVerified = payload.email_verified;
  const emailVerified = rawVerified === true || rawVerified === 'true';

  return {
    provider,
    subject,
    email,
    emailVerified,
    name: typeof payload.name === 'string' && payload.name.trim() ? payload.name.trim() : null,
  };
}

/** Test seam: drop cached JWKS clients between cases. */
export function resetJwksCacheForTest() {
  jwks.clear();
}
