import { describe, it, expect, beforeEach } from 'vitest';

import { sweepDuePushes, fireInstantOf, needsPush } from '../../src/db/reminder-push.js';
import { fakeDb } from '../helpers/fakedb.js';

const WORKSPACE = '01HZWORKSPACEAAAAAAAAAAAAA';
const USER = '01HZUSERAAAAAAAAAAAAAAAAAA';
const TASK = '01HZTASKAAAAAAAAAAAAAAAAAA';
const REMINDER = '01HZRMNDRAAAAAAAAAAAAAAAAA';

const NOW = new Date('2026-09-20T07:30:00.000Z');
/** Changed before the sweep; a device that synced after this is not stale. */
const CHANGED = new Date('2026-09-20T06:00:00.000Z');

/** A transport that records what it was asked to send and always succeeds. */
function fakeTransport(providers = ['webpush', 'fcm']) {
  const sends = [];
  return {
    sends,
    providers,
    async send(devices, payload) {
      sends.push({ deviceIds: devices.map((d) => d.id), payload });
      return devices.map((d) => ({ deviceId: d.id, outcome: 'sent' }));
    },
  };
}

describe('OPH-315 — the due sweep', () => {
  let db;
  let tables;
  let app;

  /** A device that has not synced since the reminder changed. */
  function device(id, platform, overrides = {}) {
    return {
      id,
      user_id: USER,
      platform,
      push_provider: platform === 'web' ? 'webpush' : 'fcm',
      push_token: platform === 'web' ? null : 'fcm-token',
      push_endpoint: platform === 'web' ? 'https://push.example/one' : null,
      last_seen_at: new Date('2026-09-20T05:00:00.000Z'),
      invalid_at: null,
      ...overrides,
    };
  }

  function reminder(overrides = {}) {
    return {
      id: REMINDER,
      task_id: TASK,
      kind: 'remind',
      remind_at: NOW,
      snoozed_until: null,
      status: 'scheduled',
      updated_at: CHANGED,
      deleted_at: null,
      revision: 7,
      ...overrides,
    };
  }

  beforeEach(() => {
    ({ db, tables } = fakeDb());
    tables.tasks.push({ id: TASK, workspace_id: WORKSPACE });
    tables.workspace_members.push({ workspace_id: WORKSPACE, user_id: USER });
    app = {
      db,
      config: { env: 'test', push: { sweepSec: 60, dueWindowSec: 300 } },
      pushTransport: fakeTransport(),
      log: { info: () => {}, warn: () => {}, error: () => {} },
    };
  });

  it('pushes to a browser, because a closed tab has no clock of its own', async () => {
    tables.reminders.push(reminder());
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    const result = await sweepDuePushes(app, { now: NOW });

    expect(result).toEqual({ due: 1, claimed: 1, sent: 1, failed: 0 });
    expect(app.pushTransport.sends).toHaveLength(1);
    expect(app.pushTransport.sends[0].payload).toEqual({
      v: 1,
      type: 'reminder',
      reminderId: REMINDER,
      taskId: TASK,
      fireAt: '2026-09-20T07:30:00.000Z',
      alert: 'reminder_due',
    });
  });

  it('sends once when the sweep meets the same reminder twice', async () => {
    tables.reminders.push(reminder());
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    await sweepDuePushes(app, { now: NOW });
    const second = await sweepDuePushes(app, { now: new Date(NOW.getTime() + 30_000) });

    expect(second).toEqual({ due: 1, claimed: 0, sent: 0, failed: 0 });
    expect(app.pushTransport.sends).toHaveLength(1);
    expect(tables.reminder_push_log).toHaveLength(1);
    expect(tables.reminder_push_log[0].result).toBe('sent');
  });

  it('leaves a phone alone when it synced after the change, and wakes a stale one', async () => {
    tables.reminders.push(reminder());
    tables.notification_devices.push(
      // Synced AFTER the reminder changed — it already holds the alarm.
      device('01HZDEVFRESHAAAAAAAAAAAAAA', 'android', {
        last_seen_at: new Date('2026-09-20T06:30:00.000Z'),
      }),
      device('01HZDEVSTALEAAAAAAAAAAAAAA', 'android'),
    );

    const result = await sweepDuePushes(app, { now: NOW });

    expect(result.claimed).toBe(1);
    expect(app.pushTransport.sends[0].deviceIds).toEqual(['01HZDEVSTALEAAAAAAAAAAAAAA']);
  });

  it('sweeps a snoozed reminder at snoozed_until, not at the instant it first rang', async () => {
    // The trap the backlog would have walked into: `remind_at` is two hours in
    // the past and outside any window, and the row that matters is the snooze.
    tables.reminders.push(
      reminder({
        status: 'snoozed',
        remind_at: new Date('2026-09-20T05:30:00.000Z'),
        snoozed_until: NOW,
      }),
    );
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    const result = await sweepDuePushes(app, { now: NOW });

    expect(result.sent).toBe(1);
    expect(app.pushTransport.sends[0].payload.fireAt).toBe('2026-09-20T07:30:00.000Z');
    // And the log is stamped with the instant this delivery was about, so the
    // next snooze of the same reminder is a new claim rather than a duplicate.
    expect(tables.reminder_push_log[0].fire_at).toEqual(NOW);
  });

  it('does not ring early: the window looks back, never forward', async () => {
    tables.reminders.push(reminder({ remind_at: new Date(NOW.getTime() + 120_000) }));
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    expect(await sweepDuePushes(app, { now: NOW })).toEqual({
      due: 0,
      claimed: 0,
      sent: 0,
      failed: 0,
    });
    expect(app.pushTransport.sends).toHaveLength(0);
  });

  it('still finds what fell due while a missed tick was not looking', async () => {
    tables.reminders.push(reminder({ remind_at: new Date(NOW.getTime() - 240_000) }));
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    expect((await sweepDuePushes(app, { now: NOW })).sent).toBe(1);
  });

  it('never touches the reminder row — delivery is not a revision', async () => {
    tables.reminders.push(reminder());
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    await sweepDuePushes(app, { now: NOW });

    expect(tables.reminders[0].status).toBe('scheduled');
    expect(tables.reminders[0].revision).toBe(7);
    expect(tables.sync_revisions).toHaveLength(0);
  });

  it('does not claim a device this instance cannot reach', async () => {
    // A browser-only instance meeting a phone: claiming it would burn the
    // idempotency key for an instant that never gets a second attempt.
    app.pushTransport = fakeTransport(['webpush']);
    tables.reminders.push(reminder());
    tables.notification_devices.push(device('01HZDEVANDROIDAAAAAAAAAAAA', 'android'));

    expect((await sweepDuePushes(app, { now: NOW })).claimed).toBe(0);
    expect(tables.reminder_push_log).toHaveLength(0);
  });

  it('renders the sentence in the device language, falling back to the account', async () => {
    // OPH-320: a phone set to Turkish and a laptop set to English belong to
    // the same person, which is the whole reason the device carries a locale.
    tables.users.push({ id: USER, locale: 'tr-TR' });
    tables.reminders.push(reminder());
    tables.notification_devices.push(
      device('01HZDEVPHONEAAAAAAAAAAAAAA', 'android', { locale: 'en-GB' }),
      device('01HZDEVTABLETAAAAAAAAAAAAA', 'android', { locale: null }),
    );

    const sent = [];
    app.pushTransport = {
      providers: ['fcm'],
      async send(devices) {
        for (const d of devices) sent.push([d.id, d.locale]);
        return devices.map((d) => ({ deviceId: d.id, outcome: 'sent' }));
      },
    };

    await sweepDuePushes(app, { now: NOW });

    expect(sent).toEqual([
      ['01HZDEVPHONEAAAAAAAAAAAAAA', 'en-GB'],
      // Said nothing, so the account answers.
      ['01HZDEVTABLETAAAAAAAAAAAAA', 'tr-TR'],
    ]);
  });

  it('skips a device that was written off until it registers again', async () => {
    tables.reminders.push(reminder());
    tables.notification_devices.push(
      device('01HZDEVGONEAAAAAAAAAAAAAAA', 'web', { invalid_at: new Date() }),
    );

    expect((await sweepDuePushes(app, { now: NOW })).claimed).toBe(0);
  });

  it('does nothing at all on an instance with no credentials', async () => {
    app.pushTransport = null;
    tables.reminders.push(reminder());
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    expect(await sweepDuePushes(app, { now: NOW })).toEqual({
      due: 0,
      claimed: 0,
      sent: 0,
      failed: 0,
    });
    expect(tables.reminder_push_log).toHaveLength(0);
  });

  it('writes the failure down rather than retrying it forever', async () => {
    app.pushTransport = {
      providers: ['webpush'],
      async send(devices) {
        return devices.map((d) => ({ deviceId: d.id, outcome: 'failed', retryable: true }));
      },
    };
    tables.reminders.push(reminder());
    tables.notification_devices.push(device('01HZDEVWEBAAAAAAAAAAAAAAAA', 'web'));

    const result = await sweepDuePushes(app, { now: NOW });

    expect(result).toEqual({ due: 1, claimed: 1, sent: 0, failed: 1 });
    expect(tables.reminder_push_log[0].result).toBe('failed');
    expect(tables.reminder_push_log[0].sent_at).toBeNull();
  });
});

describe('OPH-315 — the two rules on their own', () => {
  it('reads the fire instant off the status, not off one column', () => {
    expect(fireInstantOf({ status: 'scheduled', remind_at: NOW, snoozed_until: null })).toBe(NOW);
    expect(fireInstantOf({ status: 'snoozed', remind_at: CHANGED, snoozed_until: NOW })).toBe(NOW);
    // A snooze that was cleared in the same transaction as the status: fall
    // back rather than send `null` to the payload builder.
    expect(fireInstantOf({ status: 'snoozed', remind_at: NOW, snoozed_until: null })).toBe(NOW);
  });

  it('asks one question of a device, and a different one of a browser', () => {
    const reminder = { updated_at: CHANGED };
    const synced = { platform: 'android', last_seen_at: new Date(CHANGED.getTime() + 1000) };
    const stale = { platform: 'android', last_seen_at: new Date(CHANGED.getTime() - 1000) };

    expect(needsPush(synced, reminder)).toBe(false);
    expect(needsPush(stale, reminder)).toBe(true);
    // The web is pushed to even when it is perfectly up to date: holding the
    // alarm locally buys a browser nothing (ADR-0038 §3).
    expect(needsPush({ ...synced, platform: 'web' }, reminder)).toBe(true);
  });
});
