import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { resetJwksCacheForTest, verifyIdentityToken } from '../../src/lib/oauth-identity.js';
import { foreignKey, localProviderKeys, signIdToken } from '../helpers/idtoken.js';

/**
 * ADR-0026's three checks, plus OPH-366's nonce and audience pin, with REAL
 * cryptography: a local key pair stands in for the providers' JWKS.
 */

const WEB = 'web.apps.googleusercontent.com';
const IOS = 'ios.apps.googleusercontent.com';
const SERVICE = 'space.alliswell.web';
const BUNDLE = 'com.alliswell.alliswell';

const config = loadConfig({
  NODE_ENV: 'test',
  SIGN_IN_GOOGLE_WEB_CLIENT_ID: WEB,
  SIGN_IN_GOOGLE_IOS_CLIENT_ID: IOS,
  SIGN_IN_APPLE_SERVICE_ID: SERVICE,
  SIGN_IN_APPLE_BUNDLE_ID: BUNDLE,
});

let key;

beforeEach(async () => {
  key = await localProviderKeys();
});

afterEach(() => {
  resetJwksCacheForTest();
});

const rejected = (promise) =>
  expect(promise).rejects.toMatchObject({ code: 'OAUTH_TOKEN_INVALID' });

describe('verifyIdentityToken (ADR-0026, OPH-366)', () => {
  it('accepts a genuine Google token and reports the identity', async () => {
    const idToken = await signIdToken(key, {
      audience: WEB,
      email: 'Ada@Example.com',
      emailVerified: true,
    });
    await expect(verifyIdentityToken(config, { provider: 'google', idToken })).resolves.toEqual({
      provider: 'google',
      subject: 'sub-1',
      email: 'ada@example.com',
      emailVerified: true,
      name: null,
    });
  });

  it('accepts a genuine Apple token audienced to the Services ID', async () => {
    const idToken = await signIdToken(key, {
      provider: 'apple',
      audience: SERVICE,
      emailVerified: 'true',
      email: 'x@privaterelay.appleid.com',
    });
    const identity = await verifyIdentityToken(config, { provider: 'apple', idToken });
    expect(identity).toMatchObject({ provider: 'apple', emailVerified: true });
  });

  it('rejects a token minted for somebody else’s application (wrong audience)', async () => {
    const idToken = await signIdToken(key, { audience: 'someone-else.apps.googleusercontent.com' });
    await rejected(verifyIdentityToken(config, { provider: 'google', idToken }));
  });

  it('with an audience pin, refuses our OWN other client', async () => {
    const idToken = await signIdToken(key, { audience: IOS, nonce: 'n' });
    // Accepted by the app path, which takes every one of our client ids…
    await expect(
      verifyIdentityToken(config, { provider: 'google', idToken }),
    ).resolves.toBeTruthy();
    // …refused by the consent page, which only ever redirected with the web one.
    await rejected(
      verifyIdentityToken(config, { provider: 'google', idToken, nonce: 'n', audience: [WEB] }),
    );
  });

  it('an audience pin that is not one of ours refuses instead of widening', async () => {
    const idToken = await signIdToken(key, { audience: 'evil' });
    await expect(
      verifyIdentityToken(config, { provider: 'google', idToken, audience: ['evil'] }),
    ).rejects.toMatchObject({ code: 'OAUTH_PROVIDER_NOT_CONFIGURED' });
  });

  it('rejects a wrong issuer', async () => {
    const idToken = await signIdToken(key, { audience: WEB, issuer: 'https://evil.example' });
    await rejected(verifyIdentityToken(config, { provider: 'google', idToken }));
  });

  it('rejects a nonce mismatch and a missing nonce when one is expected', async () => {
    const other = await signIdToken(key, { audience: WEB, nonce: 'other' });
    await rejected(
      verifyIdentityToken(config, { provider: 'google', idToken: other, nonce: 'n1' }),
    );
    const none = await signIdToken(key, { audience: WEB });
    await rejected(verifyIdentityToken(config, { provider: 'google', idToken: none, nonce: 'n1' }));
    const right = await signIdToken(key, { audience: WEB, nonce: 'n1' });
    await expect(
      verifyIdentityToken(config, { provider: 'google', idToken: right, nonce: 'n1' }),
    ).resolves.toBeTruthy();
  });

  it('rejects an expired token', async () => {
    const idToken = await signIdToken(key, {
      audience: WEB,
      expiresIn: Math.floor(Date.now() / 1000) - 600,
    });
    await rejected(verifyIdentityToken(config, { provider: 'google', idToken }));
  });

  it('rejects a token signed by another key', async () => {
    const idToken = await signIdToken(await foreignKey(), { audience: WEB });
    await rejected(verifyIdentityToken(config, { provider: 'google', idToken }));
  });
});
