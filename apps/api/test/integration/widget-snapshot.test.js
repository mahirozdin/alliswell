import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, it, expect, beforeAll, afterAll, afterEach, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis with migrations applied.
const enabled = process.env.INTEGRATION === '1';

const prefix = `oph460-${Date.now()}`;
const PASSWORD = 'integration-pw-460';

/**
 * OPH-460 (#50, WIDGETS §3.2) — `GET /widget/snapshot`, the read the iOS
 * widget extension makes with its `aww_` token while the app is swiped away.
 *
 * The rows come from the shared grouping fixture
 * (`apps/app/test/fixtures/widget_grouping_cases.json`, written by the Dart
 * suite): a case is seeded into a real workspace, the clock is set to the
 * case's `now`, and the route's `days` must equal the fixture's
 * `expected.days` — the same body Dart builds for the same data.
 */

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../app/test/fixtures/widget_grouping_cases.json',
);
const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));
const caseNamed = (start) => {
  const found = fixture.cases.find((c) => c.name.startsWith(start));
  if (!found) throw new Error(`fixture case "${start}" is missing`);
  return found;
};

const W1 = 'W1000000000000000000000000';
const W2 = 'W2000000000000000000000000';
const W3 = 'W3000000000000000000000000';

describe.runIf(enabled)('integration: widget snapshot (OPH-460)', () => {
  let app;
  let seq = 0;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '500' }),
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    if (app) app.ee.widgetScopeResolvers.length = 0;
  });

  afterAll(async () => {
    if (!app) return;
    await clearFixtureRows();
    const users = await app.db('users').where('email', 'like', `${prefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspace_members').whereIn('user_id', ids).delete();
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  const bearer = (token) => ({ authorization: `Bearer ${token}` });

  /** A fresh account with its device registered and a widget token minted for it. */
  const account = async () => {
    seq += 1;
    const deviceId = newId();
    const email = `${prefix}-${seq}@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: PASSWORD, deviceId },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    const headers = bearer(body.tokens.accessToken);
    const put = await app.inject({
      method: 'PUT',
      url: `/api/v1/notification-devices/${deviceId}`,
      headers,
      payload: { platform: 'ios' },
    });
    expect([200, 201]).toContain(put.statusCode);
    const minted = await app.inject({
      method: 'POST',
      url: '/api/v1/widget-tokens',
      headers,
      payload: { deviceId },
    });
    expect(minted.statusCode).toBe(201);
    return {
      id: body.user.id,
      workspaceId: body.workspace.id,
      headers,
      widget: bearer(minted.json().token),
    };
  };

  /** Every row id the fixture can seed — removed before a seed and after the suite. */
  const fixtureIds = () => {
    const ids = { tasks: new Set(), projects: new Set(), events: new Set() };
    for (const c of fixture.cases) {
      for (const t of c.tasks) ids.tasks.add(t.id);
      for (const p of c.projects) ids.projects.add(p.id);
      for (const e of c.events ?? []) ids.events.add(e.id);
    }
    return ids;
  };

  async function clearFixtureRows() {
    const ids = fixtureIds();
    await app
      .db('tasks')
      .whereIn('id', [...ids.tasks])
      .delete();
    await app
      .db('projects')
      .whereIn('id', [...ids.projects])
      .delete();
    await app
      .db('calendar_external_events')
      .whereIn('id', [...ids.events])
      .delete();
  }

  const at = (value) => (value ? new Date(value) : null);

  /**
   * Seeds a fixture case: its W1 rows into the account's workspace, any other
   * fixture workspace into the one `workspaces` maps it to. Fixture users are
   * not real users, so `created_by` is the account itself.
   */
  async function seedCase(testCase, user, workspaces = {}) {
    await clearFixtureRows();
    const ws = (fixtureWs) => {
      if (fixtureWs === W1) return user.workspaceId;
      if (!workspaces[fixtureWs]) throw new Error(`no workspace for ${fixtureWs}`);
      return workspaces[fixtureWs];
    };
    for (const p of testCase.projects) {
      await app.db('projects').insert({
        id: p.id,
        workspace_id: ws(p.workspaceId),
        name: p.name,
        color_rgb: p.colorRgb,
        status: p.status,
        sort_order: p.sortOrder ?? 0,
      });
    }
    for (const t of testCase.tasks) {
      await app.db('tasks').insert({
        id: t.id,
        workspace_id: ws(t.workspaceId),
        project_id: t.projectId ?? null,
        title: t.title,
        status: t.status,
        priority: t.priority,
        color_rgb: t.colorRgb ?? null,
        start_at: at(t.startAt),
        due_at: at(t.dueAt),
        completed_at: at(t.completedAt),
        sort_order: t.sortOrder ?? 0,
        created_by: user.id,
      });
    }
    const events = testCase.events ?? [];
    if (events.length > 0) {
      const accountId = newId();
      await app.db('calendar_accounts').insert({
        id: accountId,
        user_id: user.id,
        workspace_id: user.workspaceId,
        provider: 'google',
        provider_account_id: `${prefix}-${accountId}`,
      });
      for (const e of events) {
        await app.db('calendar_external_events').insert({
          id: e.id,
          workspace_id: ws(e.workspaceId),
          calendar_account_id: accountId,
          provider: 'google',
          provider_calendar_id: 'primary',
          provider_event_id: e.id,
          summary: e.summary ?? null,
          starts_at: at(e.startsAt),
          ends_at: at(e.endsAt),
          is_all_day: Boolean(e.allDay),
        });
      }
    }
  }

  const freezeAt = (iso) => vi.useFakeTimers({ toFake: ['Date'], now: new Date(iso) });

  const snapshot = (user, query, headers = {}) =>
    app.inject({
      method: 'GET',
      url: `/api/v1/widget/snapshot?${new URLSearchParams(query).toString()}`,
      headers: { ...user.widget, ...headers },
    });

  it('returns days[0..2] each with openToday, next and project views', async () => {
    const me = await account();
    const testCase = caseNamed('buckets, the local day edges');
    await seedCase(testCase, me);
    freezeAt(testCase.now);

    const res = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: me.workspaceId,
      private: '0',
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.headers.etag).toMatch(/^"[0-9a-f]{32,64}"$/);
    const body = res.json();
    expect(body).toMatchObject({ v: 1, tz: testCase.tz, generatedAt: testCase.now });
    expect(body.days.map((d) => d.date)).toEqual(['2026-11-12', '2026-11-13', '2026-11-14']);
    for (const day of body.days) {
      expect(typeof day.openToday).toBe('number');
      expect(day.views).toBeTypeOf('object');
    }
    expect(body.days[0].next).toBeDefined();
    expect(Object.keys(body.days[0].views)).toEqual(['P1000000000000000000000000']);
    // Dart's body for the same rows, field for field.
    expect(body.days).toEqual(testCase.expected.days);

    // `days` narrows the answer; it never reshapes a day.
    const one = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: me.workspaceId,
      private: '0',
      days: '1',
    });
    expect(one.json().days).toEqual(testCase.expected.days.slice(0, 1));
  });

  it('nothing but a live widget token opens it', async () => {
    const me = await account();
    const query = `tz=Europe%2FIstanbul&workspaceIds=${me.workspaceId}`;
    const url = `/api/v1/widget/snapshot?${query}`;

    const none = await app.inject({ method: 'GET', url });
    expect(none.statusCode).toBe(401);
    expect(none.json().code).toBe('AUTH_WIDGET_TOKEN_INVALID');

    const session = await app.inject({ method: 'GET', url, headers: me.headers });
    expect(session.statusCode).toBe(401);
    expect(session.json().code).toBe('AUTH_WIDGET_TOKEN_INVALID');

    const keyRes = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${me.workspaceId}/api-keys`,
      headers: me.headers,
      payload: { name: 'widget probe' },
    });
    expect(keyRes.statusCode).toBe(201);
    const withKey = await app.inject({ method: 'GET', url, headers: bearer(keyRes.json().key) });
    expect(withKey.statusCode).toBe(401);
    expect(withKey.json().code).toBe('AUTH_WIDGET_TOKEN_INVALID');

    const ok = await app.inject({ method: 'GET', url, headers: me.widget });
    expect(ok.statusCode).toBe(200);
  });

  it('buckets follow the client tz across a day boundary', async () => {
    const me = await account();
    const testCase = caseNamed('the local day, not the UTC one');
    await seedCase(testCase, me);
    freezeAt(testCase.now); // 22:30 UTC = 01:30 the next day in Istanbul

    const local = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: me.workspaceId,
      private: '0',
    });
    expect(local.statusCode).toBe(200);
    expect(local.json().days).toEqual(testCase.expected.days);
    expect(local.json().days[0].date).toBe('2026-11-13');

    const utc = await snapshot(me, { tz: 'UTC', workspaceIds: me.workspaceId, private: '0' });
    expect(utc.statusCode).toBe(200);
    expect(utc.json().days[0].date).toBe('2026-11-12');
    expect(utc.json().days).not.toEqual(local.json().days);
    expect(utc.headers.etag).not.toBe(local.headers.etag);
  });

  it('private=1 returns no title or summary field anywhere in the body', async () => {
    const me = await account();
    const outside = await account();
    const testCase = caseNamed('the calendar in a one-workspace scope');
    await seedCase(testCase, me, { [W2]: outside.workspaceId });
    freezeAt(testCase.now);

    // Private is the default (fail-closed) and the explicit 1 alike.
    for (const query of [
      { tz: testCase.tz, workspaceIds: me.workspaceId },
      { tz: testCase.tz, workspaceIds: me.workspaceId, private: '1' },
    ]) {
      const res = await snapshot(me, query);
      expect(res.statusCode).toBe(200);
      const raw = res.payload;
      expect(raw).not.toMatch(/"title"/);
      expect(raw).not.toMatch(/"summary"/);
      for (const row of [...testCase.tasks, ...testCase.events]) {
        if (row.title) expect(raw).not.toContain(row.title);
        if (row.summary) expect(raw).not.toContain(row.summary);
      }
      // The same rows and numbers as the titled body, titles stripped.
      const strip = (value) =>
        JSON.parse(JSON.stringify(value, (key, v) => (key === 'title' ? undefined : v)));
      expect(res.json().days).toEqual(strip(testCase.expected.days));
    }
  });

  it('a workspace the user is not a member of is 403', async () => {
    const me = await account();
    const other = await account();
    const res = await snapshot(me, {
      tz: 'Europe/Istanbul',
      workspaceIds: `${me.workspaceId},${other.workspaceId}`,
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('AUTH_WORKSPACE_FORBIDDEN');

    const unknown = await snapshot(me, { tz: 'Europe/Istanbul', workspaceIds: newId() });
    expect(unknown.statusCode).toBe(403);
    expect(unknown.json().code).toBe('AUTH_WORKSPACE_FORBIDDEN');
  });

  it('events appear only for a single-workspace scope', async () => {
    const me = await account();
    const other = await account();
    // `me` joins `other`'s workspace: a two-workspace scope it may read.
    await app.db('workspace_members').insert({
      id: newId(),
      workspace_id: other.workspaceId,
      user_id: me.id,
      role: 'member',
    });
    const outside = await account();
    const testCase = caseNamed('the calendar in a one-workspace scope');
    await seedCase(testCase, me, { [W2]: outside.workspaceId });
    freezeAt(testCase.now);

    const isEvent = (item) => item.kind === 'event';
    const eventsIn = (body) =>
      body.days.flatMap((d) => d.buckets.flatMap((b) => b.items)).filter(isEvent);

    const single = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: me.workspaceId,
      private: '0',
    });
    expect(single.statusCode).toBe(200);
    expect(eventsIn(single.json()).length).toBeGreaterThan(0);
    expect(single.json().days).toEqual(testCase.expected.days);

    const two = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: `${me.workspaceId},${other.workspaceId}`,
      private: '0',
    });
    expect(two.statusCode).toBe(200);
    expect(eventsIn(two.json())).toEqual([]);

    const mine = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: me.workspaceId,
      mine: '1',
      private: '0',
    });
    expect(mine.statusCode).toBe(200);
    expect(eventsIn(mine.json())).toEqual([]);
  });

  it("mine selects the user's own work, with the extension's assignments when it has them", async () => {
    const me = await account();
    const other = await account();
    await app.db('workspace_members').insert({
      id: newId(),
      workspace_id: other.workspaceId,
      user_id: me.id,
      role: 'member',
    });
    const outside = await account();
    const testCase = caseNamed('mine across two workspaces');
    await seedCase(testCase, me, { [W2]: other.workspaceId, [W3]: outside.workspaceId });
    // The fixture's people are not real users: `created_by` follows the
    // fixture's own createdBy, and its assignments come from a resolver.
    const fixtureMe = testCase.scope.mineFor;
    for (const t of testCase.tasks) {
      await app
        .db('tasks')
        .where({ id: t.id })
        .update({ created_by: t.createdBy === fixtureMe ? me.id : other.id });
    }
    app.ee.widgetScopeResolvers.push(async (_db, { userId, tasks }) => {
      expect(userId).toBe(me.id);
      const out = new Map();
      for (const task of tasks) {
        const row = testCase.tasks.find((t) => t.id === task.id);
        const assignees = (row?.assignees ?? []).map((u) => (u === fixtureMe ? me.id : other.id));
        out.set(task.id, { assignees, isRequestWork: false });
      }
      return out;
    });
    freezeAt(testCase.now);

    const res = await snapshot(me, {
      tz: testCase.tz,
      workspaceIds: `${me.workspaceId},${other.workspaceId}`,
      mine: '1',
      private: String(testCase.private ? 1 : 0),
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().days).toEqual(testCase.expected.days);
  });

  it('ETag round-trip answers 304', async () => {
    const me = await account();
    const testCase = caseNamed('buckets, the local day edges');
    await seedCase(testCase, me);
    freezeAt(testCase.now);
    const query = { tz: testCase.tz, workspaceIds: me.workspaceId, private: '0' };

    const first = await snapshot(me, query);
    expect(first.statusCode).toBe(200);
    const etag = first.headers.etag;

    // A later generatedAt alone does not change the tag.
    vi.setSystemTime(new Date(new Date(testCase.now).getTime() + 1000));
    const again = await snapshot(me, query, { 'if-none-match': etag });
    expect(again.statusCode).toBe(304);
    expect(again.payload).toBe('');
    expect(again.headers.etag).toBe(etag);
    expect(again.headers['cache-control']).toBe('no-store');

    // Another query is another tag, even over the same rows.
    const privateOne = await snapshot(me, { ...query, private: '1' }, { 'if-none-match': etag });
    expect(privateOne.statusCode).toBe(200);
    expect(privateOne.headers.etag).not.toBe(etag);

    // A changed row is a new body and a new tag.
    await app.db('tasks').where({ id: testCase.tasks[0].id }).update({ title: 'Renamed' });
    const changed = await snapshot(me, query, { 'if-none-match': etag });
    expect(changed.statusCode).toBe(200);
    expect(changed.headers.etag).not.toBe(etag);
  });

  it('invalid tz is 400', async () => {
    const me = await account();
    const res = await snapshot(me, { tz: 'Mars/Olympus_Mons', workspaceIds: me.workspaceId });
    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('WIDGET_INVALID_TZ');

    const missing = await snapshot(me, { workspaceIds: me.workspaceId });
    expect(missing.statusCode).toBe(400);
    const badDays = await snapshot(me, { tz: 'UTC', workspaceIds: me.workspaceId, days: '4' });
    expect(badDays.statusCode).toBe(400);
    const badIds = await snapshot(me, { tz: 'UTC', workspaceIds: 'not-a-ulid' });
    expect(badIds.statusCode).toBe(400);
  });
});
