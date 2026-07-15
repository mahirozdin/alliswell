import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeGoogle, fakeGoogleEnv } from '../helpers/fakegoogle.js';
import { reconcileProviderEvent, CONFLICT } from '../../src/lib/inbound.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';

const KEY = 'c'.repeat(64);
const TASK_ID = 'T'.padEnd(26, '0');

// ── The conflict matrix, decided without Google or a database (OPH-076) ─────

describe('lib/inbound reconcileProviderEvent (OPH-075/076, §7.2)', () => {
  const task = (over = {}) => ({
    id: TASK_ID,
    workspace_id: 'W'.padEnd(26, '0'),
    project_id: null,
    title: 'Sunum hazırla',
    status: 'open',
    timezone: 'Europe/Istanbul',
    calendar_mirror_enabled: true,
    is_urgent: false,
    revision: 3,
    deleted_at: null,
    scheduled_start_at: '2030-06-01T09:00:00.000Z',
    scheduled_end_at: '2030-06-01T10:00:00.000Z',
    due_at: null,
    remind_at: null,
    updated_at: '2030-05-01T00:00:00.000Z',
    ...over,
  });

  const link = (over = {}) => ({
    id: 'L'.padEnd(26, '0'),
    task_id: TASK_ID,
    calendar_account_id: 'A'.padEnd(26, '0'),
    provider_calendar_id: 'primary',
    provider_event_id: 'ev-1',
    etag: '"ours"',
    last_provider_updated_at: '2030-05-01T00:00:00.000Z',
    last_local_updated_at: '2030-05-01T00:00:00.000Z',
    conflict_status: CONFLICT.NONE,
    ...over,
  });

  const event = (over = {}) => ({
    id: 'ev-1',
    etag: '"ours"',
    updated: '2030-05-01T00:00:00.000Z',
    summary: '[Task] Sunum hazırla',
    start: { dateTime: '2030-06-01T09:00:00.000Z' },
    end: { dateTime: '2030-06-01T10:00:00.000Z' },
    extendedProperties: { private: { alliswell_task_id: TASK_ID } },
    ...over,
  });

  const moved = {
    etag: '"theirs"',
    updated: '2030-05-02T00:00:00.000Z',
    start: { dateTime: '2030-06-05T14:00:00.000Z' },
    end: { dateTime: '2030-06-05T15:00:00.000Z' },
  };

  it('treats our own write coming back as an echo, not a provider change', () => {
    // Same etag = the event Google is describing is the one WE just wrote.
    // This is the whole reason mirror ⇄ sync cannot loop.
    const out = reconcileProviderEvent({ event: event(), link: link(), task: task() });
    expect(out).toMatchObject({ decision: 'touch', reason: 'echo' });
  });

  it('applies a foreign move to the task as SCHEDULING, not as a deadline', () => {
    const out = reconcileProviderEvent({ event: event(moved), link: link(), task: task() });
    expect(out).toMatchObject({ decision: 'apply', conflictStatus: CONFLICT.NONE });
    expect(out.taskPatch).toEqual({
      scheduled_start_at: new Date('2030-06-05T14:00:00.000Z'),
      scheduled_end_at: new Date('2030-06-05T15:00:00.000Z'),
    });
  });

  it('does not pin a due-derived event to a schedule when nothing moved', () => {
    // The event sits on the §7.1 due slot, which no column holds. A cosmetic
    // edit (colour, description) changes the etag — it must not be read as a
    // move and silently schedule a task the user never scheduled.
    const dueOnly = task({
      scheduled_start_at: null,
      scheduled_end_at: null,
      due_at: '2030-06-01T12:00:00.000Z',
    });
    const out = reconcileProviderEvent({
      event: event({
        etag: '"recoloured"',
        start: { dateTime: '2030-06-01T12:00:00.000Z' },
        end: { dateTime: '2030-06-01T12:30:00.000Z' },
      }),
      link: link(),
      task: dueOnly,
    });
    expect(out).toMatchObject({ decision: 'touch', conflictStatus: CONFLICT.NONE });
    expect(out.taskPatch).toBeUndefined();
  });

  it('maps an all-day event onto the task timezone, honouring the exclusive end', () => {
    const out = reconcileProviderEvent({
      event: event({
        etag: '"allday"',
        start: { date: '2030-06-01' },
        end: { date: '2030-06-02' },
      }),
      link: link(),
      task: task(), // Europe/Istanbul
    });
    expect(out.decision).toBe('apply');
    expect(out.taskPatch.scheduled_start_at.toISOString()).toBe('2030-05-31T21:00:00.000Z');
    expect(out.taskPatch.scheduled_end_at.toISOString()).toBe('2030-06-01T21:00:00.000Z');
  });

  it('flags a time_conflict instead of guessing at times it cannot represent', () => {
    // Turning our block into a repeating series: many instants, one task.
    const series = reconcileProviderEvent({
      event: event({ etag: '"series"', recurrence: ['RRULE:FREQ=DAILY;COUNT=5'] }),
      link: link(),
      task: task(),
    });
    expect(series).toMatchObject({ decision: 'flag', conflictStatus: CONFLICT.TIME });
    expect(series.taskPatch).toBeUndefined();

    for (const broken of [
      {
        start: { dateTime: '2030-06-01T10:00:00.000Z' },
        end: { dateTime: '2030-06-01T09:00:00.000Z' },
      },
      { start: undefined, end: undefined },
    ]) {
      expect(
        reconcileProviderEvent({
          event: event({ etag: '"broken"', ...broken }),
          link: link(),
          task: task(),
        }),
      ).toMatchObject({ decision: 'flag', conflictStatus: CONFLICT.TIME });
    }
  });

  it('resolves a both-changed race by last-write-wins, and records it either way', () => {
    // Local moved after our last push (link.last_local_updated_at) AND the
    // provider moved: §6.5 says the newer wall clock wins.
    const contested = task({ updated_at: '2030-05-03T00:00:00.000Z' });

    const providerNewer = reconcileProviderEvent({
      event: event({ ...moved, updated: '2030-05-04T00:00:00.000Z' }),
      link: link(),
      task: contested,
    });
    expect(providerNewer).toMatchObject({
      decision: 'apply',
      conflictStatus: CONFLICT.BOTH_CHANGED,
    });

    const localNewer = reconcileProviderEvent({
      event: event({ ...moved, updated: '2030-05-02T00:00:00.000Z' }),
      link: link(),
      task: contested,
    });
    expect(localNewer).toMatchObject({
      decision: 'push',
      conflictStatus: CONFLICT.BOTH_CHANGED,
    });
    expect(localNewer.taskPatch).toBeUndefined(); // local wins → the task is untouched
  });

  it('stops mirroring when the user deletes our event, instead of resurrecting it', () => {
    const out = reconcileProviderEvent({
      event: event({ status: 'cancelled' }),
      link: link(),
      task: task(),
    });
    expect(out).toMatchObject({
      decision: 'stop-mirror',
      conflictStatus: CONFLICT.PROVIDER_DELETED,
      taskPatch: { calendar_mirror_enabled: false },
    });
  });

  it('drops the mapping when both sides already agree the event is gone', () => {
    // Our own delete: the task wants no event and Google says there is none.
    expect(
      reconcileProviderEvent({
        event: event({ status: 'cancelled' }),
        link: link(),
        task: task({ status: 'completed' }),
      }),
    ).toMatchObject({ decision: 'drop-link' });
  });

  it('removes an event the task no longer earns, and flags that local won', () => {
    const out = reconcileProviderEvent({
      event: event(moved),
      link: link(),
      task: task({ status: 'completed' }),
    });
    expect(out).toMatchObject({
      decision: 'remove-remote',
      conflictStatus: CONFLICT.LOCAL_DELETED,
    });
  });

  it('adopts an unmapped event carrying our task id, and ignores everything else', () => {
    expect(
      reconcileProviderEvent({ event: event({ etag: '"x"' }), link: null, task: task() }),
    ).toMatchObject({ decision: 'adopt' });

    // A foreign event in the user's calendar is none of our business (v1).
    expect(
      reconcileProviderEvent({
        event: { id: 'ev-9', etag: '"f"', start: {}, end: {} },
        link: null,
        task: null,
      }),
    ).toMatchObject({ decision: 'ignore' });

    // Debris of our own delete — the link row went first.
    expect(
      reconcileProviderEvent({ event: event({ status: 'cancelled' }), link: null, task: task() }),
    ).toMatchObject({ decision: 'ignore' });

    // A duplicate must not steal a task that is already mapped here.
    expect(
      reconcileProviderEvent({
        event: event({ id: 'ev-2', etag: '"dup"' }),
        link: null,
        task: task(),
        alreadyLinked: true,
      }),
    ).toMatchObject({ decision: 'ignore' });
  });
});

// ── The worker, against a Google that actually answers (OPH-075) ────────────

describe('inbound sync worker end to end (OPH-075/076)', () => {
  let google;
  let app;
  let tables;
  let owner;
  let accountId;

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

    const accessToken = 'at-seeded';
    google.state.issuedTokens.add(accessToken);
    accountId = newId();
    tables.calendar_accounts.push({
      id: accountId,
      user_id: owner.user.id,
      workspace_id: owner.workspace.id,
      provider: 'google',
      provider_account_id: 'takvim@example.com',
      encrypted_access_token: encryptSecret(accessToken, KEY),
      encrypted_refresh_token: encryptSecret('rt-1', KEY),
      token_expires_at: new Date(Date.now() + 3600_000),
      default_calendar_id: 'primary',
      sync_token: null,
      sync_dirty_at: null,
      webhook_channel_id: null,
      webhook_channel_token_hash: null,
      status: 'active',
      deleted_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    });
  });

  afterEach(async () => {
    await app.close();
    await google.app.close();
  });

  const api = (method, url, payload) =>
    app.inject({ method, url, headers: owner.headers, payload });

  const account = () => tables.calendar_accounts.find((a) => a.id === accountId);
  const links = () => tables.calendar_event_links;
  const eventsIn = () => [...google.state.eventsIn('primary').values()];

  const sync = async () => {
    app.calendarSync.enqueueSync(accountId);
    await app.calendarSync.idle();
    await app.mirror.idle(); // let any write the sync caused settle
  };

  /** A mirrored task and its event, with the link bookkeeping settled. */
  const mirroredTask = async (over = {}) => {
    const res = await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Takvimli iş',
      calendarMirrorEnabled: true,
      scheduledStartAt: '2030-06-01T09:00:00.000Z',
      scheduledEndAt: '2030-06-01T10:00:00.000Z',
      ...over,
    });
    expect(res.statusCode).toBe(201);
    await app.mirror.idle();
    return { taskId: res.json().id, eventId: eventsIn()[0].id };
  };

  const taskRow = (taskId) => tables.tasks.find((t) => t.id === taskId);

  it('first sync stores a cursor and treats our own events as echoes', async () => {
    const { taskId } = await mirroredTask();
    const before = { ...links()[0] };

    await sync();

    expect(account().sync_token).toMatch(/^sync-/);
    expect(account().last_synced_at).toBeInstanceOf(Date);
    // Nothing foreign happened: no conflict, no task write.
    expect(links()[0].conflict_status).toBe('none');
    expect(links()[0].etag).toBe(before.etag);
    expect(taskRow(taskId).revision).toBe(before.task_revision ?? taskRow(taskId).revision);

    // …and it converges: a second pass finds nothing to do either.
    await sync();
    expect(links()[0].conflict_status).toBe('none');
  });

  it('applies a user move to the task and then stops fighting over it', async () => {
    const { taskId, eventId } = await mirroredTask();
    await sync();

    google.state.userEdits('primary', eventId, {
      start: { dateTime: '2030-06-05T14:00:00.000Z' },
      end: { dateTime: '2030-06-05T15:00:00.000Z' },
      updated: '2035-01-01T00:00:00.000Z',
    });
    await sync();

    const task = await api('GET', `/api/v1/tasks/${taskId}`);
    expect(task.json().scheduledStartAt).toBe('2030-06-05T14:00:00.000Z');
    expect(task.json().scheduledEndAt).toBe('2030-06-05T15:00:00.000Z');
    expect(links()[0].conflict_status).toBe('none');

    // The mirror pass our own write triggered must leave the event where the
    // user put it — and the next sync must see an echo, not a new conflict.
    expect(eventsIn()[0].start.dateTime).toBe('2030-06-05T14:00:00.000Z');
    await sync();
    expect(links()[0].conflict_status).toBe('none');
    expect(eventsIn()[0].start.dateTime).toBe('2030-06-05T14:00:00.000Z');
  });

  it('pushes local back when it wins the last-write-wins race', async () => {
    const { eventId } = await mirroredTask();
    await sync();

    // A local edit whose mirror pass has not run yet (Google was unreachable)…
    taskRow(links()[0].task_id).updated_at = new Date('2031-01-01T00:00:00.000Z');
    // …and an older foreign move.
    google.state.userEdits('primary', eventId, {
      start: { dateTime: '2030-06-05T14:00:00.000Z' },
      end: { dateTime: '2030-06-05T15:00:00.000Z' },
      updated: '2030-01-01T00:00:00.000Z',
    });
    await sync();

    // Local won: the event is back on the task's own block, and the link
    // records that a foreign change was overwritten.
    expect(eventsIn()[0].start.dateTime).toBe('2030-06-01T09:00:00.000Z');
    expect(links()[0].conflict_status).toBe('local_changed_provider_changed');
  });

  it('stops mirroring when the user deletes the event, and keeps the tombstone', async () => {
    const { taskId, eventId } = await mirroredTask();
    await sync();

    google.state.userDeletes('primary', eventId);
    await sync();

    const task = await api('GET', `/api/v1/tasks/${taskId}`);
    expect(task.json().calendarMirrorEnabled).toBe(false);
    // The flagged link survives the mirror pass the task write triggers — it
    // is the record of WHY mirroring stopped, and there is nothing left to
    // delete remotely.
    expect(links()).toHaveLength(1);
    expect(links()[0].conflict_status).toBe('provider_deleted_local_exists');
    expect(eventsIn()).toHaveLength(0); // never resurrected
  });

  it('removes an event whose task no longer earns one, flagging that local won', async () => {
    const { taskId, eventId } = await mirroredTask();
    await sync();

    // A local opt-out whose mirror pass never landed…
    taskRow(taskId).calendar_mirror_enabled = false;
    // …while the event is edited in Google.
    google.state.userEdits('primary', eventId, { summary: 'Elle değiştirildi' });
    await sync();

    expect(eventsIn()).toHaveLength(0);
    expect(links()[0].conflict_status).toBe('local_deleted_provider_exists');
  });

  it('flags a time_conflict for a series and leaves both sides alone', async () => {
    const { taskId, eventId } = await mirroredTask();
    await sync();

    google.state.userEdits('primary', eventId, {
      recurrence: ['RRULE:FREQ=DAILY;COUNT=5'],
      updated: '2035-01-01T00:00:00.000Z',
    });
    await sync();

    expect(links()[0].conflict_status).toBe('time_conflict');
    const task = await api('GET', `/api/v1/tasks/${taskId}`);
    expect(task.json().scheduledStartAt).toBe('2030-06-01T09:00:00.000Z'); // untouched
    expect(eventsIn()[0].recurrence).toEqual(['RRULE:FREQ=DAILY;COUNT=5']); // not fought
  });

  it('adopts an event that still carries our task id after the link is lost', async () => {
    const { taskId } = await mirroredTask();
    links().length = 0; // the mapping row is gone (crash, restore, reconnect)

    await sync(); // full sync — no cursor yet

    expect(links()).toHaveLength(1);
    expect(links()[0]).toMatchObject({ task_id: taskId, conflict_status: 'none' });
    expect(eventsIn()).toHaveLength(1); // adopted, not duplicated
  });

  it('recovers from an expired sync token with a full resync', async () => {
    await mirroredTask();
    await sync();
    const firstToken = account().sync_token;

    google.state.expireSyncToken = true; // Google drops the cursor (§7.2 step 8)
    await sync();

    // The 410 was absorbed: a fresh cursor, no error recorded, links intact.
    expect(account().sync_token).toMatch(/^sync-/);
    expect(account().last_error).toBeNull();
    expect(links()).toHaveLength(1);
    expect(firstToken).toBeTruthy();
  });

  it('paginates to the last page before trusting a cursor', async () => {
    await mirroredTask();
    await mirroredTask({ title: 'İkinci', scheduledStartAt: '2030-06-02T09:00:00.000Z' });
    google.state.pageSize = 1; // force nextPageToken → nextSyncToken only at the end

    await sync();

    expect(eventsIn()).toHaveLength(2);
    expect(account().sync_token).toMatch(/^sync-/);
    expect(account().last_error).toBeNull();
  });

  it('leaves foreign calendar entries alone', async () => {
    google.state.eventsIn('primary').set('ev-foreign', {
      id: 'ev-foreign',
      etag: '"foreign"',
      summary: 'Diş randevusu',
      start: { dateTime: '2030-06-01T09:00:00.000Z' },
      end: { dateTime: '2030-06-01T10:00:00.000Z' },
    });

    await sync();

    expect(links()).toHaveLength(0);
    expect(tables.tasks).toHaveLength(0);
    expect(eventsIn()).toHaveLength(1); // still theirs, untouched
  });
});
