import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const prefix = `oph436-${Date.now()}`;
const PASSWORD = 'integration-pw-436';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * OPH-436 (#48 phase 1) — acknowledging, snoozing or closing a ringing urgent
 * alarm wakes the user's other ringing Android phones, even when this
 * workspace's wake minute was already spent, through the real write paths,
 * the real post-commit event and the real job runner. The push provider is
 * the only fake: it records who would have been sent what.
 */
// Longer than the default: a test may first wait out the end of a minute.
describe.runIf(enabled)(
  'integration: an alarm stop wakes the other ringing phones',
  { timeout: 45_000 },
  () => {
    let app;
    let seq = 0;
    /** @type {Array<{ deviceIds: string[], payload: object }>} */
    let sent = [];

    beforeAll(async () => {
      app = await buildApp({
        config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '500' }),
      });
      // The instance under test has no FCM credentials; the plugin reads the
      // transport at event time, so a recording one stands in for the provider.
      app.pushTransport = {
        providers: ['fcm', 'webpush'],
        async send(devices, payload) {
          sent.push({ deviceIds: devices.map((d) => d.id).sort(), payload });
          return devices.map((d) => ({ deviceId: d.id, outcome: 'sent' }));
        },
      };
    });

    afterAll(async () => {
      if (!app) return;
      const users = await app.db('users').where('email', 'like', `${prefix}%`).select('id');
      const ids = users.map((u) => u.id);
      if (ids.length > 0) {
        await app.db('workspaces').whereIn('owner_id', ids).delete();
        await app.db('users').whereIn('id', ids).delete();
      }
      await app.close();
    });

    const account = async () => {
      seq += 1;
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { email: `${prefix}-${seq}@example.com`, password: PASSWORD },
      });
      expect(res.statusCode).toBe(201);
      const body = res.json();
      return {
        workspace: body.workspace,
        headers: { authorization: `Bearer ${body.tokens.accessToken}` },
      };
    };

    /** Registers a device and sets whether it rings urgent alarms. */
    const device = async (me, platform, ringsUrgent) => {
      const id = newId();
      const payload =
        platform === 'web'
          ? {
              platform,
              pushProvider: 'webpush',
              pushEndpoint: `https://push.example.com/${id}`,
              pushP256dh: 'p256dh-key',
              pushAuth: 'auth-key',
            }
          : { platform, pushToken: `fcm-${id}` };
      const put = await app.inject({
        method: 'PUT',
        url: `/api/v1/notification-devices/${id}`,
        headers: me.headers,
        payload,
      });
      expect([200, 201]).toContain(put.statusCode);
      const patch = await app.inject({
        method: 'PATCH',
        url: `/api/v1/notification-devices/${id}`,
        headers: me.headers,
        payload: { ringsUrgent },
      });
      expect(patch.statusCode).toBe(200);
      return id;
    };

    const waitFor = async (predicate, ms = 8_000) => {
      const until = Date.now() + ms;
      while (Date.now() < until) {
        if (predicate()) return true;
        await sleep(50);
      }
      return false;
    };

    /**
     * An urgent task whose alarm started ringing a minute ago. Creating it
     * spends the workspace's wake minute (every Android phone hears about the
     * new reminder); once that hint has gone out the log is cleared, so what is
     * left to see is only what the stop itself sends.
     */
    const ringingTask = async (me, allAndroid) => {
      // Keep the create and the stop inside one wake minute, or the minute gate
      // would admit the stop's ordinary hint as well and blur what is measured.
      const intoMinute = Date.now() % 60_000;
      if (intoMinute > 45_000) await sleep(60_000 - intoMinute + 250);

      const res = await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${me.workspace.id}/tasks`,
        headers: me.headers,
        payload: {
          title: 'Alarm stop',
          remindAt: new Date(Date.now() - 60_000).toISOString(),
          isUrgent: true,
        },
      });
      expect(res.statusCode).toBe(201);
      const task = res.json();
      const reminder = await app
        .db('reminders')
        .where({ task_id: task.id, kind: 'remind' })
        .first('id', 'alarm_level');
      expect(reminder.alarm_level).toBe('urgent');

      const expected = [...allAndroid].sort().join(',');
      expect(await waitFor(() => sent.some((s) => s.deviceIds.join(',') === expected))).toBe(true);
      await sleep(200);
      sent = [];
      return { task, reminderId: reminder.id };
    };

    const acknowledge = (me, reminderId) =>
      app.inject({
        method: 'POST',
        url: `/api/v1/reminders/${reminderId}/acknowledge`,
        headers: me.headers,
      });

    /** The sends that arrived after the stop, once they have settled. */
    const stopSends = async (count = 1) => {
      expect(await waitFor(() => sent.length >= count)).toBe(true);
      await sleep(300);
      return sent;
    };

    it('acknowledging on one device wakes the other ringing android devices', async () => {
      const me = await account();
      const first = await device(me, 'android', true);
      const second = await device(me, 'android', true);
      const { reminderId } = await ringingTask(me, [first, second]);

      const res = await acknowledge(me, reminderId);
      expect(res.statusCode).toBeLessThan(300);

      const sends = await stopSends();
      expect(sends).toEqual([
        { deviceIds: [first, second].sort(), payload: { v: 1, type: 'wake' } },
      ]);
    });

    it('devices with rings_urgent off are not woken by the stop', async () => {
      const me = await account();
      const ringing = await device(me, 'android', true);
      const quiet = await device(me, 'android', false);
      const { reminderId } = await ringingTask(me, [ringing, quiet]);

      await acknowledge(me, reminderId);

      const sends = await stopSends();
      expect(sends).toEqual([{ deviceIds: [ringing], payload: { v: 1, type: 'wake' } }]);
    });

    it('snooze and complete wake like acknowledge', async () => {
      const me = await account();
      const ringing = await device(me, 'android', true);
      const { task, reminderId } = await ringingTask(me, [ringing]);

      const snoozed = await app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/snooze`,
        headers: me.headers,
        payload: { reminderId, snoozeUntil: new Date(Date.now() + 10 * 60_000).toISOString() },
      });
      expect(snoozed.statusCode).toBe(200);
      expect(await stopSends(1)).toEqual([
        { deviceIds: [ringing], payload: { v: 1, type: 'wake' } },
      ]);

      const completed = await app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/complete`,
        headers: me.headers,
      });
      expect(completed.statusCode).toBeLessThan(300);
      const row = await app.db('reminders').where({ id: reminderId }).first('status');
      expect(row.status).toBe('completed');
      // One more stop for the new revision, to the same phone, nothing else.
      expect(await stopSends(2)).toEqual([
        { deviceIds: [ringing], payload: { v: 1, type: 'wake' } },
        { deviceIds: [ringing], payload: { v: 1, type: 'wake' } },
      ]);
    });

    it('ios and web devices are not woken', async () => {
      const me = await account();
      const android = await device(me, 'android', true);
      await device(me, 'ios', true);
      await device(me, 'web', true);
      const { reminderId } = await ringingTask(me, [android]);

      await acknowledge(me, reminderId);

      const sends = await stopSends();
      expect(sends).toEqual([{ deviceIds: [android], payload: { v: 1, type: 'wake' } }]);
    });
  },
);
