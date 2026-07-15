import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeGoogle, fakeGoogleEnv, FAKE_WEBHOOK_URL } from '../helpers/fakegoogle.js';
import { encryptSecret } from '../../src/lib/crypto.js';
import { newId } from '../../src/lib/ids.js';

const KEY = 'c'.repeat(64);
const WEBHOOK = '/api/v1/integrations/google/webhook';

/**
 * OPH-074 — the push channel and its receiver (BLUEPRINT §7.2 steps 6-7).
 * Google's notification carries no body: the headers ARE the message, which is
 * exactly what lets these tests inject one without a public address.
 */
describe('Google webhook receiver + channel lifecycle (OPH-074)', () => {
  let google;
  let app;
  let tables;
  let owner;
  let accountId;

  const build = async (env = {}) => {
    google = await startFakeGoogle();
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      CALENDAR_TOKEN_KEY: KEY,
      ...fakeGoogleEnv(google.url),
      ...env,
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
      sync_token: 'sync-0',
      sync_dirty_at: null,
      webhook_channel_id: null,
      webhook_channel_token_hash: null,
      webhook_resource_id: null,
      webhook_expires_at: null,
      status: 'active',
      deleted_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    });
  };

  afterEach(async () => {
    await app.close();
    await google.app.close();
  });

  const account = () => tables.calendar_accounts.find((a) => a.id === accountId);

  /** Opens the channel the way the sweep would, and hands back what Google
   *  kept — including the raw token, which our own database never stores. */
  const openChannel = async () => {
    app.calendarSync.enqueueWatch(accountId);
    await app.calendarSync.idle();
    return google.state.channels.get(account().webhook_channel_id);
  };

  const notify = (headers) => app.inject({ method: 'POST', url: WEBHOOK, headers });

  describe('with a public webhook address', () => {
    beforeEach(() => build({ GOOGLE_WEBHOOK_URL: FAKE_WEBHOOK_URL }));

    it('opens a channel and keeps only a digest of its token', async () => {
      const channel = await openChannel();

      expect(channel.address).toBe(FAKE_WEBHOOK_URL);
      expect(channel.calendarId).toBe('primary');
      expect(account()).toMatchObject({
        webhook_channel_id: channel.id,
        webhook_resource_id: channel.resourceId,
      });
      // Renewal keys off Google's answer, not off what we asked for.
      expect(account().webhook_expires_at.getTime()).toBeGreaterThan(Date.now());

      // The raw token went to Google and nowhere else (SECURITY.md posture).
      const stored = JSON.stringify(account());
      expect(stored).not.toContain(channel.token);
      expect(account().webhook_channel_token_hash).toMatch(/^[0-9a-f]{64}$/);
    });

    it('marks the account dirty and queues a sync for a real notification', async () => {
      const channel = await openChannel();

      const res = await notify({
        'x-goog-channel-id': channel.id,
        'x-goog-channel-token': channel.token,
        'x-goog-resource-id': channel.resourceId,
        'x-goog-resource-state': 'exists',
        'x-goog-message-number': '2',
      });

      expect(res.statusCode).toBe(200);
      expect(account().sync_dirty_at).toBeInstanceOf(Date);
    });

    it('acknowledges the opening handshake without calling it a change', async () => {
      const channel = await openChannel();

      // `sync` is Google saying "channel is live", not "something happened".
      const res = await notify({
        'x-goog-channel-id': channel.id,
        'x-goog-channel-token': channel.token,
        'x-goog-resource-state': 'sync',
        'x-goog-message-number': '1',
      });

      expect(res.statusCode).toBe(200);
      expect(account().sync_dirty_at).toBeNull();
    });

    it('rejects a forged token and refuses to be poked by it', async () => {
      const channel = await openChannel();

      const res = await notify({
        'x-goog-channel-id': channel.id,
        'x-goog-channel-token': 'guessed-it',
        'x-goog-resource-state': 'exists',
      });

      expect(res.statusCode).toBe(401);
      expect(res.json().code).toBe('GOOGLE_WEBHOOK_INVALID_TOKEN');
      expect(account().sync_dirty_at).toBeNull();

      // A missing token is no better than a wrong one.
      const bare = await notify({
        'x-goog-channel-id': channel.id,
        'x-goog-resource-state': 'exists',
      });
      expect(bare.statusCode).toBe(401);
      expect(account().sync_dirty_at).toBeNull();
    });

    it('absorbs notifications for channels it no longer knows', async () => {
      // 200, not an error: Google must stop retrying a message nobody can act
      // on, and a retry would not make the channel exist.
      const unknown = await notify({
        'x-goog-channel-id': 'e0f7f0b2-0000-4000-8000-000000000000',
        'x-goog-channel-token': 'whatever',
        'x-goog-resource-state': 'exists',
      });
      expect(unknown.statusCode).toBe(200);

      const headerless = await notify({ 'x-goog-resource-state': 'exists' });
      expect(headerless.statusCode).toBe(200);
      expect(account().sync_dirty_at).toBeNull();
    });

    it('tolerates the empty body Google actually sends', async () => {
      const channel = await openChannel();
      const headers = {
        'x-goog-channel-id': channel.id,
        'x-goog-channel-token': channel.token,
        'x-goog-resource-state': 'exists',
      };

      // No body at all, and an empty body under a JSON content-type: the
      // stock parser rejects the latter, which is why the route has its own.
      expect((await notify(headers)).statusCode).toBe(200);
      const withType = await app.inject({
        method: 'POST',
        url: WEBHOOK,
        headers: { ...headers, 'content-type': 'application/json' },
        payload: '',
      });
      expect(withType.statusCode).toBe(200);
    });

    it('renews an expiring channel without ever leaving a gap', async () => {
      const first = await openChannel();
      // Google is about to drop it (channels are never renewed automatically).
      account().webhook_expires_at = new Date(Date.now() + 60_000);

      await app.calendarSync.sweep();
      await app.calendarSync.idle();

      const second = google.state.channels.get(account().webhook_channel_id);
      expect(second.id).not.toBe(first.id);
      // The replacement is live BEFORE the old one is retired, so no change
      // can slip through in between.
      expect(google.state.stopped).toEqual([first.id]);
      expect(google.state.channels.has(first.id)).toBe(false);
      expect(account().webhook_channel_token_hash).toMatch(/^[0-9a-f]{64}$/);
    });

    it('leaves a healthy channel alone and syncs only what is dirty', async () => {
      await openChannel();
      const watchCalls = google.state.watchCalls;

      await app.calendarSync.sweep();
      await app.calendarSync.idle();
      expect(google.state.watchCalls).toBe(watchCalls); // not due for renewal

      // A webhook that arrived while the worker was down is picked up here.
      account().sync_dirty_at = new Date();
      await app.calendarSync.sweep();
      await app.calendarSync.idle();
      expect(account().sync_dirty_at).toBeNull();
      expect(account().last_synced_at).toBeInstanceOf(Date);
    });

    it('stops the channel when the account is disconnected', async () => {
      const channel = await openChannel();

      const res = await app.inject({
        method: 'DELETE',
        url: `/api/v1/integrations/google/accounts/${accountId}`,
        headers: owner.headers,
      });

      expect(res.statusCode).toBe(204);
      expect(google.state.stopped).toEqual([channel.id]);
      expect(account()).toMatchObject({
        webhook_channel_id: null,
        webhook_channel_token_hash: null,
        sync_token: null,
        sync_dirty_at: null,
      });
    });
  });

  describe('without a public webhook address', () => {
    beforeEach(() => build());

    it('never opens a channel and polls instead', async () => {
      // Self-hosters on localhost or behind NAT cannot receive a push. Inbound
      // sync still has to work for them, so the sweep IS their notification.
      app.calendarSync.enqueueWatch(accountId);
      await app.calendarSync.idle();
      expect(google.state.watchCalls).toBe(0);
      expect(account().webhook_channel_id).toBeNull();

      await app.calendarSync.sweep();
      await app.calendarSync.idle();
      expect(account().last_synced_at).toBeInstanceOf(Date);
    });
  });

  describe('configuration', () => {
    it('refuses a webhook address Google would reject', () => {
      expect(() =>
        loadConfig({ NODE_ENV: 'test', GOOGLE_WEBHOOK_URL: 'http://localhost:3000/hook' }),
      ).toThrow(/https/);
    });
  });
});
