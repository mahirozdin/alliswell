import { describe, it, expect, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeCaldav, fakeCaldavEnv } from '../helpers/fakecaldav.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';
import { externalIdFor } from '../../src/lib/caldav/ical.js';

const KEY = 'f'.repeat(64);
const CAL = '/1234/calendars/home/';

describe('CalDAV mirror + inbound sync, end to end on the inline queue (OPH-380)', () => {
  let fake;
  let app;
  let tables;
  let owner;
  let accountId;

  const boot = async ({ enabled = true, password } = {}) => {
    fake = await startFakeCaldav();
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      CALENDAR_TOKEN_KEY: KEY,
      ...fakeCaldavEnv(fake.url),
      ...(enabled ? {} : { CALDAV_ENABLED: 'false' }),
    });
    ({ app, tables } = await buildTestApp({ config }));
    owner = await registerUser(app, { email: 'owner@example.com' });
    accountId = newId();
    tables.calendar_accounts.push({
      id: accountId,
      user_id: owner.user.id,
      workspace_id: owner.workspace.id,
      provider: 'apple_caldav',
      provider_account_id: `${new URL(fake.url).host}/${fake.state.username}`,
      caldav_kind: 'icloud',
      caldav_server_url: fake.url,
      principal_url: `${fake.url}/1234/principal/`,
      calendar_home_url: `${fake.url}/1234/calendars/`,
      encrypted_app_password: encryptSecret(password ?? fake.state.password, KEY),
      default_calendar_id: CAL,
      calendar_display_name: 'Home',
      sync_token: null,
      status: 'active',
      deleted_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    });
  };

  afterEach(async () => {
    await app.close();
    await fake.close();
  });

  const api = (method, url, payload) =>
    app.inject({ method, url, headers: owner.headers, payload });
  const account = () => tables.calendar_accounts.find((a) => a.id === accountId);
  const links = () => tables.calendar_event_links;
  const resources = () => fake.state.resourcesIn(CAL);
  const taskRow = (id) => tables.tasks.find((t) => t.id === id);
  const href = (taskId) => `${CAL}alliswell-${taskId}.ics`;

  const settle = async () => {
    for (let i = 0; i < 4; i += 1) {
      await app.mirror.idle();
      await app.calendarSync.idle();
    }
  };
  const sync = async () => {
    app.calendarSync.enqueueSync(accountId);
    await settle();
  };
  const createTask = async (over = {}) => {
    const res = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Takvimli iş',
      scheduledStartAt: '2030-06-01T09:00:00.000Z',
      scheduledEndAt: '2030-06-01T10:00:00.000Z',
      ...over,
    });
    expect(res.statusCode).toBe(201);
    await settle();
    return res.json().id;
  };
  /** The user moves the event in their calendar app (Apple Calendar style: TZID). */
  const userMoves = (taskId, startLocal, endLocal) => {
    const current = fake.state.resource(href(taskId)).ics;
    const moved = current
      .replace(/DTSTART:[0-9TZ]+/, `DTSTART;TZID=Europe/Istanbul:${startLocal}`)
      .replace(/DTEND:[0-9TZ]+/, `DTEND;TZID=Europe/Istanbul:${endLocal}`)
      .replace(/LAST-MODIFIED:[0-9TZ]+/, 'LAST-MODIFIED:20991231T000000Z');
    fake.state.userPut(href(taskId), moved);
  };

  it('create: If-None-Match * at the deterministic href; the link keeps the etag', async () => {
    await boot();
    const taskId = await createTask();
    const resource = fake.state.resource(href(taskId));
    expect(resource.ics).toContain(`UID:${taskId}`);
    expect(resource.ics).toContain('DTSTART:20300601T090000Z');
    expect(resource.ics).toContain(`X-ALLISWELL-TASK-ID:${taskId}`);
    const put = fake.state.requests.find((r) => r.method === 'PUT');
    expect(put.headers['if-none-match']).toBe('*');
    expect(links()).toHaveLength(1);
    expect(links()[0]).toMatchObject({
      provider: 'apple_caldav',
      provider_calendar_id: CAL,
      provider_event_id: href(taskId),
      provider_event_uid: taskId,
      etag: resource.etag,
      conflict_status: 'none',
    });
  });

  it('update: GET + merge + PUT If-Match; the user’s alarm survives; complete → ✓; cancel → DELETE', async () => {
    await boot();
    const taskId = await createTask();
    // The user adds an alarm in their calendar app; the poll sees it (touch).
    const withAlarm = fake.state
      .resource(href(taskId))
      .ics.replace(
        'END:VEVENT',
        'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT10M\r\nEND:VALARM\r\nEND:VEVENT',
      );
    fake.state.userPut(href(taskId), withAlarm);
    await sync();
    expect(links()[0].etag).toBe(fake.state.resource(href(taskId)).etag);

    fake.state.requests.length = 0;
    await api('PATCH', `/api/v1/tasks/${taskId}`, { title: 'Yeni ad' });
    await settle();
    const put = fake.state.requests.find((r) => r.method === 'PUT');
    expect(put.headers['if-match']).toBeTruthy();
    const after = fake.state.resource(href(taskId));
    expect(after.ics).toContain('SUMMARY:[Task] Yeni ad');
    expect(after.ics).toContain('TRIGGER:-PT10M');
    expect(links()[0].etag).toBe(after.etag);

    await api('POST', `/api/v1/tasks/${taskId}/complete`);
    await settle();
    expect(fake.state.resource(href(taskId)).ics).toContain('SUMMARY:✓ [Task] Yeni ad');

    await api('PATCH', `/api/v1/tasks/${taskId}`, { status: 'cancelled' });
    await settle();
    expect(fake.state.resource(href(taskId))).toBeNull();
    expect(links()).toHaveLength(0);
  });

  it('inbound: a drag writes scheduled_*, never due_at; our echo is never fetched', async () => {
    await boot();
    const taskId = await createTask({ dueAt: '2030-06-02T12:00:00.000Z' });
    await sync(); // first full listing: our own event, etag matches → no multiget
    expect(fake.state.multigets ?? 0).toBe(0);

    userMoves(taskId, '20300601T150000', '20300601T163000');
    await sync();
    const task = taskRow(taskId);
    expect(new Date(task.scheduled_start_at).toISOString()).toBe('2030-06-01T12:00:00.000Z');
    expect(new Date(task.scheduled_end_at).toISOString()).toBe('2030-06-01T13:30:00.000Z');
    expect(new Date(task.due_at).toISOString()).toBe('2030-06-02T12:00:00.000Z');
    expect(fake.state.multigets).toBe(1);
  });

  it('a foreign etag seen by the mirror runs the inbound decision first', async () => {
    await boot();
    const taskId = await createTask();
    // The user drags it; before any poll, a local edit triggers a mirror pass.
    userMoves(taskId, '20300601T180000', '20300601T190000');
    await api('PATCH', `/api/v1/tasks/${taskId}`, { priority: 'high' });
    await settle();
    // The user's move was newer (LAST-MODIFIED 2099): it wins, nothing overwrote it.
    expect(new Date(taskRow(taskId).scheduled_start_at).toISOString()).toBe(
      '2030-06-01T15:00:00.000Z',
    );
    expect(fake.state.resource(href(taskId)).ics).toContain(
      'DTSTART;TZID=Europe/Istanbul:20300601T180000',
    );
  });

  it('a user delete keeps the task, suppresses the mirror and leaves the tombstone', async () => {
    await boot();
    const taskId = await createTask();
    fake.state.userDelete(href(taskId));
    await sync();
    expect(taskRow(taskId).deleted_at ?? null).toBeNull();
    expect(taskRow(taskId).calendar_mirror_suppressed_at).toBeTruthy();
    expect(links()[0].conflict_status).toBe('provider_deleted_local_exists');
    // Later edits do not bring it back.
    await api('PATCH', `/api/v1/tasks/${taskId}`, { title: 'still here' });
    await settle();
    expect(fake.state.resource(href(taskId))).toBeNull();
  });

  it('a 412 on create from our own existing resource is adopted, not duplicated', async () => {
    await boot();
    const taskId = await createTask();
    // Lose the link (a crash after the PUT), then mirror again.
    tables.calendar_event_links.length = 0;
    await api('PATCH', `/api/v1/tasks/${taskId}`, { title: 'adopted' });
    await settle();
    expect(resources().size).toBe(1);
    expect(links()).toHaveLength(1);
    expect(fake.state.resource(href(taskId)).ics).toContain('SUMMARY:[Task] adopted');
  });

  it('a revoked password flips the account to error — no throw, no retry storm', async () => {
    await boot({ password: 'revoked' });
    await createTask();
    expect(account().status).toBe('error');
    expect(account().last_error).toMatch(/reconnect/);
    expect(resources().size).toBe(0);
  });

  it('a rejected sync token → full resync, no duplicate links', async () => {
    await boot();
    await createTask();
    await sync();
    account().sync_token = 'http://fake/sync/999';
    await sync();
    expect(account().sync_token).toMatch(/^http:\/\/fake\/sync\/\d+$/);
    expect(links()).toHaveLength(1);
    expect(links()[0].conflict_status).toBe('none');
  });

  it('the user’s own events are cached (apple_caldav), series expanded, deletions dropped', async () => {
    await boot();
    const year = new Date().getUTCFullYear();
    const day = `${year + 1}0105`;
    fake.state.userPut(
      `${CAL}meeting.ics`,
      `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nBEGIN:VEVENT\r\nUID:m1\r\nDTSTART:${day}T090000Z\r\nDTEND:${day}T100000Z\r\nSUMMARY:Toplantı\r\nLOCATION:Ofis\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n`,
    );
    fake.state.userPut(
      `${CAL}weekly.ics`,
      `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nBEGIN:VEVENT\r\nUID:w1\r\nDTSTART:${day}T080000Z\r\nDTEND:${day}T083000Z\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nSUMMARY:Haftalık\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n`,
    );
    await sync();
    const live = () => tables.calendar_external_events.filter((e) => e.deleted_at == null);
    expect(live()).toHaveLength(4);
    expect(live().every((e) => e.provider === 'apple_caldav' && e.revision > 0)).toBe(true);
    const single = live().find((e) => e.provider_event_id === externalIdFor(`${CAL}meeting.ics`));
    expect(single).toMatchObject({ summary: 'Toplantı', location: 'Ofis' });
    expect(
      live().filter((e) => e.provider_event_id.startsWith(`${externalIdFor(`${CAL}weekly.ics`)}#`)),
    ).toHaveLength(3);

    // Shorten the series: the dropped instance goes; delete the meeting: it goes.
    fake.state.userPut(
      `${CAL}weekly.ics`,
      fake.state.resource(`${CAL}weekly.ics`).ics.replace('COUNT=3', 'COUNT=2'),
    );
    fake.state.userDelete(`${CAL}meeting.ics`);
    await sync();
    expect(live()).toHaveLength(2);
    expect(live().every((e) => e.summary === 'Haftalık')).toBe(true);
  });

  it('the sweep polls CalDAV accounts only while the connector is on', async () => {
    await boot();
    expect(await app.calendarSync.sweep()).toBe(1);
    await settle();
    expect(account().last_synced_at).toBeInstanceOf(Date);
    await app.close();
    await fake.close();
    await boot({ enabled: false });
    expect(await app.calendarSync.sweep()).toBe(0);
    await createTask();
    expect(resources().size).toBe(0);
  });
});
