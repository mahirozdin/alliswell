import { SignJWT, exportJWK, generateKeyPair } from 'jose';
import { useLocalJwksForTest } from '../../src/lib/oauth-identity.js';

/**
 * Real ID tokens without the network (OPH-366): a local RSA key stands in for
 * Google's / Apple's JWKS, so signature, issuer, audience, expiry and nonce
 * are all checked for real by `verifyIdentityToken`.
 */

export const ISSUER = { google: 'https://accounts.google.com', apple: 'https://appleid.apple.com' };

/** A signer whose public key the given providers' JWKS lookups now answer with. */
export async function localProviderKeys(providers = ['google', 'apple']) {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'test-key', alg: 'RS256', use: 'sig' };
  for (const provider of providers) useLocalJwksForTest(provider, { keys: [jwk] });
  return privateKey;
}

/** A foreign key no JWKS knows — for "signed by somebody else". */
export async function foreignKey() {
  return (await generateKeyPair('RS256')).privateKey;
}

export async function signIdToken(
  key,
  {
    provider = 'google',
    audience,
    subject = 'sub-1',
    email,
    emailVerified,
    nonce,
    issuer,
    expiresIn = '10m',
    extra = {},
  } = {},
) {
  const claims = { ...extra };
  if (email !== undefined) claims.email = email;
  if (emailVerified !== undefined) claims.email_verified = emailVerified;
  if (nonce !== undefined) claims.nonce = nonce;
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setIssuer(issuer ?? ISSUER[provider])
    .setAudience(audience)
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(key);
}
