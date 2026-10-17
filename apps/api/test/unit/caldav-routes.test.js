import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';
import { startFakeCaldav, fakeCaldavEnv } from '../helpers/fakecaldav.js';
import { decryptSecret } from '../../src/lib/crypto.js';
import {
  serializeCaldavAccount,
  normalizeServerUrl,
} from '../../src/routes/integrations-caldav.js';

const KEY = 'e'.repeat(64);

describe('CalDAV integration routes (OPH-380, CALDAV.md §3)', () => {
  let fake;
  let app;
  let tables;
  let owner;

  const boot = async (env = {}) => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      CALENDAR_TOKEN_KEY: KEY,
      ...fakeCaldavEnv(fake.url),
      ...env,
    });
    ({ app, tables } = await buildTestApp({ config }));
    owner = await registerUser(app, { email: 'owner@example.com' });
  };

  beforeEach(async () => {
    fake = await startFakeCaldav();
  });
  afterEach(async () => {
    await app?.close();
    app = null;
    await fake.close();
  });

  const base = () => `/api/v1/workspaces/${owner.workspace.id}/integrations/caldav`;
  const connect = (payload, headers = owner.headers) =>
    app.inject({ method: 'POST', url: base(), headers, payload });
  const icloud = () => ({
    server: 'icloud',
    username: fake.state.username,
    password: fake.state.password,
  });

  it('connect verifies first, stores the password encrypted, never returns it', async () => {
    await boot();
    const bad = await connect({ ...icloud(), password: 'my-apple-id-password' });
    expect(bad.statusCode).toBe(422);
    expect(bad.json().code).toBe('CALDAV_AUTH_FAILED');
    // Verify before store: a failed discovery writes nothing.
    expect(tables.calendar_accounts).toHaveLength(0);

    const res = await connect(icloud());
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.account).toMatchObject({
      provider: 'caldav',
      server: 'icloud',
      username: fake.state.username,
      status: 'active',
      // The only VEVENT calendar is chosen for the user.
      calendarUrl: '/1234/calendars/home/',
      calendarName: 'Home',
    });
    expect(body.calendars).toEqual([
      { url: '/1234/calendars/home/', name: 'Home', color: '#FF2968' },
    ]);

    const row = tables.calendar_accounts[0];
    expect(row.provider).toBe('apple_caldav');
    expect(row.caldav_kind).toBe('icloud');
    expect(row.encrypted_app_password).not.toContain(fake.state.password);
    expect(decryptSecret(row.encrypted_app_password, KEY)).toBe(fake.state.password);
    expect(row.calendar_home_url).toBe(`${fake.url}/1234/calendars/`);

    // Nothing that leaves the server carries the password or its ciphertext.
    const status = await app.inject({ method: 'GET', url: base(), headers: owner.headers });
    for (const text of [res.body, status.body]) {
      expect(text).not.toContain(fake.state.password);
      expect(text).not.toContain(row.encrypted_app_password);
      expect(text).not.toContain('encrypted');
    }
    expect(status.json()).toMatchObject({ enabled: true, items: [{ id: row.id }] });
    expect(Object.keys(serializeCaldavAccount(row))).not.toContain('encryptedAppPassword');
  });

  it('several calendars → none chosen until the user picks one; PATCH accepts only listed ones', async () => {
    fake =
      (await fake.close(),
      await startFakeCaldav({
        calendars: [
          { path: '/1234/calendars/home/', name: 'Home', components: ['VEVENT'] },
          { path: '/1234/calendars/work/', name: 'Work', components: ['VEVENT', 'VTODO'] },
        ],
      }));
    await boot();
    const res = await connect(icloud());
    expect(res.statusCode).toBe(201);
    expect(res.json().account.calendarUrl).toBeNull();
    expect(res.json().calendars).toHaveLength(2);
    const id = res.json().account.id;

    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/integrations/caldav/accounts/${id}/calendars`,
      headers: owner.headers,
    });
    expect(list.json().items.map((c) => c.name)).toEqual(['Home', 'Work']);

    const unknown = await app.inject({
      method: 'PATCH',
      url: `/api/v1/integrations/caldav/accounts/${id}`,
      headers: owner.headers,
      payload: { calendarUrl: '/somewhere/else/' },
    });
    expect(unknown.statusCode).toBe(422);
    expect(unknown.json().code).toBe('CALDAV_UNKNOWN_CALENDAR');

    const chosen = await app.inject({
      method: 'PATCH',
      url: `/api/v1/integrations/caldav/accounts/${id}`,
      headers: owner.headers,
      payload: { calendarUrl: '/1234/calendars/work/' },
    });
    expect(chosen.statusCode).toBe(200);
    expect(chosen.json()).toMatchObject({
      calendarUrl: '/1234/calendars/work/',
      calendarName: 'Work',
    });
  });

  it('same identity reconnects; a different one is 409 until the first is disconnected', async () => {
    await boot();
    const first = await connect(icloud());
    const again = await connect(icloud());
    expect(again.statusCode).toBe(201);
    expect(again.json().account.id).toBe(first.json().account.id);
    expect(tables.calendar_accounts).toHaveLength(1);

    // Another host, same server: a different identity.
    const otherHost = fake.url.replace('127.0.0.1', 'localhost');
    const generic = await connect({
      server: 'generic',
      url: otherHost,
      username: fake.state.username,
      password: fake.state.password,
    });
    expect(generic.statusCode).toBe(409);
    expect(generic.json().code).toBe('CALDAV_ALREADY_CONNECTED');

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/integrations/caldav/accounts/${first.json().account.id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    const row = tables.calendar_accounts[0];
    expect(row.encrypted_app_password).toBeNull();
    expect(row.sync_token).toBeNull();
    expect(row.status).toBe('disconnected');
    expect(row.deleted_at).not.toBeNull();

    const now = await connect({
      server: 'generic',
      url: otherHost,
      username: fake.state.username,
      password: fake.state.password,
    });
    expect(now.statusCode).toBe(201);
    expect(now.json().account).toMatchObject({
      server: 'generic',
      serverUrl: `${otherHost}/`,
      serverHost: new URL(otherHost).host,
    });
  });

  it('the same account live in another workspace is not silently moved here', async () => {
    await boot();
    tables.calendar_accounts.push({
      id: 'X'.padEnd(26, '0'),
      user_id: owner.user.id,
      workspace_id: 'W'.padEnd(26, '9'),
      provider: 'apple_caldav',
      provider_account_id: `${new URL(fake.url).host}/${fake.state.username}`,
      caldav_kind: 'icloud',
      status: 'active',
      deleted_at: null,
    });
    const res = await connect(icloud());
    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('CALDAV_ALREADY_CONNECTED');
    expect(tables.calendar_accounts[0].workspace_id).toBe('W'.padEnd(26, '9'));
    // Nothing was even tried against the server.
    expect(fake.state.requests).toHaveLength(0);
  });

  it('an API key can read status but never connect (session only)', async () => {
    await boot();
    const key = await app
      .inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/api-keys`,
        headers: owner.headers,
        payload: { name: 'script' },
      })
      .then((r) => r.json());
    const keyHeaders = { authorization: `Bearer ${key.key}` };
    const refused = await connect(icloud(), keyHeaders);
    expect(refused.statusCode).toBe(403);
    expect(refused.json().code).toBe('AUTH_APIKEY_FORBIDDEN');
    const status = await app.inject({ method: 'GET', url: base(), headers: keyHeaders });
    expect(status.statusCode).toBe(200);
  });

  it('switched off: connect is 503, status and disconnect still work', async () => {
    await boot();
    const res = await connect(icloud());
    const id = res.json().account.id;
    await app.close();
    const { app: off, tables: offTables } = await buildTestApp({
      config: loadConfig({
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '1000',
        CALENDAR_TOKEN_KEY: KEY,
      }),
    });
    app = off;
    tables = offTables;
    owner = await registerUser(app, { email: 'owner@example.com' });
    tables.calendar_accounts.push({
      id,
      user_id: owner.user.id,
      workspace_id: owner.workspace.id,
      provider: 'apple_caldav',
      provider_account_id: 'caldav.icloud.com/alice',
      caldav_kind: 'icloud',
      encrypted_app_password: 'v1:x:y:z',
      status: 'active',
      deleted_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    });
    const refused = await connect(icloud());
    expect(refused.statusCode).toBe(503);
    expect(refused.json().code).toBe('CALDAV_NOT_ENABLED');
    const status = await app.inject({ method: 'GET', url: base(), headers: owner.headers });
    expect(status.json()).toMatchObject({ enabled: false, items: [{ id }] });
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/integrations/caldav/accounts/${id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    expect(tables.calendar_accounts[0].encrypted_app_password).toBeNull();
  });

  it('another member can neither see nor manage my account', async () => {
    await boot();
    const res = await connect(icloud());
    const id = res.json().account.id;
    const other = await registerUser(app, { email: 'other@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: other.user });
    const status = await app.inject({ method: 'GET', url: base(), headers: other.headers });
    expect(status.json().items).toEqual([]);
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/integrations/caldav/accounts/${id}`,
      headers: other.headers,
    });
    expect(del.statusCode).toBe(403);
  });

  it('generic URLs: https only by default, no userinfo', async () => {
    expect(normalizeServerUrl('cloud.example.org', false)).toBe('https://cloud.example.org/');
    expect(normalizeServerUrl('http://cloud.example.org', false)).toBeNull();
    expect(normalizeServerUrl('http://192.168.1.5:8080/dav', true)).toBe(
      'http://192.168.1.5:8080/dav',
    );
    expect(normalizeServerUrl('https://u:p@cloud.example.org', false)).toBeNull();
    expect(normalizeServerUrl('https://cloud.example.org/#x', false)).toBeNull();
    expect(normalizeServerUrl('ftp://cloud.example.org', true)).toBeNull();

    await boot({ CALDAV_ALLOW_PRIVATE_HOSTS: 'false' });
    const res = await connect({
      server: 'generic',
      url: fake.url,
      username: 'a',
      password: 'b',
    });
    expect(res.statusCode).toBe(422);
    expect(res.json().code).toBe('CALDAV_BAD_URL');
  });
});
