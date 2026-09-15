import { describe, it, expect, beforeEach } from 'vitest';

import { sendWakeHint } from '../../src/db/reminder-push.js';
import { createWakeGate, wakeJobKey, wakeMinuteOf } from '../../src/plugins/push-wake.js';
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
