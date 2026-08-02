import { describe, it, expect, beforeEach, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';
import * as identity from '../../src/lib/oauth-identity.js';

/**
 * OPH-231 — Sign in with Google / Apple (ADR-0026).
 *
 * The cryptography is `jose`'s job and is not re-tested here; what IS tested is
 * the account-matching rule, which is where this feature can go wrong in a way
 * that hands somebody else's tasks to a stranger.
 *
 * `verifyIdentityToken` is stubbed so each case can state the identity a token
 * asserts. That is the correct seam: the route's contract is "given a verified
 * identity, which account is this?", and pretending to mint real Google
 * signatures would test jose rather than us.
 */

const testConfig = loadConfig({
  NODE_ENV: 'test',
  SIGN_IN_GOOGLE_WEB_CLIENT_ID: 'web.apps.googleusercontent.com',
  SIGN_IN_APPLE_BUNDLE_ID: 'com.alliswell.alliswell',
});

async function buildTestApp() {
  const { db, tables } = fakeDb();
  const app = await buildApp({ config: testConfig, db, redis: fakeRedis() });
  return { app, tables };
}

const oauth = (app, payload) => app.inject({ method: 'POST', url: '/api/v1/auth/oauth', payload });

const register = (app, payload) =>
  app.inject({ method: 'POST', url: '/api/v1/auth/register', payload });

/** Make the next verification return this identity. */
function asIdentity(fields) {
  vi.spyOn(identity, 'verifyIdentityToken').mockResolvedValue({
    provider: 'google',
    subject: 'sub-1',
    email: null,
    emailVerified: false,
    name: null,
    ...fields,
  });
}

const A_TOKEN = 'header.payload.signature';

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('POST /api/v1/auth/oauth (OPH-231)', () => {
  it('creates an account, workspace and session on a first sign-in', async () => {
    const { app, tables } = await buildTestApp();
    asIdentity({ email: 'mahir@example.com', emailVerified: true, name: 'Mahir' });

    const res = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.created).toBe(true);
    expect(body.user.email).toBe('mahir@example.com');
    expect(body.user.displayName).toBe('Mahir');

    const claims = app.jwt.verify(body.tokens.accessToken);
    expect(claims.sub).toBe(body.user.id);

    // The account is provider-only until the user sets a password.
    expect(tables.users[0].password_hash).toBeNull();
    // And it owns a workspace, exactly like a registered account.
    expect(tables.workspaces).toHaveLength(1);
    expect(tables.workspace_members[0].role).toBe('owner');
    expect(tables.user_identities[0]).toMatchObject({
      provider: 'google',
      subject: 'sub-1',
      email: 'mahir@example.com',
    });
  });

  it('signs the SAME user in the second time, without creating anything', async () => {
    const { app, tables } = await buildTestApp();
    asIdentity({ email: 'mahir@example.com', emailVerified: true });
    const first = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    asIdentity({ email: 'mahir@example.com', emailVerified: true });
    const second = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    expect(second.statusCode).toBe(200);
    expect(second.json().created).toBe(false);
    expect(second.json().user.id).toBe(first.json().user.id);
    expect(tables.users).toHaveLength(1);
    expect(tables.user_identities).toHaveLength(1);
  });

  it('recognises the subject even when the provider stops sending an e-mail', async () => {
    // Apple's actual behaviour: the address arrives on the first authorisation
    // and never again. Keying on e-mail would strand the user here.
    const { app, tables } = await buildTestApp();
    asIdentity({
      provider: 'apple',
      subject: 'apple-sub',
      email: 'x@privaterelay.appleid.com',
      emailVerified: true,
    });
    const first = await oauth(app, { provider: 'apple', idToken: A_TOKEN });

    asIdentity({ provider: 'apple', subject: 'apple-sub', email: null, emailVerified: false });
    const second = await oauth(app, { provider: 'apple', idToken: A_TOKEN });

    expect(second.statusCode).toBe(200);
    expect(second.json().user.id).toBe(first.json().user.id);
    expect(tables.users).toHaveLength(1);
  });

  it('links to an existing password account when the provider VERIFIED the e-mail', async () => {
    const { app, tables } = await buildTestApp();
    const registered = await register(app, {
      email: 'mahir@example.com',
      password: 'correct-horse-battery',
      displayName: 'Mahir',
    });

    asIdentity({ email: 'mahir@example.com', emailVerified: true });
    const res = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    expect(res.statusCode).toBe(200);
    expect(res.json().created).toBe(false);
    expect(res.json().user.id).toBe(registered.json().user.id);
    expect(tables.users).toHaveLength(1);
    // The password still works — linking adds a way in, it does not replace one.
    expect(tables.users[0].password_hash).not.toBeNull();
  });

  it('REFUSES to link on an unverified e-mail — the account-takeover path', async () => {
    // The whole point. An unverified `email` claim is a string the provider
    // passed along without vouching for it; treating it as proof of ownership
    // would let anyone who can put an address in a token adopt that account.
    const { app, tables } = await buildTestApp();
    await register(app, {
      email: 'victim@example.com',
      password: 'correct-horse-battery',
    });

    asIdentity({ subject: 'attacker-sub', email: 'victim@example.com', emailVerified: false });
    const res = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('OAUTH_EMAIL_TAKEN');
    // No link, no second account, no session.
    expect(tables.users).toHaveLength(1);
    expect(tables.user_identities ?? []).toHaveLength(0);
  });

  it('keeps two providers for one person on ONE account', async () => {
    const { app, tables } = await buildTestApp();
    asIdentity({
      provider: 'google',
      subject: 'g-1',
      email: 'mahir@example.com',
      emailVerified: true,
    });
    const viaGoogle = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    asIdentity({
      provider: 'apple',
      subject: 'a-1',
      email: 'mahir@example.com',
      emailVerified: true,
    });
    const viaApple = await oauth(app, { provider: 'apple', idToken: A_TOKEN });

    expect(viaApple.json().user.id).toBe(viaGoogle.json().user.id);
    expect(tables.users).toHaveLength(1);
    expect(tables.user_identities).toHaveLength(2);
  });

  it('gives an account with no e-mail a stable synthetic one', async () => {
    // Apple's "Hide My Email" with sharing declined: no address at all. The
    // account still needs a unique non-null e-mail, and it must be stable so the
    // same person does not accumulate accounts.
    const { app, tables } = await buildTestApp();
    asIdentity({ provider: 'apple', subject: 'no-mail-sub', email: null, emailVerified: false });

    const res = await oauth(app, { provider: 'apple', idToken: A_TOKEN });

    expect(res.statusCode).toBe(201);
    expect(res.json().user.email).toBe('apple_no-mail-sub@users.noreply.alliswell.space');
    expect(tables.users).toHaveLength(1);
  });

  it('rejects a token the verifier refuses', async () => {
    const { app } = await buildTestApp();
    vi.spyOn(identity, 'verifyIdentityToken').mockRejectedValue(
      new identity.OauthIdentityError('OAUTH_TOKEN_INVALID', 'Token rejected: bad signature'),
    );

    const res = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('OAUTH_TOKEN_INVALID');
  });

  it('says so when the provider is not configured on this server', async () => {
    const { app } = await buildTestApp();
    vi.spyOn(identity, 'verifyIdentityToken').mockRejectedValue(
      new identity.OauthIdentityError(
        'OAUTH_PROVIDER_NOT_CONFIGURED',
        'Sign in with google is not configured on this server',
      ),
    );

    const res = await oauth(app, { provider: 'google', idToken: A_TOKEN });

    // 503, not 401: nothing is wrong with the caller's token. A self-hoster who
    // never set the client IDs should read "this server does not do that".
    expect(res.statusCode).toBe(503);
    expect(res.json().code).toBe('OAUTH_PROVIDER_NOT_CONFIGURED');
  });

  it('refuses an unknown provider at the schema', async () => {
    const { app } = await buildTestApp();
    const res = await oauth(app, { provider: 'facebook', idToken: A_TOKEN });
    expect(res.statusCode).toBe(400);
  });
});

describe('audiencesFor (ADR-0026)', () => {
  // Built by loadConfig, NOT by hand. An earlier version of this test passed a
  // flat object of its own invention and happily agreed with an implementation
  // that read fields the real config does not have — so every provider was
  // "not configured" in production while the suite stayed green.
  it('accepts every platform client id of the same provider', () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      SIGN_IN_GOOGLE_WEB_CLIENT_ID: 'web',
      SIGN_IN_GOOGLE_IOS_CLIENT_ID: 'ios',
    });
    expect(identity.audiencesFor(config, 'google')).toEqual(['web', 'ios']);
  });

  it('reads Apple from the same place', () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      SIGN_IN_APPLE_BUNDLE_ID: 'com.alliswell.alliswell',
    });
    expect(identity.audiencesFor(config, 'apple')).toEqual(['com.alliswell.alliswell']);
  });

  it('returns nothing when a provider is unconfigured, so the caller can refuse', () => {
    // An empty audience list MUST NOT be read as "accept anything" — that would
    // make every Google-issued token in the world valid here.
    const bare = loadConfig({ NODE_ENV: 'test' });
    expect(identity.audiencesFor(bare, 'google')).toEqual([]);
    expect(identity.audiencesFor(bare, 'apple')).toEqual([]);
    expect(identity.audiencesFor({}, 'google')).toEqual([]);
  });
});
