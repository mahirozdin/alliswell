import { describe, it, expect, beforeAll, afterAll } from 'vitest';

import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { resetJwksCacheForTest } from '../../src/lib/oauth-identity.js';
import { totp } from '../../src/lib/totp.js';
import { localProviderKeys, signIdToken } from '../helpers/idtoken.js';
import {
  FORM_HEADERS,
  exchangeCode,
  formEncode,
  formTokenFrom,
  fullDance,
  pkcePair,
  registerMcpClient,
} from '../helpers/mcpdance.js';
import {
  beginSocial,
  openConsent,
  postCallback,
  postContinue,
  stepTokenFrom,
} from '../helpers/socialdance.js';

// Needs real MySQL + Redis with migrations applied (see integration/ready.test.js).
const enabled = process.env.INTEGRATION === '1';
const emailPrefix = `oph366-${Date.now()}`;
const WEB = 'web.apps.googleusercontent.com';

/**
 * OPH-366 (ADR-0049) — the MCP consent page is a sign-in, so the second
 * factor and the extension's sign-in policy apply to it exactly as they do to
 * /auth/login: on the new Google / Apple path AND on the password path, which
 * skipped both until this change. Real MySQL because the factor's recovery
 * codes and spent-step bookkeeping are only real there.
 */
describe.runIf(enabled)('integration: MCP consent second factor', () => {
  let app;
  let key;
  let social; // { id, secret, recoveryCodes, accessToken }
  let password; // { id, email, secret }

  const asBearer = (token, method, url, payload) =>
    app.inject({
      method,
      url,
      headers: { authorization: `Bearer ${token}` },
      ...(payload ? { payload } : {}),
    });

  /** The mfa.test.js trick: clear the spent marker, then a code for now. */
  const freshCode = async (who) => {
    await app.db('user_totp').where({ user_id: who.id }).update({ last_step: null });
    return totp(who.secret);
  };

  async function enrol(accessToken, who) {
    const started = await asBearer(accessToken, 'POST', '/api/v1/auth/mfa/totp');
    expect(started.statusCode).toBe(201);
    who.secret = started.json().secret;
    const confirmed = await asBearer(accessToken, 'POST', '/api/v1/auth/mfa/totp/confirm', {
      code: await freshCode(who),
    });
    expect(confirmed.statusCode).toBe(200);
    who.recoveryCodes = confirmed.json().recoveryCodes;
  }

  const codesFor = async (userId) => {
    const [{ n }] = await app.db('oauth_codes').where({ user_id: userId }).count({ n: '*' });
    return Number(n);
  };

  async function socialStep() {
    const begun = await beginSocial(app);
    const idToken = await signIdToken(key, {
      audience: WEB,
      subject: `${emailPrefix}-g`,
      nonce: begun.nonce,
    });
    const step = await postCallback(app, { state: begun.state, id_token: idToken });
    expect(step.statusCode).toBe(200);
    return { ...begun, step, stepToken: stepTokenFrom(step.body) };
  }

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '1000',
        API_PUBLIC_URL: 'https://api.test.example',
        SIGN_IN_GOOGLE_WEB_CLIENT_ID: WEB,
      }),
    });
    key = await localProviderKeys(['google']);

    // A Google-only account, made the way the app makes one.
    const created = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/oauth',
      payload: {
        provider: 'google',
        idToken: await signIdToken(key, {
          audience: WEB,
          subject: `${emailPrefix}-g`,
          email: `${emailPrefix}-social@example.com`,
          emailVerified: true,
        }),
      },
    });
    expect(created.statusCode).toBe(201);
    social = { id: created.json().user.id, accessToken: created.json().tokens.accessToken };
    await enrol(social.accessToken, social);

    const registered = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-pw@example.com`, password: 'integration-pw-1' },
    });
    expect(registered.statusCode).toBe(201);
    password = { id: registered.json().user.id, email: `${emailPrefix}-pw@example.com` };
    await enrol(registered.json().tokens.accessToken, password);
  });

  afterAll(async () => {
    resetJwksCacheForTest();
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('oauth_tokens').whereIn('user_id', ids).delete();
      await app.db('oauth_codes').whereIn('user_id', ids).delete();
      await app.db('user_identities').whereIn('user_id', ids).delete();
      await app.db('user_totp_recovery_codes').whereIn('user_id', ids).delete();
      await app.db('user_totp').whereIn('user_id', ids).delete();
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('workspace_members').whereIn('user_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('social path: an MFA user is challenged, and only the right code grants', async () => {
    const { step, stepToken, client, pkce } = await socialStep();
    expect(step.body).toContain('name="totpCode"');

    const none = await postContinue(app, { stepToken, decision: 'approve' });
    expect(none.statusCode).toBe(200);
    expect(none.body).toContain('That code is not right');
    const wrong = await postContinue(app, { stepToken, decision: 'approve', totpCode: '000000' });
    expect(wrong.body).toContain('That code is not right');
    expect(await codesFor(social.id)).toBe(0);

    const right = await postContinue(app, {
      stepToken,
      decision: 'approve',
      totpCode: await freshCode(social),
    });
    expect(right.statusCode).toBe(302);
    const code = new URL(right.headers.location).searchParams.get('code');
    const tokens = await exchangeCode(app, {
      clientId: client.client_id,
      code,
      verifier: pkce.verifier,
    });
    expect(tokens.statusCode).toBe(200);
  });

  it('password path: the right password leads to the code step, not a code', async () => {
    const client = await registerMcpClient(app);
    const page = await openConsent(app, {
      clientId: client.client_id,
      challenge: pkcePair().challenge,
    });
    const before = await codesFor(password.id);
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/authorize',
      headers: FORM_HEADERS,
      payload: formEncode({
        formToken: formTokenFrom(page.body),
        email: password.email,
        password: 'integration-pw-1',
        decision: 'approve',
      }),
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('Signed in as');
    expect(res.body).toContain('name="totpCode"');
    expect(await codesFor(password.id)).toBe(before);

    const stepToken = stepTokenFrom(res.body);
    const none = await postContinue(app, { stepToken, decision: 'approve' });
    expect(none.body).toContain('That code is not right');
    const right = await postContinue(app, {
      stepToken,
      decision: 'approve',
      totpCode: await freshCode(password),
    });
    expect(right.statusCode).toBe(302);
    expect(await codesFor(password.id)).toBe(before + 1);
  });

  it('a recovery code works on the consent step exactly once', async () => {
    const recovery = social.recoveryCodes[0];
    const first = await socialStep();
    const ok = await postContinue(app, {
      stepToken: first.stepToken,
      decision: 'approve',
      totpCode: recovery,
    });
    expect(ok.statusCode).toBe(302);

    const second = await socialStep();
    const again = await postContinue(app, {
      stepToken: second.stepToken,
      decision: 'approve',
      totpCode: recovery,
    });
    expect(again.statusCode).toBe(200);
    expect(again.body).toContain('That code is not right');
  });

  it('an extension sign-in requirement that refuses blocks the consent', async () => {
    app.ee.signInRequirements.push(async ({ factors }) =>
      factors.totpVerified ? { code: 'POLICY_NO', message: 'Not today' } : null,
    );
    try {
      const before = await codesFor(social.id);
      const { stepToken } = await socialStep();
      const res = await postContinue(app, {
        stepToken,
        decision: 'approve',
        totpCode: await freshCode(social),
      });
      expect(res.statusCode).toBe(200);
      expect(res.body).toContain('Not today');
      expect(await codesFor(social.id)).toBe(before);
    } finally {
      app.ee.signInRequirements.pop();
    }
  });

  it('a password user without 2FA and one workspace still gets a direct redirect', async () => {
    const email = `${emailPrefix}-plain@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'integration-pw-1' },
    });
    expect(res.statusCode).toBe(201);
    // fullDance expects a single POST → 302.
    const { tokens } = await fullDance(app, { email, password: 'integration-pw-1' });
    expect(tokens.access_token).toBeTruthy();
  });
});
