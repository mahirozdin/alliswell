import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';
import { backfillRingsUrgent } from '../../migrations/20261112120000_add_notification_device_rings_urgent.js';

/**
 * OPH-432 (#48) over real MySQL: which of an existing user's devices keeps
 * ringing urgent alarms once the per-device switch exists.
 *
 * `rings_urgent` defaults to 0, so without this backfill every existing
 * install would go silent on update (the "false-default suppression flag"
 * trap). The owner's rule is "the first-added device rings"; the guard keeps a
 * long-dead install from swallowing the alarm: the oldest non-web device seen
 * in the last 14 days, else the oldest web device seen in 14 days, else the
 * oldest of all — ties broken by id.
 *
 * The rows are seeded straight into MySQL with chosen `created_at` and
 * `last_seen_at`, because the API always stamps both with "now".
 */
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph432-${Date.now()}`;
const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date('2026-11-12T12:00:00.000Z');
const ago = (days) => new Date(NOW.getTime() - days * DAY);

describe.runIf(enabled)('integration: rings_urgent backfill (OPH-432)', () => {
  let app;
  const users = {};

  const register = async (key) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-${key}@example.com`, password: 'integration-pw-432' },
    });
    expect(res.statusCode).toBe(201);
    users[key] = res.json().user.id;
  };

  const seed = async (userKey, { platform, createdDaysAgo, seenDaysAgo, id = newId() }) => {
    await app.db('notification_devices').insert({
      id,
      user_id: users[userKey],
      platform,
      device_name: `${platform}-${createdDaysAgo}`,
      created_at: ago(createdDaysAgo),
      updated_at: ago(seenDaysAgo),
      last_seen_at: ago(seenDaysAgo),
    });
    return id;
  };

  const rows = (userKey) =>
    app
      .db('notification_devices')
      .where({ user_id: users[userKey] })
      .select('id', 'rings_urgent', 'rings_urgent_source');

  const ringing = async (userKey) =>
    (await rows(userKey)).filter((r) => Number(r.rings_urgent) === 1).map((r) => r.id);

  const ids = {};

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig() });
    await app.ready();
    for (const key of ['mixed', 'stale', 'webOnly', 'dormant', 'tie']) await register(key);

    // mixed: an old iPhone still in use, a newer Android, an older web tab.
    ids.mixedWeb = await seed('mixed', { platform: 'web', createdDaysAgo: 400, seenDaysAgo: 1 });
    ids.mixedIos = await seed('mixed', { platform: 'ios', createdDaysAgo: 300, seenDaysAgo: 2 });
    ids.mixedAndroid = await seed('mixed', {
      platform: 'android',
      createdDaysAgo: 30,
      seenDaysAgo: 0,
    });

    // stale: the first-added install has not been opened for 15 days.
    ids.staleOld = await seed('stale', { platform: 'ios', createdDaysAgo: 900, seenDaysAgo: 15 });
    ids.staleNew = await seed('stale', { platform: 'macos', createdDaysAgo: 10, seenDaysAgo: 13 });

    // webOnly: the only recent device is a web tab; the phone is long gone.
    ids.webOnlyPhone = await seed('webOnly', {
      platform: 'android',
      createdDaysAgo: 500,
      seenDaysAgo: 60,
    });
    ids.webOnlyOldTab = await seed('webOnly', {
      platform: 'web',
      createdDaysAgo: 200,
      seenDaysAgo: 20,
    });
    ids.webOnlyTab = await seed('webOnly', {
      platform: 'web',
      createdDaysAgo: 100,
      seenDaysAgo: 3,
    });
    ids.webOnlyNewTab = await seed('webOnly', {
      platform: 'web',
      createdDaysAgo: 5,
      seenDaysAgo: 1,
    });

    // dormant: nothing seen in 14 days at all.
    ids.dormantNewer = await seed('dormant', {
      platform: 'windows',
      createdDaysAgo: 50,
      seenDaysAgo: 40,
    });
    ids.dormantOldest = await seed('dormant', {
      platform: 'web',
      createdDaysAgo: 700,
      seenDaysAgo: 300,
    });
    ids.dormantMiddle = await seed('dormant', {
      platform: 'ios',
      createdDaysAgo: 200,
      seenDaysAgo: 100,
    });

    // tie: two recent phones created at the same millisecond — the lower id wins.
    const [low, high] = [newId(), newId()].sort();
    ids.tieHigh = await seed('tie', {
      platform: 'ios',
      createdDaysAgo: 20,
      seenDaysAgo: 1,
      id: high,
    });
    ids.tieLow = await seed('tie', {
      platform: 'android',
      createdDaysAgo: 20,
      seenDaysAgo: 1,
      id: low,
    });

    await backfillRingsUrgent(app.db, { now: NOW });
  });

  afterAll(async () => {
    if (!app) return;
    const found = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const userIds = found.map((u) => u.id);
    if (userIds.length > 0) {
      // notification_devices cascades from users; workspaces cascade the rest.
      await app.db('workspaces').whereIn('owner_id', userIds).delete();
      await app.db('users').whereIn('id', userIds).delete();
    }
    await app.close();
  });

  it('backfill rings the first-added device seen in the last 14 days and silences the rest', async () => {
    // The web tab is older, but a recent native device wins over web.
    expect(await ringing('mixed')).toEqual([ids.mixedIos]);
    expect(await ringing('tie')).toEqual([ids.tieLow]);
  });

  it('an old install not seen for 14 days does not keep the alarm', async () => {
    expect(await ringing('stale')).toEqual([ids.staleNew]);
  });

  it('a user whose only recent device is web keeps the web device ringing', async () => {
    // The 20-day-old tab is outside the window; of the recent tabs the first-added rings.
    expect(await ringing('webOnly')).toEqual([ids.webOnlyTab]);
  });

  it('a user with no recent device rings the oldest registered one', async () => {
    expect(await ringing('dormant')).toEqual([ids.dormantOldest]);
  });

  it('every backfilled row carries source backfill', async () => {
    for (const key of Object.keys(users)) {
      const all = await rows(key);
      expect(all.length).toBeGreaterThan(0);
      for (const row of all) expect(row.rings_urgent_source).toBe('backfill');
    }
    // Acceptance: after the backfill every user with devices has exactly one ringing row.
    const counts = await app
      .db('notification_devices')
      .select('user_id')
      .sum({ ringing: 'rings_urgent' })
      .groupBy('user_id');
    for (const c of counts) expect(Number(c.ringing)).toBe(1);
  });
});
