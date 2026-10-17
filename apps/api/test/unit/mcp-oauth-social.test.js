import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { resetJwksCacheForTest } from '../../src/lib/oauth-identity.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { localProviderKeys, signIdToken } from '../helpers/idtoken.js';
import {
  FORM_HEADERS,
  REDIRECT_URI,
  exchangeCode,
  formEncode,
  formTokenFrom,
  pkcePair,
  registerMcpClient,
  rpc,
} from '../helpers/mcpdance.js';
import {
  beginSocial,
  openConsent,
  postCallback,
  postContinue,
  stepTokenFrom,
} from '../helpers/socialdance.js';

/**
 * OPH-366 (ADR-0049) — "Continue with Google / Apple" on the MCP consent page.
 *
 * The ID tokens here are REAL signatures against a local key that stands in
 * for the providers' JWKS, so the audience pin and the nonce binding are
 * exercised by the route, not assumed by a stub.
 */

const WEB = 'web.apps.googleusercontent.com';
const SERVICE = 'space.alliswell.web';
const PUBLIC = 'https://api.test.example';

const socialConfig = loadConfig({
  NODE_ENV: 'test',
  RATE_LIMIT_AUTH_MAX: '1000',
  API_PUBLIC_URL: PUBLIC,
  SIGN_IN_GOOGLE_WEB_CLIENT_ID: WEB,
  SIGN_IN_GOOGLE_IOS_CLIENT_ID: 'ios.apps.googleusercontent.com',
  SIGN_IN_APPLE_SERVICE_ID: SERVICE,
  SIGN_IN_APPLE_BUNDLE_ID: 'com.alliswell.alliswell',
});

let app;
let tables;
let key;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp({ config: socialConfig }));
  key = await localProviderKeys();
});

afterEach(() => {
  resetJwksCacheForTest();
});

/** A Google-only account made the way the app makes one. */
async function socialOnlyUser({ subject = 'g-sub-1', email = 'social@example.com', name } = {}) {
  const idToken = await signIdToken(key, {
    audience: WEB,
    subject,
    email,
    emailVerified: true,
    ...(name ? { extra: { name } } : {}),
  });
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/oauth',
    payload: { provider: 'google', idToken },
  });
  expect(res.statusCode).toBe(201);
  return res.json().user;
}

const googleToken = (nonce, fields = {}) =>
  signIdToken(key, { audience: WEB, subject: 'g-sub-1', nonce, ...fields });

describe('consent page buttons', () => {
  it('shows Google and Apple when both are configured, after the password form', async () => {
    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    expect(page.body).toContain('Continue with Google');
    expect(page.body).toContain('Continue with Apple');
    expect(page.body).toContain(`action="${PUBLIC}/oauth/authorize/social"`);
    // A separate form after the password form: Enter in the password field
    // submits Approve (first in DOM), never a provider.
    const passwordForm = page.body.indexOf('name="password"');
    const socialForm = page.body.indexOf('/oauth/authorize/social');
    expect(passwordForm).toBeLessThan(socialForm);
    expect(page.body.indexOf('value="approve"')).toBeLessThan(page.body.indexOf('value="deny"'));
    // Deny must submit with the required fields empty.
    expect(page.body).toContain('value="deny" formnovalidate');
  });

  it('OPH-383: the card fits a 390 px phone (border-box, smaller padding when narrow)', async () => {
    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    const card = page.body.match(/\.card\{([^}]*)\}/)[1];
    // Without border-box the 32 px padding sat outside calc(100% - …) and the
    // card overflowed a 390 px screen (scrollWidth 399).
    expect(card).toContain('box-sizing:border-box');
    expect(card).toContain('width:calc(100% - 32px)');
    expect(page.body).toMatch(/@media \(max-width:420px\)\{\.card\{padding:20px\}\}/);
    // The social buttons stay full width of the card.
    expect(page.body).toMatch(/\.social button\{[^}]*width:100%/);
  });

  it('shows neither button nor divider when no provider is configured', async () => {
    const plain = await buildTestApp();
    const client = await registerMcpClient(plain.app);
    const page = await openConsent(plain.app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    expect(page.body).not.toContain('Continue with');
    expect(page.body).not.toContain('or / veya');
    expect(page.body).not.toContain('/oauth/authorize/social');
  });

  it('hides Apple on an http public URL (Apple refuses http return URLs)', async () => {
    const httpApp = await buildTestApp({
      config: loadConfig({
        NODE_ENV: 'test',
        API_PUBLIC_URL: 'http://localhost:3000',
        SIGN_IN_GOOGLE_WEB_CLIENT_ID: WEB,
        SIGN_IN_APPLE_SERVICE_ID: SERVICE,
      }),
    });
    const client = await registerMcpClient(httpApp.app);
    const page = await openConsent(httpApp.app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    expect(page.body).toContain('Continue with Google');
    expect(page.body).not.toContain('Continue with Apple');
    const res = await httpApp.app.inject({
      method: 'POST',
      url: '/oauth/authorize/social',
      headers: FORM_HEADERS,
      payload: formEncode({ formToken: formTokenFrom(page.body), provider: 'apple' }),
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('the provider redirect', () => {
  it('Google: web client, our callback, form_post, nonce, and a state carrying the request', async () => {
    const { client, pkce, url, providerParams } = await beginSocial(app, { state: 'orig-state' });
    expect(url.origin + url.pathname).toBe('https://accounts.google.com/o/oauth2/v2/auth');
    expect(providerParams).toMatchObject({
      client_id: WEB,
      redirect_uri: `${PUBLIC}/oauth/authorize/callback`,
      response_type: 'id_token',
      response_mode: 'form_post',
      scope: 'openid email',
    });
    expect(providerParams.nonce.length).toBeGreaterThanOrEqual(43);
    const state = app.jwt.verify(providerParams.state);
    expect(state).toMatchObject({
      purpose: 'mcp_social',
      p: 'google',
      n: providerParams.nonce,
      c: client.client_id,
      r: REDIRECT_URI,
      cc: pkce.challenge,
      st: 'orig-state',
    });
  });

  it('Apple: Services ID, code id_token, form_post', async () => {
    const { url, providerParams } = await beginSocial(app, { provider: 'apple' });
    expect(url.origin + url.pathname).toBe('https://appleid.apple.com/auth/authorize');
    expect(providerParams).toMatchObject({
      client_id: SERVICE,
      redirect_uri: `${PUBLIC}/oauth/authorize/callback`,
      response_type: 'code id_token',
      response_mode: 'form_post',
    });
  });

  it('an unknown provider or an expired form is refused', async () => {
    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    const bad = await app.inject({
      method: 'POST',
      url: '/oauth/authorize/social',
      headers: FORM_HEADERS,
      payload: formEncode({ formToken: formTokenFrom(page.body), provider: 'github' }),
    });
    expect(bad.statusCode).toBe(400);
    const expired = await app.inject({
      method: 'POST',
      url: '/oauth/authorize/social',
      headers: FORM_HEADERS,
      payload: formEncode({ formToken: 'nope', provider: 'google' }),
    });
    expect(expired.statusCode).toBe(400);
    expect(expired.body).toContain('The form expired');
  });
});

describe('a social-only user completes consent', () => {
  it('callback → "Signed in as" → approve → code → token → /mcp works', async () => {
    const user = await socialOnlyUser();
    const { client, pkce, state, nonce } = await beginSocial(app, { state: 'orig-state' });

    const step = await postCallback(app, { state, id_token: await googleToken(nonce) });
    expect(step.statusCode).toBe(200);
    expect(step.body).toContain('Signed in as');
    expect(step.body).toContain('social@example.com');
    expect(step.body).toContain('with Google');
    expect(step.body).not.toContain('name="totpCode"');
    // Explicit approval is required even with one workspace and no 2FA.
    expect(tables.oauth_codes).toHaveLength(0);

    const approve = await postContinue(app, {
      stepToken: stepTokenFrom(step.body),
      decision: 'approve',
    });
    expect(approve.statusCode).toBe(302);
    const location = new URL(approve.headers.location);
    expect(location.origin + location.pathname).toBe(REDIRECT_URI);
    expect(location.searchParams.get('state')).toBe('orig-state');
    const code = location.searchParams.get('code');
    expect(tables.oauth_codes[0].user_id).toBe(user.id);

    const tokens = await exchangeCode(app, {
      clientId: client.client_id,
      code,
      verifier: pkce.verifier,
    });
    expect(tokens.statusCode).toBe(200);
    const list = await rpc(app, tokens.json().access_token, 'tools/list');
    expect(list.statusCode).toBe(200);
    expect(list.json().result.tools.length).toBeGreaterThan(0);
  });

  it('a code issued via social is bound to the original PKCE challenge', async () => {
    await socialOnlyUser();
    const { client, state, nonce } = await beginSocial(app);
    const step = await postCallback(app, { state, id_token: await googleToken(nonce) });
    const approve = await postContinue(app, {
      stepToken: stepTokenFrom(step.body),
      decision: 'approve',
    });
    const code = new URL(approve.headers.location).searchParams.get('code');
    const wrong = await exchangeCode(app, {
      clientId: client.client_id,
      code,
      verifier: pkcePair().verifier,
    });
    expect(wrong.statusCode).toBe(400);
    expect(wrong.json().error).toBe('invalid_grant');
  });

  it('Deny on the step page bounces access_denied with the original state', async () => {
    await socialOnlyUser();
    const { state, nonce } = await beginSocial(app, { state: 'orig-state' });
    const step = await postCallback(app, { state, id_token: await googleToken(nonce) });
    expect(step.body).toContain('value="deny" formnovalidate');
    const deny = await postContinue(app, { stepToken: stepTokenFrom(step.body), decision: 'deny' });
    expect(deny.statusCode).toBe(302);
    const location = new URL(deny.headers.location);
    expect(location.searchParams.get('error')).toBe('access_denied');
    expect(location.searchParams.get('state')).toBe('orig-state');
    expect(tables.oauth_codes).toHaveLength(0);
  });

  it('several workspaces: the step page asks which, and refuses a foreign one', async () => {
    const user = await socialOnlyUser();
    tables.workspaces.push({ id: 'W2'.padEnd(26, '0'), name: 'Second', owner_id: user.id });
    tables.workspace_members.push({
      id: 'M2'.padEnd(26, '0'),
      workspace_id: 'W2'.padEnd(26, '0'),
      user_id: user.id,
      role: 'owner',
    });
    const { state, nonce } = await beginSocial(app);
    const step = await postCallback(app, { state, id_token: await googleToken(nonce) });
    expect(step.body).toContain('name="workspaceId"');
    const stepToken = stepTokenFrom(step.body);
    const foreign = await postContinue(app, {
      stepToken,
      decision: 'approve',
      workspaceId: 'X'.padEnd(26, '0'),
    });
    expect(foreign.statusCode).toBe(200);
    expect(foreign.body).toContain('Pick one of your own workspaces');
    const ok = await postContinue(app, {
      stepToken,
      decision: 'approve',
      workspaceId: 'W2'.padEnd(26, '0'),
    });
    expect(ok.statusCode).toBe(302);
    expect(tables.oauth_codes[0].workspace_id).toBe('W2'.padEnd(26, '0'));
  });
});

describe('verification failures land back on consent, with no code', () => {
  it('a wrong-audience id_token re-renders consent with a fresh form token', async () => {
    await socialOnlyUser();
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, {
      state,
      id_token: await googleToken(nonce, { audience: 'someone-else.apps.googleusercontent.com' }),
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('Could not verify your Google sign-in');
    expect(res.body).not.toContain('Signed in as');
    // The fresh form token is a real one: the password form works from it.
    expect(app.jwt.verify(formTokenFrom(res.body)).purpose).toBe('mcp_authorize');
    expect(tables.oauth_codes).toHaveLength(0);
  });

  it('our own iOS client id is refused too: the redirect used the web client', async () => {
    await socialOnlyUser();
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, {
      state,
      id_token: await googleToken(nonce, { audience: 'ios.apps.googleusercontent.com' }),
    });
    expect(res.body).toContain('Could not verify');
  });

  it('Apple user_cancelled_authorize re-renders consent with the cancelled message', async () => {
    const { state } = await beginSocial(app, { provider: 'apple' });
    const res = await postCallback(app, { state, error: 'user_cancelled_authorize' });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('Sign-in was cancelled');
    expect(res.body).toContain('name="password"');
  });

  it('the password form re-rendered by the callback still posts to /oauth/authorize', async () => {
    await registerUser(app, { email: 'owner@example.com' });
    const { state } = await beginSocial(app);
    const back = await postCallback(app, { state, error: 'access_denied' });
    // An empty action would resolve against /oauth/authorize/callback in a
    // real browser and land on "The form expired".
    expect(back.body).toContain(`<form method="post" action="${PUBLIC}/oauth/authorize">`);
    const res = await app.inject({
      method: 'POST',
      url: new URL(`${PUBLIC}/oauth/authorize`).pathname,
      headers: FORM_HEADERS,
      payload: formEncode({
        formToken: formTokenFrom(back.body),
        email: 'owner@example.com',
        password: 'test-password-1',
        decision: 'approve',
      }),
    });
    expect(res.statusCode).toBe(302);
    expect(new URL(res.headers.location).searchParams.get('state')).toBe('st1');
  });
});

describe('CSRF / state binding', () => {
  it('a forged, tampered or wrong-purpose state is the expired page', async () => {
    await socialOnlyUser();
    const { state, nonce } = await beginSocial(app);
    const idToken = await googleToken(nonce);
    const [header, payload, signature] = state.split('.');
    const tamperedPayload = Buffer.from(
      JSON.stringify({ ...JSON.parse(Buffer.from(payload, 'base64url')), r: 'https://evil/cb' }),
    ).toString('base64url');
    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    for (const bad of [
      'forged',
      `${header}.${tamperedPayload}.${signature}`,
      formTokenFrom(page.body), // a form token is not a social state
    ]) {
      const res = await postCallback(app, { state: bad, id_token: idToken });
      expect(res.statusCode).toBe(400);
      expect(res.body).toContain('The form expired');
    }
    expect(tables.oauth_codes).toHaveLength(0);
  });

  it('a valid state with an id_token carrying another nonce is rejected', async () => {
    await socialOnlyUser();
    const first = await beginSocial(app);
    const second = await beginSocial(app);
    // A token issued for the SECOND request, replayed against the first.
    const res = await postCallback(app, {
      state: first.state,
      id_token: await googleToken(second.nonce),
    });
    expect(res.body).toContain('Could not verify your Google sign-in');
    expect(res.body).not.toContain('Signed in as');
  });

  it('purposes never cross: a step token is not a form token and vice versa', async () => {
    await socialOnlyUser();
    const { state, nonce } = await beginSocial(app);
    const step = await postCallback(app, { state, id_token: await googleToken(nonce) });
    const stepToken = stepTokenFrom(step.body);
    const asForm = await app.inject({
      method: 'POST',
      url: '/oauth/authorize',
      headers: FORM_HEADERS,
      payload: formEncode({ formToken: stepToken, decision: 'approve' }),
    });
    expect(asForm.statusCode).toBe(400);

    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    const asStep = await postContinue(app, {
      stepToken: formTokenFrom(page.body),
      decision: 'approve',
    });
    expect(asStep.statusCode).toBe(400);
    const stateAsStep = await postContinue(app, { stepToken: state, decision: 'approve' });
    expect(stateAsStep.statusCode).toBe(400);
    // And a step token is never an access token.
    const asBearer = await rpc(app, stepToken, 'tools/list');
    expect(asBearer.statusCode).toBe(401);
    expect(tables.oauth_codes).toHaveLength(0);
  });
});

describe('account rules: the consent page never creates an account', () => {
  it('unknown subject with an unverified email → "No AllisWell account", nothing written', async () => {
    const before = {
      users: tables.users.length,
      workspaces: tables.workspaces.length,
      identities: tables.user_identities.length,
    };
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, {
      state,
      id_token: await googleToken(nonce, {
        subject: 'stranger',
        email: 'stranger@example.com',
        emailVerified: false,
      }),
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('No AllisWell account uses this Google account yet');
    expect({
      users: tables.users.length,
      workspaces: tables.workspaces.length,
      identities: tables.user_identities.length,
    }).toEqual(before);
  });

  it('unverified email matching a password account does NOT link', async () => {
    await registerUser(app, { email: 'owner@example.com' });
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, {
      state,
      id_token: await googleToken(nonce, {
        subject: 'attacker',
        email: 'owner@example.com',
        emailVerified: false,
      }),
    });
    expect(res.body).toContain('No AllisWell account');
    expect(tables.user_identities).toHaveLength(0);
  });

  it('verified email matching a password account links, and signs in as that account', async () => {
    const { user } = await registerUser(app, { email: 'owner@example.com' });
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, {
      state,
      id_token: await googleToken(nonce, {
        subject: 'g-owner',
        email: 'owner@example.com',
        emailVerified: true,
      }),
    });
    expect(res.body).toContain('Signed in as');
    expect(res.body).toContain('owner@example.com');
    expect(tables.user_identities).toHaveLength(1);
    expect(tables.user_identities[0]).toMatchObject({
      user_id: user.id,
      provider: 'google',
      subject: 'g-owner',
    });
    const approve = await postContinue(app, {
      stepToken: stepTokenFrom(res.body),
      decision: 'approve',
    });
    expect(approve.statusCode).toBe(302);
    expect(tables.oauth_codes[0].user_id).toBe(user.id);
  });

  it('a deleted account behind a known identity is refused, not resurrected', async () => {
    const user = await socialOnlyUser();
    tables.users.find((u) => u.id === user.id).deleted_at = new Date();
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, { state, id_token: await googleToken(nonce) });
    expect(res.body).toContain('No AllisWell account');
  });
});

describe('escaping on the step page', () => {
  it('a hostile display name and e-mail render as text', async () => {
    await socialOnlyUser({
      email: 'x"><script>alert(1)</script>@example.com',
      name: '<img src=x onerror=alert(2)>',
    });
    const { state, nonce } = await beginSocial(app);
    const res = await postCallback(app, { state, id_token: await googleToken(nonce) });
    expect(res.body).toContain('Signed in as');
    expect(res.body).not.toContain('<script>alert(1)</script>');
    expect(res.body).not.toContain('<img src=x');
    expect(res.body).toContain('&lt;script&gt;');
    expect(res.body).toContain('&lt;img src=x onerror=alert(2)&gt;');
  });

  it('a hostile EE refusal message renders as text on the password path', async () => {
    await registerUser(app, { email: 'policy@example.com' });
    app.ee.signInRequirements.push(async () => ({
      code: 'POLICY_NO',
      message: '<script>alert(3)</script>',
    }));
    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/authorize',
      headers: FORM_HEADERS,
      payload: formEncode({
        formToken: formTokenFrom(page.body),
        email: 'policy@example.com',
        password: 'test-password-1',
        decision: 'approve',
      }),
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('&lt;script&gt;alert(3)&lt;/script&gt;');
    expect(res.body).not.toContain('<script>alert(3)');
    expect(tables.oauth_codes).toHaveLength(0);
  });
});
