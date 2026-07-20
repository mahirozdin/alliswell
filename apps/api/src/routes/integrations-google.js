import crypto from 'node:crypto';
import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { encryptSecret, decryptSecret } from '../lib/crypto.js';
import { decodeJwtPayload } from '../lib/google.js';
import { hashChannelToken } from '../lib/tokens.js';
import { googleClientFor, getFreshAccessToken } from '../db/calendar.js';
import { enqueueWorkspaceMirrorSweep } from '../queue/mirror-job.js';

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const STATE_TTL_SEC = 600;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const accountSchema = {
  type: 'object',
  required: ['id', 'provider', 'providerAccountId', 'status'],
  properties: {
    id: { type: 'string' },
    provider: { type: 'string' },
    providerAccountId: { type: 'string' },
    status: { type: 'string', enum: ['active', 'error', 'revoked', 'disconnected'] },
    defaultCalendarId: { type: ['string', 'null'] },
    lastSyncedAt: { type: ['string', 'null'] },
    lastError: { type: ['string', 'null'] },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

/** Tokens NEVER leave the server — the serializer has no code path for them. */
function serializeAccount(row) {
  return {
    id: row.id,
    provider: row.provider,
    providerAccountId: row.provider_account_id,
    status: row.status,
    defaultCalendarId: row.default_calendar_id ?? null,
    lastSyncedAt: toIso(row.last_synced_at),
    lastError: row.last_error ?? null,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

const closePage = (title, body) => `<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><title>${title}</title></head>
<body style="font-family: system-ui; display: grid; place-items: center; min-height: 90vh">
<div style="text-align: center"><h2>${title}</h2><p>${body}</p></div>
</body></html>`;

/**
 * Google Calendar integration (OPH-070/071, BLUEPRINT §7.2, ADR-0006).
 * Optional feature: without GOOGLE_CLIENT_ID/SECRET every route answers
 * `GOOGLE_NOT_CONFIGURED` instead of failing at boot.
 */
export default async function googleIntegrationRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  function ensureConfigured() {
    if (!app.config.google.clientId || !app.config.google.clientSecret) {
      throw coded(
        app.httpErrors.serviceUnavailable(
          'Google Calendar is not configured on this server (GOOGLE_CLIENT_ID/SECRET)',
        ),
        'GOOGLE_NOT_CONFIGURED',
      );
    }
  }

  /** Account visible only to the user who connected it, inside its workspace. */
  async function loadOwnAccount(request, accountId) {
    const row = await app
      .db('calendar_accounts')
      .where({ id: accountId, provider: 'google' })
      .whereNull('deleted_at')
      .first();
    if (!row) {
      throw coded(
        app.httpErrors.notFound('Calendar account not found'),
        'CALENDAR_ACCOUNT_NOT_FOUND',
      );
    }
    await app.requireWorkspaceMember(request, row.workspace_id);
    if (row.user_id !== request.user.id) {
      throw coded(
        app.httpErrors.forbidden('Only the connecting user manages this account'),
        'CALENDAR_ACCOUNT_FORBIDDEN',
      );
    }
    return row;
  }

  // ── Connect: hand the app a consent URL carrying a signed state ───────────

  app.post(
    '/workspaces/:workspaceId/integrations/google/connect',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: { type: 'object', properties: { authUrl: { type: 'string' } } },
          403: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      ensureConfigured();
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      // The callback arrives UNAUTHENTICATED from a browser redirect — the
      // state token carries the identity, signed and short-lived.
      const state = app.jwt.sign(
        { sub: request.user.id, purpose: 'google_oauth', wsId: workspaceId },
        { expiresIn: STATE_TTL_SEC },
      );
      return { authUrl: googleClientFor(app).buildAuthUrl(state) };
    },
  );

  // ── Callback: code → tokens (encrypted at rest) → account row ─────────────

  app.get(
    '/integrations/google/callback',
    {
      schema: {
        querystring: {
          type: 'object',
          properties: {
            code: { type: 'string' },
            state: { type: 'string' },
            error: { type: 'string' },
          },
        },
      },
    },
    async (request, reply) => {
      ensureConfigured();
      reply.type('text/html; charset=utf-8');

      if (request.query.error || !request.query.code || !request.query.state) {
        return reply
          .code(400)
          .send(closePage('Bağlantı tamamlanamadı', 'Google izni reddedildi veya eksik.'));
      }

      let state;
      try {
        state = app.jwt.verify(request.query.state);
        if (state.purpose !== 'google_oauth') throw new Error('wrong purpose');
      } catch {
        return reply
          .code(400)
          .send(closePage('Bağlantı tamamlanamadı', 'Geçersiz veya süresi dolmuş istek.'));
      }

      try {
        const tokens = await googleClientFor(app).exchangeCode(request.query.code);
        const identity = decodeJwtPayload(tokens.id_token);
        const providerAccountId = identity.email ?? identity.sub;
        const key = app.config.calendar.tokenKey;

        const values = {
          workspace_id: state.wsId,
          encrypted_access_token: encryptSecret(tokens.access_token, key),
          // Google re-issues the refresh token only with prompt=consent; keep
          // the old one if a re-connect response omits it.
          ...(tokens.refresh_token
            ? { encrypted_refresh_token: encryptSecret(tokens.refresh_token, key) }
            : {}),
          token_expires_at: new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000),
          status: 'active',
          last_error: null,
          deleted_at: null,
          updated_at: new Date(),
        };

        const existing = await app
          .db('calendar_accounts')
          .where({ user_id: state.sub, provider: 'google', provider_account_id: providerAccountId })
          .first('id');
        let accountId;
        if (existing) {
          accountId = existing.id;
          await app.db('calendar_accounts').where({ id: existing.id }).update(values);
        } else {
          accountId = newId();
          await app.db('calendar_accounts').insert({
            id: accountId,
            user_id: state.sub,
            provider: 'google',
            provider_account_id: providerAccountId,
            ...values,
          });
        }

        // Round 8 (OPH-160): "connected" must mean "data flows". The old flow
        // parked the account on a hidden second step — nothing synced until the
        // user separately picked a default calendar. Auto-select the primary
        // calendar when none is chosen yet, then start the first sync and the
        // push channel immediately (the PATCH branch below stays the way to
        // switch calendars later). Failure here is non-fatal: tokens are saved
        // and the manual picker still works.
        let calendarReady = false;
        try {
          const row = await app.db('calendar_accounts').where({ id: accountId }).first();
          if (row.default_calendar_id) {
            calendarReady = true; // reconnect: channel/cursor may be stale — resync below
          } else {
            const list = await googleClientFor(app).listCalendars(tokens.access_token);
            const primary = (list?.items ?? []).find((c) => c.primary);
            if (primary) {
              await app.db('calendar_accounts').where({ id: accountId }).update({
                default_calendar_id: primary.id,
                sync_token: null,
                sync_dirty_at: new Date(),
                updated_at: new Date(),
              });
              calendarReady = true;
            }
          }
          if (calendarReady) {
            // Mirror backfill + §7.2 steps 4-6, exactly like the PATCH branch.
            await enqueueWorkspaceMirrorSweep(app, row.workspace_id);
            app.calendarSync.enqueueSync(accountId);
            app.calendarSync.enqueueWatch(accountId);
          }
        } catch (err) {
          request.log.warn({ err: err.message }, 'google auto calendar select failed');
        }

        return reply.send(
          closePage(
            'Google Takvim bağlandı',
            calendarReady
              ? 'Takvimin bağlandı; etkinlikler arka planda senkronize ediliyor. ' +
                  'Bu pencereyi kapatıp AllisWell’e dönebilirsin. ' +
                  'İstersen Ayarlar’dan farklı bir takvim seçebilirsin.'
              : 'Bu pencereyi kapatıp AllisWell’e dönebilirsin. Sırada: varsayılan takvimi seç.',
          ),
        );
      } catch (err) {
        request.log.warn({ err: err.message }, 'google oauth exchange failed');
        return reply
          .code(400)
          .send(closePage('Bağlantı tamamlanamadı', 'Google ile anlaşma başarısız oldu.'));
      }
    },
  );

  // ── Status / calendars / default calendar / disconnect ────────────────────

  app.get(
    '/workspaces/:workspaceId/integrations/google',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              configured: { type: 'boolean' },
              items: { type: 'array', items: accountSchema },
            },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const rows = await app
        .db('calendar_accounts')
        .where({ workspace_id: workspaceId, provider: 'google' })
        .whereNull('deleted_at')
        .orderBy('created_at', 'asc')
        .select();
      return {
        configured: Boolean(app.config.google.clientId && app.config.google.clientSecret),
        items: rows.map(serializeAccount),
      };
    },
  );

  app.get(
    '/integrations/google/accounts/:accountId/calendars',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { accountId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              items: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    id: { type: 'string' },
                    summary: { type: 'string' },
                    primary: { type: 'boolean' },
                  },
                },
              },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
          502: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      ensureConfigured();
      const account = await loadOwnAccount(request, request.params.accountId);
      try {
        const accessToken = await getFreshAccessToken(app, account);
        const list = await googleClientFor(app).listCalendars(accessToken);
        return {
          items: (list?.items ?? []).map((c) => ({
            id: c.id,
            summary: c.summary ?? c.id,
            primary: Boolean(c.primary),
          })),
        };
      } catch (err) {
        if (err?.code === 'CALENDAR_ACCOUNT_REAUTH_REQUIRED') {
          throw coded(
            app.httpErrors.badGateway('Google rejected the stored credentials — reconnect'),
            'CALENDAR_ACCOUNT_REAUTH_REQUIRED',
          );
        }
        throw err;
      }
    },
  );

  app.patch(
    '/integrations/google/accounts/:accountId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { accountId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['defaultCalendarId'],
          properties: { defaultCalendarId: { type: 'string', minLength: 1, maxLength: 255 } },
        },
        response: {
          200: accountSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const account = await loadOwnAccount(request, request.params.accountId);
      const calendarChanged = account.default_calendar_id !== request.body.defaultCalendarId;
      await app
        .db('calendar_accounts')
        .where({ id: account.id })
        .update({
          default_calendar_id: request.body.defaultCalendarId,
          // A different calendar is a different event feed: the old cursor and
          // channel describe a calendar we no longer watch.
          ...(calendarChanged ? { sync_token: null, sync_dirty_at: new Date() } : {}),
          updated_at: new Date(),
        });
      // Backfill: mirror-enabled tasks flow into the newly chosen calendar.
      await enqueueWorkspaceMirrorSweep(app, account.workspace_id);
      if (calendarChanged) {
        // §7.2 steps 4-6: first full sync, then open the push channel.
        app.calendarSync.enqueueSync(account.id);
        app.calendarSync.enqueueWatch(account.id);
      }
      const fresh = await app.db('calendar_accounts').where({ id: account.id }).first();
      return serializeAccount(fresh);
    },
  );

  // ── Webhook: Google announces a change (OPH-074, §7.2 step 7) ─────────────

  await app.register(async (webhook) => {
    // Google's push carries NO body, and may arrive with a JSON content-type
    // anyway — the stock parser would 400 on the empty payload. This scope
    // accepts (and drains) whatever shows up; the headers are the message.
    webhook.removeAllContentTypeParsers();
    webhook.addContentTypeParser('*', (request, payload, done) => {
      payload.resume();
      done(null, null);
    });

    webhook.post(
      '/integrations/google/webhook',
      {
        schema: {
          response: { 200: { type: 'null' }, 401: errorResponseSchema },
        },
      },
      async (request, reply) => {
        const channelId = request.headers['x-goog-channel-id'];
        const state = request.headers['x-goog-resource-state'];
        if (!channelId) return reply.code(200).send();

        const account = await app
          .db('calendar_accounts')
          .where({ webhook_channel_id: channelId })
          .whereNull('deleted_at')
          .first();

        // Unknown or retired channel: 200 so Google stops retrying a message
        // nobody can act on. We cannot call channels.stop without the account
        // it belonged to, so the channel dies on its own expiry.
        if (!account?.webhook_channel_token_hash) {
          request.log.info({ channelId }, 'google webhook for an unknown channel');
          return reply.code(200).send();
        }

        // The channel token is the only thing separating Google from anyone
        // who guesses a channel id. Compare digests, in constant time.
        const presented = hashChannelToken(
          String(request.headers['x-goog-channel-token'] ?? ''),
          app.config.auth.refreshSecret,
        );
        const expected = account.webhook_channel_token_hash;
        if (
          presented.length !== expected.length ||
          !crypto.timingSafeEqual(Buffer.from(presented), Buffer.from(expected))
        ) {
          request.log.warn({ channelId }, 'google webhook with a bad channel token');
          throw coded(
            app.httpErrors.unauthorized('Invalid channel token'),
            'GOOGLE_WEBHOOK_INVALID_TOKEN',
          );
        }

        // `sync` is the handshake Google sends when a channel opens — an
        // acknowledgement, not a change.
        if (state === 'sync') return reply.code(200).send();

        // Mark dirty and hand off: the receiver must answer fast, and the
        // notification carries no payload worth reading (§8.3-style: ids only).
        await app
          .db('calendar_accounts')
          .where({ id: account.id })
          .update({ sync_dirty_at: new Date(), updated_at: new Date() });
        app.calendarSync.enqueueSync(account.id);
        return reply.code(200).send();
      },
    );
  });

  app.delete(
    '/integrations/google/accounts/:accountId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { accountId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const account = await loadOwnAccount(request, request.params.accountId);

      // Best-effort cleanup at Google, then drop the ciphertext — a
      // disconnected row keeps NO secrets. Event links stay (events remain in
      // the user's calendar; reconnecting re-links via extended properties).
      const key = app.config.calendar.tokenKey;
      const token = account.encrypted_refresh_token ?? account.encrypted_access_token;
      if (token && app.config.google.clientId) {
        const google = googleClientFor(app);
        // Close the push channel BEFORE revoking — afterwards the token is
        // dead and Google would keep notifying a channel nobody owns until it
        // expires (OPH-074).
        if (account.webhook_channel_id && account.webhook_resource_id) {
          try {
            const accessToken = await getFreshAccessToken(app, account);
            await google.stopChannel(accessToken, {
              channelId: account.webhook_channel_id,
              resourceId: account.webhook_resource_id,
            });
          } catch (err) {
            request.log.info({ err: err.message }, 'could not stop google channel on disconnect');
          }
        }
        await google.revokeToken(decryptSecret(token, key));
      }
      await app.db('calendar_accounts').where({ id: account.id }).update({
        status: 'disconnected',
        encrypted_access_token: null,
        encrypted_refresh_token: null,
        token_expires_at: null,
        sync_token: null,
        sync_dirty_at: null,
        webhook_channel_id: null,
        webhook_channel_token_hash: null,
        webhook_resource_id: null,
        webhook_expires_at: null,
        deleted_at: new Date(),
        updated_at: new Date(),
      });
      return reply.code(204).send();
    },
  );
}
