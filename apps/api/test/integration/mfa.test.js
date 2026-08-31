import { describe, it, expect, beforeAll, afterAll } from 'vitest';

import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { totp } from '../../src/lib/totp.js';

// Needs real MySQL + Redis with migrations applied (see integration/ready.test.js).
const enabled = process.env.INTEGRATION === '1';
const emailPrefix = `oph283-${Date.now()}`;

/// OPH-283 — the second factor end to end, and the password change beside it.
///
/// The unit suite proves the arithmetic against the RFC. What only a running
/// app proves is the part that is about people: that a staged factor protects
/// nothing, that a confirmed one cannot be skipped, that a code cannot be
/// spent twice, that losing the phone is survivable exactly ten times, and
/// that turning any of it off costs a live code.
describe.runIf(enabled)('integration: two-factor authentication', () => {
  let app;
  let user;
  let secret;
  let recoveryCodes;

  const register = (email) =>
    app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'integration-pw-1', displayName: 'Ada' },
    });

  const login = (payload) => app.inject({ method: 'POST', url: '/api/v1/auth/login', payload });

  const asUser = (method, url, payload) =>
    app.inject({
      method,
      url,
      headers: { authorization: `Bearer ${user.accessToken}` },
      ...(payload ? { payload } : {}),
    });

  /**
   * A code the server will accept right now.
   *
   * The obvious trick — generate one for a step in the future so it cannot
   * collide with a spent one — does not work, and finding that out is worth a
   * comment: the server verifies against ITS clock with a one-step window, so
   * a code minted sixty seconds ahead is two steps away and simply wrong.
   *
   * So the code is always for now, and the SPENT MARKER is cleared instead.
   * That is honest surgery rather than a workaround: `last_step` is exactly
   * the state that makes a second call in the same thirty seconds fail, and
   * the test that cares about replay (below) does not call this.
   */
  const freshCode = async () => {
    await app.db('user_totp').where({ user_id: user.id }).update({ last_step: null });
    return totp(secret);
  };

  beforeAll(async () => {
    // The MFA routes carry the auth rate limit, and this suite makes far more
    // auth calls than a person would. Raising the ceiling here is not hiding
    // the limit — the limit is real, and it is what made these two tests 429
    // the first time they ran.
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000' }),
    });
    const res = await register(`${emailPrefix}-ada@example.com`);
    expect(res.statusCode).toBe(201);
    const body = res.json();
    user = { id: body.user.id, email: body.user.email, accessToken: body.tokens.accessToken };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('reports no factor before anything is set up', async () => {
    const res = await asUser('GET', '/api/v1/auth/mfa/totp');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ enrolled: false, staged: false, recoveryCodesLeft: 0 });
  });

  it('a STAGED secret protects nothing — sign-in is untouched', async () => {
    const started = await asUser('POST', '/api/v1/auth/mfa/totp');
    expect(started.statusCode).toBe(201);
    secret = started.json().secret;
    expect(started.json().uri).toContain('otpauth://totp/');

    expect((await asUser('GET', '/api/v1/auth/mfa/totp')).json()).toMatchObject({
      enrolled: false,
      staged: true,
    });
    // The point: somebody who closed the tab mid-setup is not locked out.
    const res = await login({ email: user.email, password: 'integration-pw-1' });
    expect(res.statusCode).toBe(200);
  });

  it('a wrong code does not enrol', async () => {
    const res = await asUser('POST', '/api/v1/auth/mfa/totp/confirm', { code: '000000' });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('TOTP_CODE_WRONG');
  });

  it('confirming turns it on and hands over the recovery codes once', async () => {
    const res = await asUser('POST', '/api/v1/auth/mfa/totp/confirm', { code: await freshCode() });
    expect(res.statusCode).toBe(200);
    recoveryCodes = res.json().recoveryCodes;
    expect(recoveryCodes).toHaveLength(10);
    expect(recoveryCodes[0]).toMatch(/^[0-9A-Z]{5}-[0-9A-Z]{5}$/);

    expect((await asUser('GET', '/api/v1/auth/mfa/totp')).json()).toEqual({
      enrolled: true,
      staged: false,
      recoveryCodesLeft: 10,
    });
  });

  it('sign-in without a code is refused with its own reason, not "wrong password"', async () => {
    const res = await login({ email: user.email, password: 'integration-pw-1' });
    expect(res.statusCode).toBe(401);
    // A client that cannot tell these apart has to guess what to prompt for.
    expect(res.json().code).toBe('AUTH_MFA_REQUIRED');
  });

  it('sign-in with a wrong code is refused, and the password is still not the reason', async () => {
    const res = await login({
      email: user.email,
      password: 'integration-pw-1',
      totpCode: '000000',
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('AUTH_MFA_INVALID');
  });

  it('a wrong password with a right code is still just a wrong password', async () => {
    const res = await login({ email: user.email, password: 'nope', totpCode: await freshCode() });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('AUTH_INVALID_CREDENTIALS');
  });

  it('sign-in with the code works, and the same code cannot be used twice', async () => {
    const code = await freshCode();
    const first = await login({ email: user.email, password: 'integration-pw-1', totpCode: code });
    expect(first.statusCode).toBe(200);

    // The replay refusal, from the outside: a shoulder-surfed code is dead.
    const second = await login({ email: user.email, password: 'integration-pw-1', totpCode: code });
    expect(second.statusCode).toBe(401);
    expect(second.json().code).toBe('AUTH_MFA_INVALID');
  });

  it('a recovery code signs in exactly once', async () => {
    const code = recoveryCodes[0];
    const first = await login({ email: user.email, password: 'integration-pw-1', totpCode: code });
    expect(first.statusCode).toBe(200);

    const second = await login({ email: user.email, password: 'integration-pw-1', totpCode: code });
    expect(second.statusCode).toBe(401);

    expect((await asUser('GET', '/api/v1/auth/mfa/totp')).json().recoveryCodesLeft).toBe(9);
  });

  it('recovery codes are accepted however they are typed off the paper', async () => {
    const code = recoveryCodes[1];
    const res = await login({
      email: user.email,
      password: 'integration-pw-1',
      totpCode: code.replace('-', '').toLowerCase(),
    });
    expect(res.statusCode).toBe(200);
  });

  it('an extension can refuse a sign-in that is otherwise correct', async () => {
    // The seam EE-124 needs: correct password, correct factor, and a policy
    // that still says no. Pushed directly onto the registry the overlay writes
    // to, so core's consultation is what is under test.
    app.ee.signInRequirements.push(async ({ factors }) =>
      factors.totpVerified ? { code: 'POLICY_NO', message: 'Not today' } : null,
    );
    try {
      const res = await login({
        email: user.email,
        password: 'integration-pw-1',
        totpCode: await freshCode(),
      });
      expect(res.statusCode).toBe(401);
      expect(res.json().code).toBe('POLICY_NO');
    } finally {
      app.ee.signInRequirements.pop();
    }
  });

  it('regenerating recovery codes needs a live code and retires the old ones', async () => {
    const refused = await asUser('POST', '/api/v1/auth/mfa/totp/recovery-codes', {
      code: '000000',
    });
    expect(refused.statusCode).toBe(401);

    const res = await asUser('POST', '/api/v1/auth/mfa/totp/recovery-codes', {
      code: await freshCode(),
    });
    expect(res.statusCode).toBe(200);
    const fresh = res.json().recoveryCodes;
    expect(fresh).toHaveLength(10);
    expect(fresh).not.toContain(recoveryCodes[2]);

    // An unspent code from the retired set is now worthless.
    const stale = await login({
      email: user.email,
      password: 'integration-pw-1',
      totpCode: recoveryCodes[2],
    });
    expect(stale.statusCode).toBe(401);
    recoveryCodes = fresh;
  });

  it('turning the factor off costs a live code', async () => {
    const refused = await asUser('DELETE', '/api/v1/auth/mfa/totp', { code: '000000' });
    expect(refused.statusCode).toBe(401);

    const res = await asUser('DELETE', '/api/v1/auth/mfa/totp', { code: await freshCode() });
    expect(res.statusCode).toBe(204);
    expect((await asUser('GET', '/api/v1/auth/mfa/totp')).json().enrolled).toBe(false);

    // And the codes went with it.
    const rows = await app.db('user_totp_recovery_codes').where({ user_id: user.id });
    expect(rows).toHaveLength(0);

    const back = await login({ email: user.email, password: 'integration-pw-1' });
    expect(back.statusCode).toBe(200);
  });
});

describe.runIf(enabled)('integration: changing your own password', () => {
  let app;
  let user;

  beforeAll(async () => {
    // The MFA routes carry the auth rate limit, and this suite makes far more
    // auth calls than a person would. Raising the ceiling here is not hiding
    // the limit — the limit is real, and it is what made these two tests 429
    // the first time they ran.
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-pw@example.com`, password: 'integration-pw-1' },
    });
    const body = res.json();
    user = {
      id: body.user.id,
      email: body.user.email,
      accessToken: body.tokens.accessToken,
      refreshToken: body.tokens.refreshToken,
    };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}-pw%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  const change = (payload) =>
    app.inject({
      method: 'POST',
      url: '/api/v1/auth/password',
      headers: { authorization: `Bearer ${user.accessToken}` },
      payload,
    });

  it('refuses without the current password — a stolen token is not enough', async () => {
    const res = await change({ currentPassword: 'wrong-one', newPassword: 'integration-pw-2' });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('AUTH_INVALID_CREDENTIALS');
  });

  it('changes it, stamps the date, and ends every other session', async () => {
    const res = await change({
      currentPassword: 'integration-pw-1',
      newPassword: 'integration-pw-2',
    });
    expect(res.statusCode).toBe(204);

    const row = await app.db('users').where({ id: user.id }).first('password_changed_at');
    expect(row.password_changed_at).toBeTruthy();

    // The old refresh token is dead: that is what makes the change an act
    // rather than a gesture.
    const refreshed = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: user.refreshToken },
    });
    expect(refreshed.statusCode).toBe(401);

    expect(
      (
        await app.inject({
          method: 'POST',
          url: '/api/v1/auth/login',
          payload: { email: user.email, password: 'integration-pw-2' },
        })
      ).statusCode,
    ).toBe(200);
  });

  it('an extension can refuse a new password after the old one is proven', async () => {
    app.ee.passwordRequirements.push(async ({ password }) =>
      password.length < 20 ? { code: 'POLICY_SHORT', message: 'Too short for this team' } : null,
    );
    try {
      const res = await change({
        currentPassword: 'integration-pw-2',
        newPassword: 'integration-pw-3',
      });
      expect(res.statusCode).toBe(400);
      expect(res.json().code).toBe('POLICY_SHORT');
    } finally {
      app.ee.passwordRequirements.pop();
    }
  });
});
