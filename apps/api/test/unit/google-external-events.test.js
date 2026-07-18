import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeGoogle, fakeGoogleEnv } from '../helpers/fakegoogle.js';
import { deriveExternalEvent } from '../../src/lib/external-events.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';

const KEY = 'c'.repeat(64);
const NOW = new Date('2030-06-01T12:00:00.000Z');

// ── What we keep, and why — decided without Google or a database (OPH-082) ──

describe('lib/external-events deriveExternalEvent (OPH-082, ADR-0008)', () => {
  const ctx = { timeZone: 'Europe/Istanbul', now: NOW };

  const meeting = (over = {}) => ({
    id: 'ev-ext-1',
    etag: '"m1"',
    updated: '2030-05-20T10:00:00.000Z',
    summary: 'Diş randevusu',
    location: 'Kadıköy',
    htmlLink: 'https://calendar.google.com/event?eid=abc',
    start: { dateTime: '2030-06-02T09:00:00.000Z' },
    end: { dateTime: '2030-06-02T10:00:00.000Z' },
    ...over,
  });

  it('stores a plain meeting with the fields a calendar view needs', () => {
    const out = deriveExternalEvent(meeting(), ctx);
    expect(out.action).toBe('store');
    expect(out.values).toMatchObject({
      summary: 'Diş randevusu',
      location: 'Kadıköy',
      starts_at: new Date('2030-06-02T09:00:00.000Z'),
      ends_at: new Date('2030-06-02T10:00:00.000Z'),
      is_all_day: false,
      is_busy: true,
      etag: '"m1"',
    });
  });

  it('never stores our own mirrored events — they are already tasks', () => {
    // Showing both would duplicate every mirrored block on the one screen this
    // whole feature exists for.
    const ours = meeting({
      summary: '[Task] Sunum hazırla',
      extendedProperties: { private: { alliswell_task_id: 'T'.padEnd(26, '0') } },
    });
    expect(deriveExternalEvent(ours, ctx)).toMatchObject({ action: 'skip', reason: 'ours' });
  });

  it('drops a cancelled event so it stops being shown', () => {
    expect(deriveExternalEvent(meeting({ status: 'cancelled' }), ctx)).toMatchObject({
      action: 'drop',
      reason: 'cancelled',
    });
  });

  it('keeps only what a calendar view could plausibly show', () => {
    // `timeMin` cannot be combined with a syncToken, so Google always hands us
    // the WHOLE history — the window is applied here instead.
    const ancient = meeting({
      start: { dateTime: '2020-01-01T09:00:00.000Z' },
      end: { dateTime: '2020-01-01T10:00:00.000Z' },
    });
    const faraway = meeting({
      start: { dateTime: '2040-01-01T09:00:00.000Z' },
      end: { dateTime: '2040-01-01T10:00:00.000Z' },
    });
    // `drop`, not `skip`: an event that MOVED out must stop being shown, and
    // this pass is the only notification we get.
    expect(deriveExternalEvent(ancient, ctx)).toMatchObject({
      action: 'drop',
      reason: 'out-of-window',
    });
    expect(deriveExternalEvent(faraway, ctx)).toMatchObject({ action: 'drop' });

    // Yesterday and next month are both inside it.
    expect(
      deriveExternalEvent(
        meeting({
          start: { dateTime: '2030-05-31T09:00:00.000Z' },
          end: { dateTime: '2030-05-31T10:00:00.000Z' },
        }),
        ctx,
      ).action,
    ).toBe('store');
  });

  it('maps an all-day event onto the user timezone and marks it not-busy', () => {
    const out = deriveExternalEvent(
      meeting({
        start: { date: '2030-06-05' },
        end: { date: '2030-06-06' }, // Google's end.date is EXCLUSIVE
        transparency: 'transparent',
      }),
      ctx,
    );
    expect(out.action).toBe('store');
    expect(out.values.starts_at.toISOString()).toBe('2030-06-04T21:00:00.000Z');
    expect(out.values.ends_at.toISOString()).toBe('2030-06-05T21:00:00.000Z');
    expect(out.values.is_all_day).toBe(true);
    expect(out.values.is_busy).toBe(false);
  });

  it('does not guess at events it cannot place', () => {
    for (const broken of [
      { start: undefined, end: undefined },
      {
        start: { dateTime: '2030-06-02T10:00:00.000Z' },
        end: { dateTime: '2030-06-02T09:00:00.000Z' },
      },
    ]) {
      expect(deriveExternalEvent(meeting(broken), ctx)).toMatchObject({
        action: 'skip',
        reason: 'unmappable-times',
      });
    }
  });

  it('tolerates an untitled event (Google allows them)', () => {
    const out = deriveExternalEvent(meeting({ summary: undefined }), ctx);
    expect(out.action).toBe('store');
    expect(out.values.summary).toBeNull();
  });
});

// ── The worker, against a Google that answers ──────────────────────────────

describe('external events end to end (OPH-082)', () => {
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

  const sync = async () => {
    app.calendarSync.enqueueSync(accountId);
    await app.calendarSync.idle();
    await app.mirror.idle();
  };

  const account = () => tables.calendar_accounts.find((a) => a.id === accountId);
  const stored = () => tables.calendar_external_events.filter((e) => e.deleted_at == null);

  /** A meeting the user already had in Google — nothing to do with AllisWell. */
  const seedMeeting = (id, over = {}) => {
    const soon = new Date(Date.now() + 86400_000);
    const event = {
      id,
      etag: `"${id}-1"`,
      updated: new Date().toISOString(),
      summary: 'Ekip toplantısı',
      start: { dateTime: soon.toISOString() },
      end: { dateTime: new Date(soon.getTime() + 3600_000).toISOString() },
      ...over,
    };
    google.state.eventsIn('primary').set(id, event);
    google.state.logChange('primary', event);
    return event;
  };

  it('pulls the user’s own meetings into the replica feed', async () => {
    seedMeeting('ev-meeting-1');

    await sync();

    expect(stored()).toHaveLength(1);
    expect(stored()[0]).toMatchObject({
      workspace_id: owner.workspace.id,
      summary: 'Ekip toplantısı',
      provider_event_id: 'ev-meeting-1',
      provider: 'google',
    });
    // …and it syncs to every device like any other entity (§6.2).
    const logged = tables.sync_revisions.filter((r) => r.entity_type === 'external_event');
    expect(logged).toHaveLength(1);
    expect(logged[0].operation).toBe('create');
  });

  it('runs BOTH feeds and keeps their cursors apart', async () => {
    seedMeeting('ev-meeting-2');
    await sync();

    // One list call per feed per pass — not one per event.
    expect(google.state.listCalls.mirror).toBe(1);
    expect(google.state.listCalls.external).toBe(1);
    expect(account().sync_token).toMatch(/^sync-/);
    expect(account().external_sync_token).toMatch(/^sync-/);
  });

  it('leaves our own mirrored events out of the calendar feed', async () => {
    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: {
        title: 'Aynalanan iş',
        calendarMirrorEnabled: true,
        dueAt: new Date(Date.now() + 86400_000).toISOString(),
      },
    });
    expect(created.statusCode).toBe(201);
    await app.mirror.idle();
    seedMeeting('ev-meeting-3');

    await sync();

    // The task's own event is in the calendar, but it is a TASK — showing it
    // here too would double every mirrored block.
    expect(stored()).toHaveLength(1);
    expect(stored()[0].provider_event_id).toBe('ev-meeting-3');
  });

  it('a meeting deleted in Google stops being shown (tombstone, not a hole)', async () => {
    seedMeeting('ev-meeting-4');
    await sync();
    expect(stored()).toHaveLength(1);
    const id = stored()[0].id;

    google.state.userDeletes('primary', 'ev-meeting-4');
    await sync();

    expect(stored()).toHaveLength(0);
    const row = tables.calendar_external_events.find((e) => e.id === id);
    expect(row.deleted_at).toBeInstanceOf(Date); // soft — pull turns it into a tombstone
    expect(
      tables.sync_revisions.filter(
        (r) => r.entity_type === 'external_event' && r.operation === 'delete',
      ),
    ).toHaveLength(1);
  });

  it('an unchanged meeting costs no revision on a resync', async () => {
    seedMeeting('ev-meeting-5');
    await sync();
    const revisionsAfterFirst = tables.sync_revisions.length;

    // A full resync replays the user's ENTIRE calendar through here. Burning a
    // revision per meeting would wake every device for nothing.
    google.state.expireSyncToken = true;
    await sync();

    expect(tables.sync_revisions).toHaveLength(revisionsAfterFirst);
    expect(stored()).toHaveLength(1);
  });

  it('serves the meetings to clients through sync/pull, and refuses writes', async () => {
    seedMeeting('ev-meeting-6');
    await sync();

    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=0`,
      headers: owner.headers,
    });
    expect(pull.statusCode).toBe(200);
    const change = pull.json().changes.find((c) => c.entityType === 'external_event');
    expect(change.data).toMatchObject({
      summary: 'Ekip toplantısı',
      isAllDay: false,
      isBusy: true,
    });
    // No provider ids leak to clients — they render it, they don't manage it.
    expect(change.data.providerEventId).toBeUndefined();

    // Read-only: editing someone else's meeting is not a thing v1 does. This
    // falls out of the push ENTITIES registry rather than a special case.
    const push = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId: 'C'.padEnd(26, '0'),
        workspaceId: owner.workspace.id,
        baseRevision: 0,
        mutations: [
          {
            clientMutationId: 'M'.padEnd(26, '0'),
            entityType: 'external_event',
            entityId: change.entityId,
            operation: 'update',
            localUpdatedAt: new Date().toISOString(),
            patch: { summary: 'değiştirmeyi dene' },
          },
        ],
      },
    });
    expect(push.statusCode).toBe(200);
    expect(push.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNSUPPORTED_ENTITY',
    });
  });
});
