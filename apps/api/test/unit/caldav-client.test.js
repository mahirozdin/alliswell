import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import http from 'node:http';
import { createCaldavClient, hostPolicy, retryAfterMs } from '../../src/lib/caldav/client.js';
import { discover } from '../../src/lib/caldav/discovery.js';
import { startFakeCaldav } from '../helpers/fakecaldav.js';

const config = (over = {}) => ({
  allowPrivateHosts: true,
  icloudUrl: 'https://caldav.icloud.com',
  timeoutMs: 5000,
  ...over,
});

describe('caldav client + discovery against the fake (OPH-380)', () => {
  let fake;
  let client;

  beforeEach(async () => {
    fake = await startFakeCaldav();
    client = createCaldavClient({
      kind: 'generic',
      serverUrl: fake.url,
      username: fake.state.username,
      password: fake.state.password,
      config: config(),
    });
  });
  afterEach(async () => {
    await fake.close();
  });

  it('well-known → principal → partition home → VEVENT calendars only', async () => {
    const found = await discover(client, { startUrl: fake.url });
    expect(found.principalUrl).toBe(`${fake.url}/1234/principal/`);
    expect(found.homeUrl).toBe(`${fake.url}/1234/calendars/`);
    // The Reminders (VTODO-only) collection is filtered out.
    expect(found.calendars).toEqual([
      { url: '/1234/calendars/home/', name: 'Home', color: '#FF2968' },
    ]);
    expect(fake.state.requests[0].path).toBe('/.well-known/caldav');
  });

  it('a wrong password is CALDAV_AUTH_FAILED', async () => {
    const bad = createCaldavClient({
      kind: 'generic',
      serverUrl: fake.url,
      username: fake.state.username,
      password: 'wrong',
      config: config(),
    });
    await expect(discover(bad, { startUrl: fake.url })).rejects.toMatchObject({
      code: 'CALDAV_AUTH_FAILED',
      status: 401,
    });
  });

  it('a redirect off the host is refused — the credential never leaves', async () => {
    let leaked = null;
    const other = http.createServer((req, res) => {
      leaked = req.headers.authorization ?? 'no-auth-but-reached';
      res.end();
    });
    await new Promise((resolve) => other.listen(0, '127.0.0.1', resolve));
    // Same address, other NAME: the host policy is by host, not by IP.
    fake.state.redirectOffHost = `http://localhost:${other.address().port}/.well-known/caldav`;
    await expect(discover(client, { startUrl: fake.url })).rejects.toMatchObject({
      code: 'CALDAV_REDIRECT_OFF_HOST',
    });
    expect(leaked).toBeNull();
    await new Promise((resolve) => other.close(resolve));
  });

  it('without CALDAV_ALLOW_PRIVATE_HOSTS: http:// and loopback are refused', async () => {
    const strict = createCaldavClient({
      kind: 'generic',
      serverUrl: fake.url,
      username: 'a',
      password: 'b',
      config: config({ allowPrivateHosts: false }),
    });
    await expect(strict.get(`${fake.url}/x.ics`)).rejects.toMatchObject({
      code: 'CALDAV_BLOCKED_ADDRESS',
    });
    const https127 = createCaldavClient({
      kind: 'generic',
      serverUrl: 'https://127.0.0.1:9/',
      username: 'a',
      password: 'b',
      config: config({ allowPrivateHosts: false }),
    });
    await expect(https127.get('https://127.0.0.1:9/x.ics')).rejects.toMatchObject({
      code: 'CALDAV_BLOCKED_ADDRESS',
    });
    // A NAME that resolves to loopback is caught at connect time.
    const named = createCaldavClient({
      kind: 'generic',
      serverUrl: 'https://localhost:9/',
      username: 'a',
      password: 'b',
      config: config({ allowPrivateHosts: false }),
    });
    await expect(named.get('https://localhost:9/x.ics')).rejects.toMatchObject({
      code: 'CALDAV_BLOCKED_ADDRESS',
    });
    expect(fake.state.requests).toHaveLength(0);
  });

  it('iCloud host policy: caldav.icloud.com and pNN partitions only', () => {
    const allowed = hostPolicy({ kind: 'icloud', icloudUrl: 'https://caldav.icloud.com' });
    expect(allowed(new URL('https://caldav.icloud.com/'))).toBe(true);
    expect(allowed(new URL('https://p34-caldav.icloud.com:443/123/calendars/'))).toBe(true);
    expect(allowed(new URL('https://p34-caldav.icloud.com.evil.example/'))).toBe(false);
    expect(allowed(new URL('https://evil.example/'))).toBe(false);
    const generic = hostPolicy({ kind: 'generic', serverUrl: 'https://cloud.example.org/dav' });
    expect(generic(new URL('https://cloud.example.org/remote.php/dav'))).toBe(true);
    expect(generic(new URL('https://other.example.org/'))).toBe(false);
  });

  it('obeys one 429 with Retry-After and succeeds', async () => {
    fake.state.throttleNext = 1;
    const found = await discover(client, { startUrl: fake.url });
    expect(found.calendars).toHaveLength(1);
    expect(retryAfterMs('2', 0)).toBe(2000);
    expect(retryAfterMs('999', 0)).toBe(60000);
  });

  it('a PUT without ETag falls back to PROPFIND getetag', async () => {
    fake.state.omitEtagOnPut = true;
    const url = `${fake.url}/1234/calendars/home/a.ics`;
    const etag = await client.put(url, 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n', {
      ifNoneMatch: '*',
    });
    expect(etag).toBe(fake.state.resource('/1234/calendars/home/a.ics').etag);
    // If-None-Match: * on an existing resource → 412.
    await expect(client.put(url, 'x', { ifNoneMatch: '*' })).rejects.toMatchObject({ status: 412 });
    // DELETE with a stale etag → 412; with the right one → gone; again → tolerated.
    await expect(client.delete(url, '"nope"')).rejects.toMatchObject({ status: 412 });
    await client.delete(url, etag);
    await client.delete(url, etag);
    expect(await client.get(url)).toBeNull();
  });

  it('sync-collection: pages on 507, reports changes and deletions, rejects bad tokens', async () => {
    const cal = `${fake.url}/1234/calendars/home/`;
    fake.state.userPut('/1234/calendars/home/a.ics', 'A');
    fake.state.userPut('/1234/calendars/home/b.ics', 'B');
    const first = await client.syncCollection(cal, null);
    expect(first.changed.map((c) => c.href).sort()).toEqual([
      '/1234/calendars/home/a.ics',
      '/1234/calendars/home/b.ics',
    ]);
    fake.state.userDelete('/1234/calendars/home/a.ics');
    fake.state.userPut('/1234/calendars/home/c.ics', 'C');
    fake.state.userPut('/1234/calendars/home/d.ics', 'D');
    fake.state.pageSize = 1;
    const next = await client.syncCollection(cal, first.token);
    expect(next.removed).toEqual(['/1234/calendars/home/a.ics']);
    expect(next.changed.map((c) => c.href).sort()).toEqual([
      '/1234/calendars/home/c.ics',
      '/1234/calendars/home/d.ics',
    ]);
    const multi = await client.multiget(cal, [
      '/1234/calendars/home/c.ics',
      '/1234/calendars/home/zz.ics',
    ]);
    expect(multi).toEqual([
      {
        href: '/1234/calendars/home/c.ics',
        etag: fake.state.resource('/1234/calendars/home/c.ics').etag,
        ics: 'C',
      },
    ]);
    await expect(client.syncCollection(cal, 'http://fake/sync/999')).rejects.toMatchObject({
      status: 403,
      davError: 'valid-sync-token',
    });
  });
});
