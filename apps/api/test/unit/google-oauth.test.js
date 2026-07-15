import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeGoogle, fakeGoogleEnv } from '../helpers/fakegoogle.js';
import { encryptSecret, decryptSecret } from '../../src/lib/crypto.js';

const KEY = 'a'.repeat(64);

describe('lib/crypto (OPH-070)', () => {
  it('round-trips, salts every value and rejects tampering/wrong keys', () => {
    const secret = 'ya29.google-access-token';
    const encrypted = encryptSecret(secret, KEY);
    expect(encrypted).toMatch(/^v1:/);
    expect(encrypted).not.toContain(secret);
    expect(decryptSecret(encrypted, KEY)).toBe(secret);
    // Fresh IV per call → different ciphertexts for the same plaintext.
    expect(encryptSecret(secret, KEY)).not.toBe(encrypted);
    // GCM authenticates: bit-flips and wrong keys throw, never garbage.
    const tampered = encrypted.slice(0, -2) + (encrypted.endsWith('A') ? 'BB' : 'AA');
    expect(() => decryptSecret(tampered, KEY)).toThrow();
    expect(() => decryptSecret(encrypted, 'b'.repeat(64))).toThrow();
    expect(() => decryptSecret('garbage', KEY)).toThrow();
  });
});

describe('Google OAuth connect (OPH-070) + calendars (OPH-071)', () => {
  let google;
  let app;
  let tables;
  let owner;

  beforeEach(async () => {
    google = await startFakeGoogle();
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      CALENDAR_TOKEN_KEY: KEY,
      ...fakeGoogleEnv(google.url),
    });
    ({ app, tables } = await buildTestApp({ config }));
    owner = await registerUser(app, { email: 'owner@example.com' });
  });

  afterEach(async () => {
    await app.close();
    await google.app.close();
  });

  const connect = () =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/integrations/google/connect`,
      headers: owner.headers,
    });

  const callback = (qs) =>
    app.inject({ method: 'GET', url: `/api/v1/integrations/google/callback?${qs}` });

  it('hands out a consent URL carrying a signed state', async () => {
    const res = await connect();
    expect(res.statusCode).toBe(200);
    const authUrl = new URL(res.json().authUrl);
    expect(authUrl.origin).toBe(google.url);
    expect(authUrl.searchParams.get('client_id')).toBe('fake-client-id');
    expect(authUrl.searchParams.get('access_type')).toBe('offline');
    expect(authUrl.searchParams.get('scope')).toContain('auth/calendar');
    const state = app.jwt.verify(authUrl.searchParams.get('state'));
    expect(state).toMatchObject({ purpose: 'google_oauth', wsId: owner.workspace.id });
  });

  it('exchanges the callback code and stores ONLY ciphertext at rest', async () => {
    const authUrl = new URL((await connect()).json().authUrl);
    const state = authUrl.searchParams.get('state');

    const res = await callback(`code=good-code&state=${encodeURIComponent(state)}`);
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('bağlandı');

    const account = tables.calendar_accounts.at(0);
    expect(account).toMatchObject({
      provider: 'google',
      provider_account_id: 'takvim@example.com',
      status: 'active',
      workspace_id: owner.workspace.id,
    });
    expect(account.encrypted_access_token).toMatch(/^v1:/);
    expect(account.encrypted_refresh_token).toMatch(/^v1:/);
    expect(account.encrypted_access_token).not.toContain('at-');
    expect(decryptSecret(account.encrypted_refresh_token, KEY)).toBe('rt-1');

    // Reconnecting the same Google identity upserts, never duplicates.
    const again = await callback(
      `code=good-code&state=${encodeURIComponent(
        new URL((await connect()).json().authUrl).searchParams.get('state'),
      )}`,
    );
    expect(again.statusCode).toBe(200);
    expect(tables.calendar_accounts).toHaveLength(1);

    // The status endpoint never leaks tokens.
    const status = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/integrations/google`,
      headers: owner.headers,
    });
    expect(status.json().configured).toBe(true);
    const item = status.json().items[0];
    expect(item.providerAccountId).toBe('takvim@example.com');
    expect(JSON.stringify(item)).not.toContain('v1:');
  });

  it('rejects forged/expired/missing state and failed exchanges', async () => {
    expect((await callback('code=x&state=not-a-jwt')).statusCode).toBe(400);
    expect((await callback('error=access_denied')).statusCode).toBe(400);

    // A valid session JWT is NOT a valid state (wrong purpose).
    const accessToken = owner.headers.authorization.replace('Bearer ', '');
    const wrongPurpose = await callback(`code=x&state=${encodeURIComponent(accessToken)}`);
    expect(wrongPurpose.statusCode).toBe(400);

    const state = new URL((await connect()).json().authUrl).searchParams.get('state');
    const badCode = await callback(`code=bad-code&state=${encodeURIComponent(state)}`);
    expect(badCode.statusCode).toBe(400);
    expect(tables.calendar_accounts).toHaveLength(0);
  });

  it('answers GOOGLE_NOT_CONFIGURED without credentials', async () => {
    const bare = await buildTestApp();
    const user = await registerUser(bare.app, { email: 'plain@example.com' });
    const res = await bare.app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${user.workspace.id}/integrations/google/connect`,
      headers: user.headers,
    });
    expect(res.statusCode).toBe(503);
    expect(res.json().code).toBe('GOOGLE_NOT_CONFIGURED');
    const status = await bare.app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${user.workspace.id}/integrations/google`,
      headers: user.headers,
    });
    expect(status.json().configured).toBe(false);
    await bare.app.close();
  });

  it('lists calendars, refreshing an expired access token in place (OPH-071)', async () => {
    const state = new URL((await connect()).json().authUrl).searchParams.get('state');
    await callback(`code=good-code&state=${encodeURIComponent(state)}`);
    const account = tables.calendar_accounts[0];
    // Force the refresh path.
    account.token_expires_at = new Date(Date.now() - 1000);

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/integrations/google/accounts/${account.id}/calendars`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().items).toEqual([
      { id: 'primary', summary: 'Ana Takvim', primary: true },
      { id: 'is-takvimi', summary: 'İş', primary: false },
    ]);
    expect(google.state.refreshCalls).toBe(1);
    // The fresh token was re-encrypted at rest.
    expect(new Date(account.token_expires_at).getTime()).toBeGreaterThan(Date.now());

    // A rejected refresh flips the account to error and reports reauth.
    google.state.failRefresh = true;
    account.token_expires_at = new Date(Date.now() - 1000);
    const dead = await app.inject({
      method: 'GET',
      url: `/api/v1/integrations/google/accounts/${account.id}/calendars`,
      headers: owner.headers,
    });
    expect(dead.statusCode).toBe(502);
    expect(dead.json().code).toBe('CALENDAR_ACCOUNT_REAUTH_REQUIRED');
    expect(account.status).toBe('error');
  });

  it('only the connecting user manages the account; disconnect wipes secrets', async () => {
    const state = new URL((await connect()).json().authUrl).searchParams.get('state');
    await callback(`code=good-code&state=${encodeURIComponent(state)}`);
    const account = tables.calendar_accounts[0];

    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const foreign = await app.inject({
      method: 'GET',
      url: `/api/v1/integrations/google/accounts/${account.id}/calendars`,
      headers: outsider.headers,
    });
    expect(foreign.statusCode).toBe(403); // not even a workspace member

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/integrations/google/accounts/${account.id}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(204);
    expect(google.state.revoked).toContain('rt-1');
    expect(account.status).toBe('disconnected');
    expect(account.encrypted_access_token).toBeNull();
    expect(account.encrypted_refresh_token).toBeNull();
    expect(account.deleted_at).not.toBeNull();
  });
});
