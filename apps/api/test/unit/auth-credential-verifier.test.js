import { describe, it, expect } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

/**
 * OPH-286 — the credential-verifier seam.
 *
 * Two halves, and the first one is the important one: with nothing registered
 * this endpoint must behave exactly as it did before the seam existed. The
 * other three auth hooks could be added without touching the happy path;
 * this one moves the password check itself, so "unchanged" has to be asserted
 * rather than assumed.
 */

const testConfig = loadConfig({ NODE_ENV: 'test' });
const PASSWORD = 'correct-horse-battery';

async function appWithUser() {
  const { db, tables } = fakeDb();
  const app = await buildApp({ config: testConfig, db, redis: fakeRedis() });
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email: 'mahir@example.com', password: PASSWORD, displayName: 'Mahir' },
  });
  expect(res.statusCode).toBe(201);
  return { app, tables, registered: res.json() };
}

const login = (app, payload) => app.inject({ method: 'POST', url: '/api/v1/auth/login', payload });

describe('credential verifiers — with none registered (OPH-286)', () => {
  it('registers no verifiers by default', async () => {
    const { app } = await appWithUser();
    expect(app.ee.credentialVerifiers).toEqual([]);
    await app.close();
  });

  it('the right password still signs in', async () => {
    const { app, registered } = await appWithUser();
    const res = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    expect(res.statusCode).toBe(200);
    expect(res.json().user).toEqual(registered.user);
    await app.close();
  });

  it('the wrong password, an unknown address and a passwordless account all refuse alike', async () => {
    const { app, tables } = await appWithUser();

    const wrong = await login(app, { email: 'mahir@example.com', password: 'not-it-at-all' });
    const unknown = await login(app, { email: 'nobody@example.com', password: PASSWORD });
    expect(wrong.statusCode).toBe(401);
    expect(unknown.statusCode).toBe(401);
    // Same code and same message: the endpoint must not become an oracle for
    // which of the two went wrong.
    expect(wrong.json().code).toBe(unknown.json().code);
    expect(wrong.json().message).toBe(unknown.json().message);

    // A null password_hash is the shape a directory-sourced account will have,
    // and today it refuses — which is exactly why the seam has to exist.
    tables.users[0].password_hash = null;
    const passwordless = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    expect(passwordless.statusCode).toBe(401);
    expect(passwordless.json().code).toBe(wrong.json().code);
    await app.close();
  });

  it('still tells the failure observers, with the same arguments as before', async () => {
    const { app } = await appWithUser();
    const seen = [];
    app.ee.signInFailureObservers.push(async (ctx) => {
      seen.push({ email: ctx.email, user: ctx.user?.email ?? null });
    });
    await login(app, { email: 'mahir@example.com', password: 'wrong' });
    await login(app, { email: 'ghost@example.com', password: 'wrong' });
    expect(seen).toEqual([
      { email: 'mahir@example.com', user: 'mahir@example.com' },
      { email: 'ghost@example.com', user: null },
    ]);
    await app.close();
  });
});

describe('credential verifiers — the three answers (OPH-286)', () => {
  it('a verifier that declines leaves the local password in charge', async () => {
    const { app } = await appWithUser();
    const asked = [];
    app.ee.credentialVerifiers.push(async ({ email }) => {
      asked.push(email);
      return null;
    });

    const ok = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    const no = await login(app, { email: 'mahir@example.com', password: 'wrong' });
    expect(ok.statusCode).toBe(200);
    expect(no.statusCode).toBe(401);
    // Consulted for both, which is what keeps its invocation from being an
    // account-existence oracle.
    expect(asked).toEqual(['mahir@example.com', 'mahir@example.com']);
    await app.close();
  });

  it('is asked about addresses with no account here', async () => {
    const { app } = await appWithUser();
    const asked = [];
    app.ee.credentialVerifiers.push(async ({ email, user }) => {
      asked.push({ email, user });
      return null;
    });
    await login(app, { email: 'ghost@example.com', password: PASSWORD });
    expect(asked).toEqual([{ email: 'ghost@example.com', user: null }]);
    await app.close();
  });

  it('a claim signs the named account in WITHOUT its local password', async () => {
    const { app, tables, registered } = await appWithUser();
    // The directory-sourced shape: no local password at all.
    tables.users[0].password_hash = null;
    app.ee.credentialVerifiers.push(async ({ password }) =>
      password === 'directory-pw' ? { ok: true, userId: registered.user.id } : null,
    );

    const res = await login(app, { email: 'mahir@example.com', password: 'directory-pw' });
    expect(res.statusCode).toBe(200);
    expect(res.json().user).toEqual(registered.user);
    expect(app.jwt.verify(res.json().tokens.accessToken).sub).toBe(registered.user.id);
    await app.close();
  });

  it('a refusal is refused, and the failure observers hear about it', async () => {
    const { app } = await appWithUser();
    const seen = [];
    app.ee.signInFailureObservers.push(async ({ email }) => seen.push(email));
    app.ee.credentialVerifiers.push(async () => ({ ok: false }));

    // Even the RIGHT local password loses: the address belongs to the verifier.
    const res = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    expect(res.statusCode).toBe(401);
    expect(seen).toEqual(['mahir@example.com']);
    await app.close();
  });

  it('cannot conjure an account: a claim naming nobody is a refusal', async () => {
    const { app } = await appWithUser();
    app.ee.credentialVerifiers.push(async () => ({
      ok: true,
      userId: 'nosuchuser0000000000000000',
    }));
    const res = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('cannot sign in a deleted account either', async () => {
    const { app, tables, registered } = await appWithUser();
    tables.users[0].deleted_at = new Date();
    app.ee.credentialVerifiers.push(async () => ({ ok: true, userId: registered.user.id }));
    const res = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('the first verifier to claim the address settles it', async () => {
    const { app, registered } = await appWithUser();
    const calls = [];
    app.ee.credentialVerifiers.push(async () => {
      calls.push('first');
      return { ok: true, userId: registered.user.id };
    });
    app.ee.credentialVerifiers.push(async () => {
      calls.push('second');
      return { ok: false };
    });
    const res = await login(app, { email: 'mahir@example.com', password: 'anything' });
    expect(res.statusCode).toBe(200);
    expect(calls).toEqual(['first']);
    await app.close();
  });

  it('a claimed sign-in still passes through the sign-in requirements', async () => {
    const { app, registered } = await appWithUser();
    app.ee.credentialVerifiers.push(async () => ({ ok: true, userId: registered.user.id }));
    app.ee.signInRequirements.push(async () => ({ code: 'POLICY_NO', message: 'Not today' }));
    const res = await login(app, { email: 'mahir@example.com', password: 'anything' });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('POLICY_NO');
    await app.close();
  });

  it('a throwing verifier refuses the sign-in rather than falling back to the password', async () => {
    const { app } = await appWithUser();
    app.ee.credentialVerifiers.push(async () => {
      throw new Error('directory unreachable');
    });
    const res = await login(app, { email: 'mahir@example.com', password: PASSWORD });
    // Not a 401: an unreachable credential source is a server-side failure,
    // and an operator should be able to tell it from a wrong password.
    expect(res.statusCode).toBeGreaterThanOrEqual(500);
    await app.close();
  });
});
