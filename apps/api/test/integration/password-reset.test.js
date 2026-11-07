import { describe, it, expect, beforeAll, afterAll } from 'vitest';

import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { run as resetLinkCli } from '../../src/cli/password-reset-link.js';

// Needs real MySQL + Redis with migrations applied (see integration/ready.test.js).
const enabled = process.env.INTEGRATION === '1';
const emailPrefix = `oph406-${Date.now()}`;
const APP_URL = 'https://app.alliswell.test';

/** Records what would have been sent; `send` is all the routes need. */
function fakeMailer() {
  return {
    sent: [],
    async send(mail) {
      this.sent.push(mail);
    },
  };
}

const tick = () => new Promise((resolve) => setImmediate(resolve));
const tokenIn = (text) => /reset-password\?token=([A-Za-z0-9_-]+)/.exec(text)?.[1] ?? null;

async function cleanup(app) {
  const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
  const ids = users.map((u) => u.id);
  if (ids.length > 0) {
    await app.db('workspaces').whereIn('owner_id', ids).delete();
    await app.db('users').whereIn('id', ids).delete();
  }
}

/// OPH-406 — "I forgot my password" end to end: the link is single use, it
/// expires, a newer one retires the older, the forgot form never says whether
/// an account exists, and both doors sit behind the credential rate limit.
describe.runIf(enabled)('integration: password reset', () => {
  let app;
  let mailer;

  const register = (email, password = 'old-password-1') =>
    app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email, password } });
  const login = (email, password) =>
    app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password } });
  const forgot = (payload, target = app) =>
    target.inject({ method: 'POST', url: '/api/v1/auth/password/forgot', payload });
  const reset = (payload, target = app) =>
    target.inject({ method: 'POST', url: '/api/v1/auth/password/reset', payload });

  /** Asks for a link and returns the token from the mail it produced. */
  async function mailedToken(email) {
    const before = mailer.sent.length;
    const res = await forgot({ email });
    expect(res.statusCode).toBe(202);
    await tick();
    expect(mailer.sent).toHaveLength(before + 1);
    return tokenIn(mailer.sent.at(-1).text);
  }

  beforeAll(async () => {
    mailer = fakeMailer();
    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        APP_PUBLIC_URL: APP_URL,
        RATE_LIMIT_AUTH_MAX: '1000',
      }),
      mailer,
    });
  });

  afterAll(async () => {
    if (!app) return;
    await cleanup(app);
    await app.close();
  });

  it('answers the same for a known and an unknown address, and mails only the known one', async () => {
    const email = `${emailPrefix}-same@example.com`;
    expect((await register(email)).statusCode).toBe(201);

    const known = await forgot({ email: email.toUpperCase(), locale: 'tr' });
    const unknown = await forgot({ email: `${emailPrefix}-nobody@example.com` });
    await tick();

    expect(known.statusCode).toBe(202);
    expect(unknown.statusCode).toBe(202);
    expect(known.json()).toEqual({ delivery: 'email' });
    expect(unknown.json()).toEqual(known.json());

    const mails = mailer.sent.filter((m) => m.to.startsWith(`${emailPrefix}-`));
    expect(mails.map((m) => m.to)).toEqual([email]);
    expect(mails[0].subject).toBe('AllisWell parolanı sıfırla');
    const token = tokenIn(mails[0].text);
    expect(mails[0].text).toContain(`${APP_URL}/#/reset-password?token=${token}`);

    // Stored as a keyed digest only: the raw token is nowhere in the row.
    const user = await app.db('users').where({ email }).first('id');
    const rows = await app.db('password_resets').where({ user_id: user.id });
    expect(rows).toHaveLength(1);
    expect(rows[0].token_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(rows[0])).not.toContain(token);
    expect(rows[0].source).toBe('email');
  });

  it('sets the password once, ends every session, and refuses the same link again', async () => {
    const email = `${emailPrefix}-once@example.com`;
    const registered = (await register(email)).json();
    const token = await mailedToken(email);

    const first = await reset({ token, password: 'new-password-1' });
    expect(first.statusCode).toBe(204);

    expect((await login(email, 'new-password-1')).statusCode).toBe(200);
    const old = await login(email, 'old-password-1');
    expect(old.statusCode).toBe(401);

    // The session from before the reset is over (ADR-0006).
    const refresh = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: registered.tokens.refreshToken },
    });
    expect(refresh.statusCode).toBe(401);

    const again = await reset({ token, password: 'third-password-1' });
    expect(again.statusCode).toBe(400);
    expect(again.json().code).toBe('AUTH_RESET_INVALID');
    expect((await login(email, 'new-password-1')).statusCode).toBe(200);
  });

  it('refuses an expired link, an unknown one and a short password', async () => {
    const email = `${emailPrefix}-expired@example.com`;
    await register(email);
    const token = await mailedToken(email);

    const short = await reset({ token, password: 'short' });
    expect(short.statusCode).toBe(400);

    const user = await app.db('users').where({ email }).first('id');
    await app
      .db('password_resets')
      .where({ user_id: user.id })
      .update({ expires_at: new Date(Date.now() - 1000) });
    const expired = await reset({ token, password: 'new-password-1' });
    expect(expired.statusCode).toBe(400);
    expect(expired.json().code).toBe('AUTH_RESET_INVALID');

    const unknown = await reset({ token: 'x'.repeat(43), password: 'new-password-1' });
    expect(unknown.statusCode).toBe(400);
    expect(unknown.json().code).toBe('AUTH_RESET_INVALID');
    expect((await login(email, 'old-password-1')).statusCode).toBe(200);
  });

  it('retires the older link when a newer one is sent', async () => {
    const email = `${emailPrefix}-newer@example.com`;
    await register(email);
    const older = await mailedToken(email);
    const newer = await mailedToken(email);

    expect((await reset({ token: older, password: 'new-password-1' })).statusCode).toBe(400);
    expect((await reset({ token: newer, password: 'new-password-1' })).statusCode).toBe(204);
  });

  it('sends at most three links an hour to one account, and still answers the same', async () => {
    const email = `${emailPrefix}-hourly@example.com`;
    await register(email);
    for (let i = 0; i < 3; i += 1) await mailedToken(email);

    const before = mailer.sent.length;
    const fourth = await forgot({ email });
    await tick();
    expect(fourth.statusCode).toBe(202);
    expect(fourth.json()).toEqual({ delivery: 'email' });
    expect(mailer.sent).toHaveLength(before);
  });

  it('puts both doors behind the credential rate limit', async () => {
    const limited = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        APP_PUBLIC_URL: APP_URL,
        RATE_LIMIT_AUTH_MAX: '3',
      }),
      mailer: fakeMailer(),
    });
    try {
      const email = `${emailPrefix}-nobody-limited@example.com`;
      const asks = [];
      for (let i = 0; i < 4; i += 1) asks.push((await forgot({ email }, limited)).statusCode);
      expect(asks).toEqual([202, 202, 202, 429]);

      const guesses = [];
      for (let i = 0; i < 4; i += 1) {
        const res = await reset(
          { token: `guess-${i}`.padEnd(43, 'x'), password: 'p'.repeat(8) },
          limited,
        );
        guesses.push(res.statusCode);
      }
      expect(guesses).toEqual([400, 400, 400, 429]);
      const last = await reset({ token: 'y'.repeat(43), password: 'p'.repeat(8) }, limited);
      expect(last.json().code).toBe('RATE_LIMITED');
    } finally {
      await limited.close();
    }
  });

  it('without outgoing mail answers "admin" and issues nothing', async () => {
    const noMail = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', APP_PUBLIC_URL: APP_URL }),
      mailer: null,
    });
    try {
      const email = `${emailPrefix}-nomail@example.com`;
      expect((await register(email)).statusCode).toBe(201);
      const res = await forgot({ email }, noMail);
      expect(res.statusCode).toBe(202);
      expect(res.json()).toEqual({ delivery: 'admin' });
      const user = await app.db('users').where({ email }).first('id');
      expect(await app.db('password_resets').where({ user_id: user.id })).toHaveLength(0);
    } finally {
      await noMail.close();
    }
  });

  it("the operator's command prints a working 24-hour link", async () => {
    const email = `${emailPrefix}-admin@example.com`;
    await register(email);
    const out = [];
    const err = [];
    const code = await resetLinkCli({
      argv: [email.toUpperCase()],
      config: app.config,
      db: app.db,
      out: (line) => out.push(line),
      err: (line) => err.push(line),
    });
    expect(code).toBe(0);
    expect(out).toHaveLength(1);
    expect(out[0].startsWith(`${APP_URL}/#/reset-password?token=`)).toBe(true);

    const user = await app.db('users').where({ email }).first('id');
    const row = await app.db('password_resets').where({ user_id: user.id }).first();
    expect(row.source).toBe('admin');
    const hours = (new Date(row.expires_at).getTime() - Date.now()) / 3600000;
    expect(hours).toBeGreaterThan(23.9);
    expect(hours).toBeLessThanOrEqual(24);

    const res = await reset({ token: tokenIn(out[0]), password: 'admin-given-1' });
    expect(res.statusCode).toBe(204);
    expect((await login(email, 'admin-given-1')).statusCode).toBe(200);

    // The operator learns an address has no account; the public form never says.
    const missing = await resetLinkCli({
      argv: [`${emailPrefix}-ghost@example.com`],
      config: app.config,
      db: app.db,
      out: () => {},
      err: () => {},
    });
    expect(missing).toBe(1);
    expect(await resetLinkCli({ argv: [], config: app.config, db: app.db, err: () => {} })).toBe(2);
  });
});
