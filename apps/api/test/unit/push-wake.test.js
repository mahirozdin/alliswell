import { describe, it, expect, beforeEach } from 'vitest';

import { sendAlarmStopWake, sendWakeHint } from '../../src/db/reminder-push.js';
import {
  alarmStopJobKey,
  createWakeDispatcher,
  createWakeGate,
  isAlarmStop,
  wakeJobKey,
  wakeMinuteOf,
} from '../../src/plugins/push-wake.js';
import { createJobRunner } from '../../src/queue/runner.js';
import { fakeDb } from '../helpers/fakedb.js';

const WORKSPACE = '01HZWORKSPACEAAAAAAAAAAAAA';
const USER = '01HZUSERAAAAAAAAAAAAAAAAAA';

/**
 * OPH-322 — the most graceful of the three triggers: a reminder changed, so
 * the devices that schedule it locally are told to sync, and the alarm then
 * rings from the device's own clock with its full behaviour.
 */
describe('the wake-up hint', () => {
  let db;
  let tables;
  let app;
  let sent;

  function device(id, platform, overrides = {}) {
    return {
      id,
      user_id: USER,
      platform,
      push_provider: platform === 'web' ? 'webpush' : 'fcm',
      push_token: 'fcm-token',
      invalid_at: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    ({ db, tables } = fakeDb());
    tables.workspace_members.push({ workspace_id: WORKSPACE, user_id: USER });
    sent = [];
    app = {
      db,
      log: { info: () => {}, warn: () => {}, error: () => {} },
      pushTransport: {
        providers: ['fcm', 'webpush'],
        async send(devices, payload) {
          sent.push({ deviceIds: devices.map((d) => d.id), payload });
          return devices.map((d) => ({ deviceId: d.id, outcome: 'sent' }));
        },
      },
    };
  });

  it('says only that something changed, never what', async () => {
    tables.notification_devices.push(device('01HZDEVANDROIDAAAAAAAAAAAA', 'android'));

    expect(await sendWakeHint(app, { workspaceId: WORKSPACE })).toBe(1);
    // The device is about to sync and find out for itself; anything more would
    // be a second copy of the truth crossing somebody else's servers.
    expect(sent[0].payload).toEqual({ v: 1, type: 'wake' });
  });

  it('wakes Android, and leaves iOS and browsers alone', async () => {
    tables.notification_devices.push(
      device('01HZDEVANDROIDAAAAAAAAAAAA', 'android'),
      // No background mode, a budgeted delivery, and a session a locked wake
      // cannot read (ADR-0038 §8) — iPhones get the visible fallback instead.
      device('01HZDEVIOSAAAAAAAAAAAAAAAA', 'ios'),
      // A Web Push subscription is userVisibleOnly: a "silent" push to a tab
      // is a contradiction the browser resolves by showing its own card.
      device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'),
    );

    await sendWakeHint(app, { workspaceId: WORKSPACE });

    expect(sent[0].deviceIds).toEqual(['01HZDEVANDROIDAAAAAAAAAAAA']);
  });

  it('skips a device that was written off', async () => {
    tables.notification_devices.push(
      device('01HZDEVGONEAAAAAAAAAAAAAAA', 'android', { invalid_at: new Date() }),
    );

    expect(await sendWakeHint(app, { workspaceId: WORKSPACE })).toBe(0);
    expect(sent).toHaveLength(0);
  });

  it('does nothing on an instance that cannot reach a phone', async () => {
    tables.notification_devices.push(device('01HZDEVANDROIDAAAAAAAAAAAA', 'android'));

    // A browser-only instance: VAPID keys, no FCM service account.
    app.pushTransport = { providers: ['webpush'], send: async () => [] };
    expect(await sendWakeHint(app, { workspaceId: WORKSPACE })).toBe(0);

    app.pushTransport = null;
    expect(await sendWakeHint(app, { workspaceId: WORKSPACE })).toBe(0);
    expect(sent).toHaveLength(0);
  });

  it('reaches every member of the workspace, not just the editor', async () => {
    const other = '01HZUSERBBBBBBBBBBBBBBBBBB';
    tables.workspace_members.push({ workspace_id: WORKSPACE, user_id: other });
    tables.notification_devices.push(
      device('01HZDEVONEAAAAAAAAAAAAAAAA', 'android'),
      device('01HZDEVTWOAAAAAAAAAAAAAAAA', 'android', { user_id: other }),
    );

    await sendWakeHint(app, { workspaceId: WORKSPACE });

    expect(sent[0].deviceIds).toHaveLength(2);
  });
});

describe('the storm control', () => {
  it('collapses a burst in one minute into a single hint', async () => {
    const runs = [];
    const gate = createWakeGate();
    const runner = createJobRunner(
      { log: { warn: () => {} } },
      {
        name: 'push-wake-test',
        handler: async (data) => runs.push(data),
        jobKey: wakeJobKey,
      },
    );

    // Somebody dragging a reminder across a calendar: ten commits, ten events.
    const minute = wakeMinuteOf(Date.UTC(2026, 8, 20, 7, 30, 15));
    for (let i = 0; i < 10; i += 1) {
      if (gate.admit(WORKSPACE, minute)) {
        await runner.enqueue({ workspaceId: WORKSPACE, minute });
      }
      // Awaited on purpose: this is what exposed the plan's assumption. Both
      // runners forget a key as the job leaves the queue, so without the gate
      // ten writes a few milliseconds apart produced FOUR hints, not one.
      await runner.idle();
    }

    expect(runs).toHaveLength(1);
  });

  it('the job key alone is not enough, which is why the gate exists', async () => {
    const runs = [];
    const runner = createJobRunner(
      { log: { warn: () => {} } },
      {
        name: 'push-wake-test',
        handler: async (data) => runs.push(data),
        jobKey: wakeJobKey,
      },
    );

    const minute = wakeMinuteOf(Date.UTC(2026, 8, 20, 7, 30, 15));
    for (let i = 0; i < 3; i += 1) {
      await runner.enqueue({ workspaceId: WORKSPACE, minute });
      await runner.idle();
    }

    // Measured, so the comment above is a fact and not a belief: the key is
    // the second line of defence, never the first.
    expect(runs.length).toBeGreaterThan(1);
  });

  it('forgets workspaces nobody has touched, rather than growing forever', () => {
    const gate = createWakeGate({ keep: 2, forgetAfterMinutes: 5 });
    gate.admit('old-1', 100);
    gate.admit('old-2', 100);
    gate.admit('fresh', 200); // trips the sweep

    expect(gate.size).toBe(1);
    // ...and a forgotten workspace is admitted again, which is correct: the
    // gate is a burst damper, not a record.
    expect(gate.admit('old-1', 200)).toBe(true);
  });

  it('does not collapse the next minute into the last one', async () => {
    const runs = [];
    const runner = createJobRunner(
      { log: { warn: () => {} } },
      { name: 'push-wake-test', handler: async (d) => runs.push(d), jobKey: wakeJobKey },
    );

    await runner.enqueue({ workspaceId: WORKSPACE, minute: 100 });
    await runner.idle();
    await runner.enqueue({ workspaceId: WORKSPACE, minute: 101 });
    await runner.idle();

    // A change an hour later must still wake the phone.
    expect(runs).toHaveLength(2);
  });

  it('buckets by the minute an instant falls in', () => {
    expect(wakeMinuteOf(Date.UTC(2026, 8, 20, 7, 30, 0))).toBe(
      wakeMinuteOf(Date.UTC(2026, 8, 20, 7, 30, 59)),
    );
    expect(wakeMinuteOf(Date.UTC(2026, 8, 20, 7, 30, 59))).not.toBe(
      wakeMinuteOf(Date.UTC(2026, 8, 20, 7, 31, 0)),
    );
  });
});

/**
 * OPH-436 (#50, #48) — the hint grows in two directions. A task or project
 * change wakes Android too (the home-screen widget shows them), still behind
 * the per-workspace minute. And a ringing urgent alarm that was acknowledged,
 * snoozed or closed somewhere else must reach the other ringing phones even
 * when that minute was already spent: the gate exists to damp bursts, not to
 * swallow the one change that stops a siren.
 */
describe('task, project and alarm-stop wakes', () => {
  const RINGING = '01HZDEVRINGAAAAAAAAAAAAAAA';
  const QUIET = '01HZDEVQUIETAAAAAAAAAAAAAA';
  const IOS = '01HZDEVIOSRINGAAAAAAAAAAAA';
  const REMINDER = '01HZREMINDERAAAAAAAAAAAAAA';
  const T0 = Date.UTC(2026, 10, 12, 7, 30, 10);

  let db;
  let tables;
  let app;
  let sent;
  let clock;
  let dispatch;
  let wake;
  let stop;

  beforeEach(() => {
    ({ db, tables } = fakeDb());
    tables.workspace_members.push({ workspace_id: WORKSPACE, user_id: USER });
    const dev = (id, platform, ringsUrgent) => ({
      id,
      user_id: USER,
      platform,
      push_provider: platform === 'web' ? 'webpush' : 'fcm',
      push_token: 'fcm-token',
      invalid_at: null,
      rings_urgent: ringsUrgent,
    });
    tables.notification_devices.push(
      dev(RINGING, 'android', true),
      dev(QUIET, 'android', false),
      dev(IOS, 'ios', true),
    );
    sent = [];
    clock = T0;
    app = {
      db,
      log: { info: () => {}, warn: () => {}, error: () => {} },
      pushTransport: {
        providers: ['fcm', 'webpush'],
        async send(devices, payload) {
          sent.push({ deviceIds: devices.map((d) => d.id).sort(), payload });
          return devices.map((d) => ({ deviceId: d.id, outcome: 'sent' }));
        },
      },
    };
    wake = createJobRunner(app, {
      name: 'push-wake-test',
      handler: (data) => sendWakeHint(app, data),
      jobKey: wakeJobKey,
    });
    stop = createJobRunner(app, {
      name: 'push-alarm-stop-test',
      handler: (data) => sendAlarmStopWake(app, data),
      jobKey: alarmStopJobKey,
    });
    dispatch = createWakeDispatcher({
      db,
      gate: createWakeGate(),
      wake,
      stop,
      now: () => clock,
    });
  });

  const settle = async () => {
    // The dispatcher reads the reminder before it enqueues; let that land.
    await new Promise((resolve) => setImmediate(resolve));
    await wake.idle();
    await stop.idle();
  };

  const change = (entityType, entityId = REMINDER, operation = 'update') =>
    dispatch({ workspaceId: WORKSPACE, entityType, entityId, operation });

  const reminder = (overrides = {}) => {
    tables.reminders.length = 0;
    tables.reminders.push({
      id: REMINDER,
      task_id: '01HZTASKAAAAAAAAAAAAAAAAAA',
      alarm_level: 'urgent',
      status: 'acknowledged',
      remind_at: new Date(T0 - 2 * 60_000),
      snoozed_until: null,
      updated_at: new Date(T0 - 1_000),
      ...overrides,
    });
  };

  const ALL_ANDROID = [QUIET, RINGING].sort();

  it('a task change wakes android devices once per workspace-minute', async () => {
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();

    expect(sent).toHaveLength(1);
    expect(sent[0]).toEqual({ deviceIds: ALL_ANDROID, payload: { v: 1, type: 'wake' } });

    clock = T0 + 60_000;
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();
    expect(sent).toHaveLength(2);
  });

  it('a project change wakes android devices', async () => {
    await change('project', '01HZPROJECTAAAAAAAAAAAAAAA');
    await settle();

    expect(sent).toEqual([{ deviceIds: ALL_ANDROID, payload: { v: 1, type: 'wake' } }]);
  });

  it('other entity types still wake nothing', async () => {
    await change('note', '01HZNOTEAAAAAAAAAAAAAAAAAA');
    await settle();

    expect(sent).toHaveLength(0);
  });

  it('an acknowledged urgent reminder in its ring window wakes even when the minute was already used', async () => {
    // A task write spent this workspace's minute a moment ago.
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();
    sent.length = 0;

    reminder({ status: 'acknowledged' });
    await change('reminder');
    await settle();

    // Only the phones that ring urgent alarms, Android only, payload unchanged.
    expect(sent).toEqual([{ deviceIds: [RINGING], payload: { v: 1, type: 'wake' } }]);
  });

  it('the same acknowledgement revision wakes once', async () => {
    reminder({ status: 'acknowledged' });
    await change('reminder');
    await settle();
    await change('reminder');
    await settle();

    const stops = sent.filter((s) => s.deviceIds.length === 1);
    expect(stops).toHaveLength(1);

    // A later revision of the same reminder is a new stop.
    reminder({ status: 'completed', updated_at: new Date(T0 + 500) });
    await change('reminder');
    await settle();
    expect(sent.filter((s) => s.deviceIds.length === 1)).toHaveLength(2);
    expect(alarmStopJobKey({ reminderId: REMINDER, revisionMs: T0 + 500 })).toBe(
      `alarm-stop:${REMINDER}:${T0 + 500}`,
    );
  });

  it('a transient push failure retries the alarm stop until it is sent', async () => {
    // FCM answers 503 once, then delivers.
    let calls = 0;
    app.pushTransport.send = async (devices, payload) => {
      calls += 1;
      sent.push({ deviceIds: devices.map((d) => d.id).sort(), payload });
      return devices.map((d) =>
        calls === 1
          ? { deviceId: d.id, outcome: 'failed', retryable: true, reason: 'HTTP 503' }
          : { deviceId: d.id, outcome: 'sent' },
      );
    };
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();
    sent.length = 0;
    // The task's hint spent the minute; the stop's first try is the one that fails.
    calls = 0;
    reminder({ status: 'acknowledged' });
    await change('reminder');
    await settle();

    expect(sent).toEqual([
      { deviceIds: [RINGING], payload: { v: 1, type: 'wake' } },
      { deviceIds: [RINGING], payload: { v: 1, type: 'wake' } },
    ]);
  });

  it('a permanent push failure does not retry the alarm stop', async () => {
    app.pushTransport.send = async (devices, payload) => {
      sent.push({ deviceIds: devices.map((d) => d.id).sort(), payload });
      return devices.map((d) => ({
        deviceId: d.id,
        outcome: 'failed',
        retryable: false,
        reason: 'HTTP 400',
      }));
    };
    reminder({ status: 'acknowledged' });
    await change('reminder');
    await settle();

    expect(sent.filter((s) => s.deviceIds.join() === RINGING)).toHaveLength(1);
  });

  it('a normal reminder acknowledgement stays behind the minute gate', async () => {
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();
    sent.length = 0;

    reminder({ alarm_level: 'normal', status: 'acknowledged' });
    await change('reminder');
    await settle();

    expect(sent).toHaveLength(0);
  });

  it('an acknowledgement outside the ring window stays behind the minute gate', async () => {
    await change('task', '01HZTASKAAAAAAAAAAAAAAAAAA');
    await settle();
    sent.length = 0;

    // 46 minutes ago: past the longest insistent chain (40) + 5.
    reminder({ status: 'acknowledged', remind_at: new Date(T0 - 46 * 60_000) });
    await change('reminder');
    await settle();
    // Two minutes ahead: it has not started ringing yet.
    reminder({
      status: 'cancelled',
      remind_at: new Date(T0 + 2 * 60_000),
      updated_at: new Date(T0 + 1),
    });
    await change('reminder');
    await settle();

    expect(sent).toHaveLength(0);
  });

  it('decides the ring window from remind_at, or the last snooze, and the status', () => {
    const base = {
      alarm_level: 'urgent',
      status: 'acknowledged',
      remind_at: new Date(T0),
      snoozed_until: null,
    };
    expect(isAlarmStop(base, T0)).toBe(true);
    expect(isAlarmStop({ ...base, remind_at: new Date(T0 - 45 * 60_000) }, T0)).toBe(true);
    expect(isAlarmStop({ ...base, remind_at: new Date(T0 - 45 * 60_000 - 1) }, T0)).toBe(false);
    expect(isAlarmStop({ ...base, remind_at: new Date(T0 + 60_000) }, T0)).toBe(true);
    expect(isAlarmStop({ ...base, remind_at: new Date(T0 + 60_001) }, T0)).toBe(false);
    // A snoozed alarm rang a moment ago by definition.
    expect(
      isAlarmStop({ ...base, status: 'snoozed', remind_at: new Date(T0 - 3 * 3_600_000) }, T0),
    ).toBe(true);
    // Acknowledged on its second ring: the ring started at the last snooze.
    expect(
      isAlarmStop(
        {
          ...base,
          remind_at: new Date(T0 - 2 * 3_600_000),
          snoozed_until: new Date(T0 - 60_000),
        },
        T0,
      ),
    ).toBe(true);
    expect(isAlarmStop({ ...base, status: 'scheduled' }, T0)).toBe(false);
    expect(isAlarmStop({ ...base, status: 'delivered' }, T0)).toBe(false);
    expect(isAlarmStop({ ...base, alarm_level: 'normal' }, T0)).toBe(false);
  });
});
