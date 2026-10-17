import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { decryptSecret } from '../../src/lib/crypto.js';
import { externalIdFor } from '../../src/lib/caldav/ical.js';

// A REAL CalDAV server (Radicale 3.8.3 in docker — `docker compose up -d
// radicale`, CI starts it with `docker run`) behind the real connector, over
// BullMQ and MySQL (OPH-380, ADR-0059). It proves the protocol end to end:
// discovery, sync-collection, multiget, If-Match/If-None-Match, 404 members, a
// rejected sync token. iCloud's quirks live in the unit suite's fake; real
// iCloud and Nextcloud are the owner's manual check (DEVICE-CHECKS.md).
const enabled = process.env.INTEGRATION === '1';
const RADICALE = process.env.CALDAV_TEST_URL || 'http://127.0.0.1:5232';
const USER = 'alice';
const PASSWORD = 'alice-app-pw';
const prefix = `oph380-${Date.now()}`;
const CAL = `/${USER}/${prefix}/`;
const KEY = 'a'.repeat(64);
const basic = `Basic ${Buffer.from(`${USER}:${PASSWORD}`).toString('base64')}`;

/** Raw DAV requests, as the user's own calendar app would make them. */
async function dav(method, path, { body, headers = {} } = {}) {
  const res = await fetch(new URL(path, RADICALE), {
    method,
    headers: { authorization: basic, ...headers },
    body,
  });
  return { status: res.status, etag: res.headers.get('etag'), text: await res.text() };
}

async function waitForRadicale() {
  // Fail loudly, never skip: a missing server must not read as a green suite.
  for (let i = 0; i < 60; i += 1) {
    try {
      const res = await fetch(new URL(`/${USER}/`, RADICALE), {
        method: 'PROPFIND',
        headers: { authorization: basic, depth: '0' },
      });
      if (res.status === 207) return;
    } catch {
      // not up yet
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Radicale is not answering at ${RADICALE} — docker compose up -d radicale`);
}

const VTZ =
  'BEGIN:VTIMEZONE\r\nTZID:Europe/Istanbul\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\nTZOFFSETFROM:+0300\r\nTZOFFSETTO:+0300\r\nTZNAME:+03\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n';

describe.runIf(enabled)('integration: CalDAV connector against Radicale', () => {
  let app;
  let owner;
  let accountId;

  const api = (method, url, payload) =>
    app.inject({ method, url, headers: owner.headers, payload });
  const account = () => app.db('calendar_accounts').where({ id: accountId }).first();
  const task = (id) => app.db('tasks').where({ id }).first();
  const linkOf = (taskId) => app.db('calendar_event_links').where({ task_id: taskId }).first();
  const href = (taskId) => `${CAL}alliswell-${taskId}.ics`;
  const wait = (fn) => vi.waitFor(fn, { timeout: 15000, interval: 150 });
  const syncNow = async () => {
    const before = (await account()).last_synced_at;
    await app.calendarSync.sweep();
    await wait(async () => {
      const after = (await account()).last_synced_at;
      expect(after && (!before || new Date(after) > new Date(before))).toBeTruthy();
    });
  };
  const createTask = async (payload) => {
    const res = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, payload);
    expect(res.statusCode).toBe(201);
    const id = res.json().id;
    await wait(async () => {
      expect((await dav('GET', href(id))).status).toBe(200);
      expect(await linkOf(id)).toBeTruthy();
    });
    return id;
  };

  beforeAll(async () => {
    await waitForRadicale();
    const made = await dav('MKCALENDAR', CAL, {
      headers: { 'content-type': 'application/xml' },
      body:
        '<?xml version="1.0"?><C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:set><D:prop><D:displayname>OPH-380 test</D:displayname>' +
        '<C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set></D:prop></D:set></C:mkcalendar>',
    });
    expect(made.status).toBe(201);

    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '100',
        CALENDAR_TOKEN_KEY: KEY,
        CALDAV_ENABLED: 'true',
        CALDAV_ALLOW_PRIVATE_HOSTS: 'true',
        REDIS_KEY_PREFIX: prefix,
      }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${prefix}-owner@example.com`, password: 'integration-pw-9' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    owner = {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  });

  afterAll(async () => {
    if (app) {
      const users = await app.db('users').where('email', 'like', `${prefix}%`).select('id');
      const ids = users.map((u) => u.id);
      if (ids.length > 0) {
        await app.db('workspaces').whereIn('owner_id', ids).delete();
        await app.db('users').whereIn('id', ids).delete();
      }
      await app.close();
    }
    await dav('DELETE', CAL).catch(() => null);
  });

  it('wrong password → 422 CALDAV_AUTH_FAILED, nothing stored', async () => {
    const res = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/integrations/caldav`, {
      server: 'generic',
      url: RADICALE,
      username: USER,
      password: 'not-it',
    });
    expect(res.statusCode).toBe(422);
    expect(res.json().code).toBe('CALDAV_AUTH_FAILED');
    expect(
      await app.db('calendar_accounts').where({ user_id: owner.user.id }).first(),
    ).toBeUndefined();
  });

  it('connect → choose → mirror → read back → delete → foreign events → resync → disconnect', async () => {
    // Connect through well-known discovery; Radicale lists the test calendar.
    const connected = await api(
      'POST',
      `/api/v1/workspaces/${owner.workspace.id}/integrations/caldav`,
      { server: 'generic', url: RADICALE, username: USER, password: PASSWORD },
    );
    expect(connected.statusCode).toBe(201);
    accountId = connected.json().account.id;
    expect(connected.json().calendars.map((c) => c.url)).toContain(CAL);

    const chosen = await api('PATCH', `/api/v1/integrations/caldav/accounts/${accountId}`, {
      calendarUrl: CAL,
    });
    expect(chosen.statusCode).toBe(200);
    expect(chosen.json().calendarName).toBe('OPH-380 test');

    // 1. A dated task lands in Radicale with our identity on it.
    const moverId = await createTask({
      title: 'Radicale işi',
      dueAt: '2030-06-02T12:00:00.000Z',
      scheduledStartAt: '2030-06-01T09:00:00.000Z',
      scheduledEndAt: '2030-06-01T10:00:00.000Z',
    });
    const stored = await dav('GET', href(moverId));
    expect(stored.text).toContain(`UID:${moverId}`);
    expect(stored.text).toContain(`URL:alliswell://task/${moverId}`);
    // X-properties survive a Radicale round trip (iCloud: the owner's check).
    expect(stored.text).toContain(`X-ALLISWELL-TASK-ID:${moverId}`);
    await syncNow(); // first full listing — our own event is an echo

    // 2. The user drags it (TZID + VTIMEZONE, as Apple Calendar writes it).
    const moved = stored.text
      .replace(/DTSTART:[0-9TZ]+/, 'DTSTART;TZID=Europe/Istanbul:20300601T150000')
      .replace(/DTEND:[0-9TZ]+/, 'DTEND;TZID=Europe/Istanbul:20300601T163000')
      .replace(/LAST-MODIFIED:[0-9TZ]+/, 'LAST-MODIFIED:20991231T000000Z')
      .replace('BEGIN:VEVENT', `${VTZ}BEGIN:VEVENT`);
    const put = await dav('PUT', href(moverId), {
      body: moved,
      headers: { 'content-type': 'text/calendar', 'if-match': stored.etag },
    });
    expect(put.status).toBeLessThan(300);
    await syncNow();
    await wait(async () => {
      const row = await task(moverId);
      expect(new Date(row.scheduled_start_at).toISOString()).toBe('2030-06-01T12:00:00.000Z');
      expect(new Date(row.scheduled_end_at).toISOString()).toBe('2030-06-01T13:30:00.000Z');
      // A move in the calendar is scheduling, never the deadline (ADR-0007).
      expect(new Date(row.due_at).toISOString()).toBe('2030-06-02T12:00:00.000Z');
    });

    // 3. Completing it marks the event ✓.
    await api('POST', `/api/v1/tasks/${moverId}/complete`);
    await wait(async () => {
      expect((await dav('GET', href(moverId))).text).toContain('SUMMARY:✓ [Task] Radicale işi');
    });

    // 4. The user deletes another task's event: the task stays, mirroring stops.
    const deletedId = await createTask({ title: 'Silinecek', dueAt: '2030-06-03T12:00:00.000Z' });
    expect((await dav('DELETE', href(deletedId))).status).toBeLessThan(300);
    await syncNow();
    await wait(async () => {
      const row = await task(deletedId);
      expect(row.deleted_at).toBeNull();
      expect(row.calendar_mirror_suppressed_at).not.toBeNull();
      expect((await linkOf(deletedId)).conflict_status).toBe('provider_deleted_local_exists');
    });

    // 5. Cancelling a task removes its event.
    const cancelId = await createTask({ title: 'İptal', dueAt: '2030-06-04T12:00:00.000Z' });
    await api('PATCH', `/api/v1/tasks/${cancelId}`, { status: 'cancelled' });
    await wait(async () => {
      expect((await dav('GET', href(cancelId))).status).toBe(404);
      expect(await linkOf(cancelId)).toBeUndefined();
    });

    // 6. The user's own events — one plain, one weekly — are cached for display.
    const year = new Date().getUTCFullYear() + 1;
    const plain = `${CAL}meeting-${prefix}.ics`;
    const weekly = `${CAL}weekly-${prefix}.ics`;
    const cal = (body) =>
      `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n${body}END:VCALENDAR\r\n`;
    await dav('PUT', plain, {
      headers: { 'content-type': 'text/calendar', 'if-none-match': '*' },
      body: cal(
        `BEGIN:VEVENT\r\nUID:m-${prefix}\r\nDTSTAMP:20300101T000000Z\r\nDTSTART:${year}0105T090000Z\r\nDTEND:${year}0105T100000Z\r\nSUMMARY:Toplantı\r\nEND:VEVENT\r\n`,
      ),
    });
    await dav('PUT', weekly, {
      headers: { 'content-type': 'text/calendar', 'if-none-match': '*' },
      body: cal(
        `BEGIN:VEVENT\r\nUID:w-${prefix}\r\nDTSTAMP:20300101T000000Z\r\nDTSTART:${year}0106T080000Z\r\nDTEND:${year}0106T083000Z\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nSUMMARY:Haftalık\r\nEND:VEVENT\r\n`,
      ),
    });
    await syncNow();
    const externals = () =>
      app
        .db('calendar_external_events')
        .where({ calendar_account_id: accountId })
        .whereNull('deleted_at')
        .select();
    await wait(async () => {
      const rows = await externals();
      expect(rows).toHaveLength(4);
      expect(rows.every((r) => r.provider === 'apple_caldav' && r.revision > 0)).toBe(true);
    });
    expect(
      (await externals()).find((r) => r.provider_event_id === externalIdFor(plain)).summary,
    ).toBe('Toplantı');

    await dav('DELETE', plain);
    await syncNow();
    await wait(async () => {
      expect((await externals()).every((r) => r.summary === 'Haftalık')).toBe(true);
    });

    // 7. A corrupted cursor → full resync that converges without duplicates.
    const linksBefore = await app
      .db('calendar_event_links')
      .where({ calendar_account_id: accountId })
      .select();
    await app
      .db('calendar_accounts')
      .where({ id: accountId })
      .update({ sync_token: 'http://radicale.org/ns/sync/nonsense' });
    await syncNow();
    const linksAfter = await app
      .db('calendar_event_links')
      .where({ calendar_account_id: accountId })
      .select();
    expect(linksAfter.map((l) => l.id).sort()).toEqual(linksBefore.map((l) => l.id).sort());
    expect((await account()).sync_token).not.toBe('http://radicale.org/ns/sync/nonsense');
    expect((await externals()).length).toBe(3);
    expect((await linkOf(moverId)).conflict_status).not.toBe('provider_deleted_local_exists');

    // 8. Disconnect: the password goes, the events stay.
    const row = await account();
    expect(decryptSecret(row.encrypted_app_password, KEY)).toBe(PASSWORD);
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/integrations/caldav/accounts/${accountId}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    expect((await account()).encrypted_app_password).toBeNull();
    expect((await dav('GET', href(moverId))).status).toBe(200);
  }, 120000);
});
