import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { encryptSecret } from '../lib/crypto.js';
import { createCaldavClient } from '../lib/caldav/client.js';
import { discover, listCalendarsAt } from '../lib/caldav/discovery.js';
import {
  caldavClientForAccount,
  caldavHost,
  caldavIdentity,
  caldavUsername,
} from '../db/calendar.js';
import { enqueueWorkspaceMirrorSweep } from '../queue/mirror-job.js';
import { recordSyncWrites } from '../db/sync.js';

/**
 * iCloud / CalDAV calendar (OPH-380, docs/CALDAV.md, ADR-0059).
 *
 * The connect endpoint takes a PASSWORD — an iCloud app-specific password or a
 * CalDAV server's app password — and keeps it, encrypted, so the server can
 * mirror while the user's devices are off. CALDAV.md §3 is binding here:
 *
 * - verify before storing: discovery must succeed before a row is written;
 * - never returned: the serializer has no path to the ciphertext;
 * - session only: a leaked API key must not be able to plant a credential or
 *   open a standing outbound channel (API.md §1, rule 12);
 * - off by default: `CALDAV_ENABLED` — status and disconnect keep working
 *   while it is off, so an admin switching it off never strands a password.
 *
 * Errors from the CalDAV server never answer 401 (the app would read that as
 * its OWN session expiring): a rejected password is 422 `CALDAV_AUTH_FAILED`.
 */

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const PROVIDER = 'apple_caldav';
/** `default_calendar_id` is varchar(255) — a longer path is refused, not cut. */
const MAX_CALENDAR_PATH = 255;

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
  required: ['id', 'provider', 'server', 'serverHost', 'username', 'status'],
  properties: {
    id: { type: 'string' },
    provider: { type: 'string', enum: ['caldav'] },
    server: { type: 'string', enum: ['icloud', 'generic'] },
    serverHost: { type: 'string' },
    serverUrl: { type: ['string', 'null'] },
    username: { type: 'string' },
    status: { type: 'string', enum: ['active', 'error', 'revoked', 'disconnected'] },
    calendarUrl: { type: ['string', 'null'] },
    calendarName: { type: ['string', 'null'] },
    lastSyncedAt: { type: ['string', 'null'] },
    lastError: { type: ['string', 'null'] },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

const calendarSchema = {
  type: 'object',
  required: ['url', 'name'],
  properties: {
    url: { type: 'string' },
    name: { type: 'string' },
    color: { type: ['string', 'null'] },
  },
};

/**
 * The password NEVER leaves the server — this function has no code path to
 * `encrypted_app_password`, and the response schema would strip it anyway.
 */
export function serializeCaldavAccount(row) {
  return {
    id: row.id,
    provider: 'caldav',
    server: row.caldav_kind === 'icloud' ? 'icloud' : 'generic',
    serverHost: caldavHost(row),
    // What the user typed (generic) — not a secret, and what a reconnect form
    // is prefilled with. iCloud's is the fixed iCloud address.
    serverUrl: row.caldav_kind === 'icloud' ? null : (row.caldav_server_url ?? null),
    username: caldavUsername(row),
    status: row.status,
    calendarUrl: row.default_calendar_id ?? null,
    calendarName: row.calendar_display_name ?? null,
    lastSyncedAt: toIso(row.last_synced_at),
    lastError: row.last_error ?? null,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/** CaldavError codes → the answer the app shows next to the form. */
const CONNECT_ERRORS = {
  CALDAV_AUTH_FAILED: ['unprocessableEntity', 'The server rejected the user name or password'],
  CALDAV_NOT_CALDAV: ['unprocessableEntity', 'That address does not answer like a CalDAV server'],
  CALDAV_NO_CALENDARS: ['unprocessableEntity', 'The account has no calendar that can hold events'],
  CALDAV_BLOCKED_ADDRESS: [
    'unprocessableEntity',
    'That address is not allowed on this server (https, public hosts only)',
  ],
  CALDAV_REDIRECT_OFF_HOST: [
    'unprocessableEntity',
    'The server sent us to another host; the password is only sent to the host you entered',
  ],
  CALDAV_URL_TOO_LONG: ['unprocessableEntity', 'The calendar address is too long'],
  CALDAV_UNREACHABLE: ['badGateway', 'The CalDAV server could not be reached'],
  CALDAV_RESPONSE_TOO_LARGE: ['badGateway', 'The CalDAV server answered with too much data'],
  CALDAV_REQUEST_FAILED: ['badGateway', 'The CalDAV server refused the request'],
};

/**
 * Apple refuses the Apple Account password itself; only an app-specific one
 * works. Same code, a message that says so (the app shows its own hint).
 */
const ICLOUD_AUTH_FAILED =
  'Apple did not accept that password. Use an app-specific password made at ' +
  'account.apple.com (Sign-In and Security → App-Specific Passwords); your ' +
  'Apple Account password does not work here';

/** iCloud by choice, or a "generic" address that is iCloud's CalDAV host. */
export function isIcloudServer(server, serverUrl) {
  if (server === 'icloud') return true;
  try {
    return /(^|\.)icloud\.com$/i.test(new URL(serverUrl).hostname);
  } catch {
    return false;
  }
}

export default async function caldavIntegrationRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  function ensureEnabled() {
    if (!app.config.caldav.enabled) {
      throw coded(
        app.httpErrors.serviceUnavailable(
          'The CalDAV connector is not enabled on this server (CALDAV_ENABLED)',
        ),
        'CALDAV_NOT_ENABLED',
      );
    }
  }

  function translate(err, { icloud = false } = {}) {
    const mapped = CONNECT_ERRORS[err?.code];
    if (!mapped) return err;
    const [kind, message] = mapped;
    // An API/MCP caller sees no app hint: the iCloud refusal names its cure.
    const text = icloud && err.code === 'CALDAV_AUTH_FAILED' ? ICLOUD_AUTH_FAILED : message;
    return coded(app.httpErrors[kind](text), err.code);
  }

  /** Account visible only to the user who connected it, inside its workspace. */
  async function loadOwnAccount(request, accountId) {
    const row = await app
      .db('calendar_accounts')
      .where({ id: accountId, provider: PROVIDER })
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

  /** The calendars of a stored account, re-discovering when the home moved. */
  async function calendarsOf(account) {
    let client;
    try {
      client = caldavClientForAccount(app, account);
    } catch (err) {
      if (err?.code === 'CALENDAR_ACCOUNT_REAUTH_REQUIRED') throw reauthError();
      throw err;
    }
    try {
      try {
        return await listCalendarsAt(client, account.calendar_home_url);
      } catch (err) {
        if (err?.code !== 'CALDAV_REQUEST_FAILED') throw err;
        // iCloud moved the account to another partition (CALDAV.md §4.1):
        // discover again and remember where the home is now.
        const found = await discover(client, {
          startUrl: account.caldav_server_url ?? app.config.caldav.icloudUrl,
        });
        await app.db('calendar_accounts').where({ id: account.id }).update({
          principal_url: found.principalUrl,
          calendar_home_url: found.homeUrl,
          updated_at: new Date(),
        });
        return found.calendars;
      }
    } catch (err) {
      if (err?.code === 'CALDAV_AUTH_FAILED') {
        await app.db('calendar_accounts').where({ id: account.id }).update({
          status: 'error',
          last_error: 'password rejected — reconnect the calendar',
          updated_at: new Date(),
        });
        throw reauthError();
      }
      throw translate(err);
    }
  }

  const reauthError = () =>
    coded(
      app.httpErrors.badGateway('The CalDAV server rejected the stored password — reconnect'),
      'CALENDAR_ACCOUNT_REAUTH_REQUIRED',
    );

  // ── Status ────────────────────────────────────────────────────────────────

  app.get(
    '/workspaces/:workspaceId/integrations/caldav',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            required: ['enabled', 'items'],
            properties: {
              enabled: { type: 'boolean' },
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
        .where({ workspace_id: workspaceId, provider: PROVIDER, user_id: request.user.id })
        .whereNull('deleted_at')
        .orderBy('created_at', 'asc')
        .select();
      return { enabled: app.config.caldav.enabled, items: rows.map(serializeCaldavAccount) };
    },
  );

  // ── Connect: verify, then store ───────────────────────────────────────────

  app.post(
    '/workspaces/:workspaceId/integrations/caldav',
    {
      onRequest: [app.authenticate],
      // A leaked API key must not be able to plant a calendar password or
      // open a standing outbound channel (API.md §1).
      preHandler: [app.rejectApiKeys],
      config: { rateLimit: { max: app.config.rateLimitAuthMax, timeWindow: '1 minute' } },
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['server', 'username', 'password'],
          properties: {
            server: { type: 'string', enum: ['icloud', 'generic'] },
            url: { type: 'string', minLength: 1, maxLength: 500 },
            username: { type: 'string', minLength: 1, maxLength: 255 },
            password: { type: 'string', minLength: 1, maxLength: 255 },
          },
        },
        response: {
          201: {
            type: 'object',
            required: ['account', 'calendars'],
            properties: {
              account: accountSchema,
              calendars: { type: 'array', items: calendarSchema },
            },
          },
          400: errorResponseSchema,
          403: errorResponseSchema,
          409: errorResponseSchema,
          422: errorResponseSchema,
          502: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      ensureEnabled();
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const { server } = request.body;
      const username = request.body.username.trim();
      const password = request.body.password;

      let serverUrl;
      if (server === 'icloud') {
        serverUrl = app.config.caldav.icloudUrl;
      } else {
        serverUrl = normalizeServerUrl(request.body.url, app.config.caldav.allowPrivateHosts);
        if (!serverUrl) {
          throw coded(
            app.httpErrors.unprocessableEntity(
              app.config.caldav.allowPrivateHosts
                ? 'Enter the server address, e.g. https://cloud.example.org'
                : 'Enter the server’s https:// address, e.g. https://cloud.example.org',
            ),
            'CALDAV_BAD_URL',
          );
        }
      }
      const host = new URL(serverUrl).host;
      const identity = caldavIdentity(host, username);

      // One CalDAV account per user per workspace: a different one must be
      // disconnected first (the card shows one account).
      const live = await app
        .db('calendar_accounts')
        .where({ user_id: request.user.id, workspace_id: workspaceId, provider: PROVIDER })
        .whereNull('deleted_at')
        .select();
      if (live.some((row) => row.provider_account_id !== identity)) {
        throw coded(
          app.httpErrors.conflict('Disconnect the calendar you have before connecting another'),
          'CALDAV_ALREADY_CONNECTED',
        );
      }

      const existing = await app
        .db('calendar_accounts')
        .where({ user_id: request.user.id, provider: PROVIDER, provider_account_id: identity })
        .first();
      // The identity is unique per user (one row): live in another workspace,
      // it would silently move here and stop mirroring there.
      if (existing && existing.deleted_at == null && existing.workspace_id !== workspaceId) {
        throw coded(
          app.httpErrors.conflict(
            'This calendar account is connected in another workspace — disconnect it there first',
          ),
          'CALDAV_ALREADY_CONNECTED',
        );
      }

      // Verify BEFORE storing (CALDAV.md §3.5).
      let found;
      try {
        const client = createCaldavClient({
          kind: server,
          serverUrl,
          username,
          password,
          config: app.config.caldav,
        });
        found = await discover(client, { startUrl: serverUrl });
      } catch (err) {
        request.log.info({ code: err?.code }, 'caldav connect failed');
        // Anything discovery could not make sense of (a malformed href from
        // a server we have never seen) is "not a CalDAV server", not a 500.
        throw translate(CONNECT_ERRORS[err?.code] ? err : { code: 'CALDAV_NOT_CALDAV' }, {
          icloud: isIcloudServer(server, serverUrl),
        });
      }
      const calendars = found.calendars.filter((c) => c.url.length <= MAX_CALENDAR_PATH);
      if (calendars.length === 0) {
        throw translate({ code: 'CALDAV_URL_TOO_LONG' });
      }
      if (found.homeUrl.length > 500 || found.principalUrl.length > 500) {
        throw translate({ code: 'CALDAV_URL_TOO_LONG' });
      }

      const key = app.config.calendar.tokenKey;
      const keep =
        existing &&
        existing.workspace_id === workspaceId &&
        existing.default_calendar_id &&
        calendars.some((c) => c.url === existing.default_calendar_id);
      const chosen = keep
        ? calendars.find((c) => c.url === existing.default_calendar_id)
        : calendars.length === 1
          ? calendars[0]
          : null;

      const values = {
        workspace_id: workspaceId,
        caldav_kind: server,
        caldav_server_url: serverUrl,
        principal_url: found.principalUrl,
        calendar_home_url: found.homeUrl,
        encrypted_app_password: encryptSecret(password, key),
        default_calendar_id: chosen?.url ?? null,
        calendar_display_name: chosen?.name ?? null,
        // A reconnect starts from a full listing: the cursor may be from before
        // the password was revoked, and links re-adopt by href.
        sync_token: null,
        status: 'active',
        last_error: null,
        deleted_at: null,
        updated_at: new Date(),
      };
      let accountId;
      if (existing) {
        accountId = existing.id;
        await app.db('calendar_accounts').where({ id: existing.id }).update(values);
      } else {
        accountId = newId();
        await app.db('calendar_accounts').insert({
          id: accountId,
          user_id: request.user.id,
          provider: PROVIDER,
          provider_account_id: identity,
          ...values,
        });
      }

      if (chosen) {
        await enqueueWorkspaceMirrorSweep(app, workspaceId);
        app.calendarSync.enqueueSync(accountId);
      }
      const row = await app.db('calendar_accounts').where({ id: accountId }).first();
      return reply.code(201).send({ account: serializeCaldavAccount(row), calendars });
    },
  );

  // ── Calendars / choose / disconnect ───────────────────────────────────────

  app.get(
    '/integrations/caldav/accounts/:accountId/calendars',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { accountId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            required: ['items'],
            properties: { items: { type: 'array', items: calendarSchema } },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
          422: errorResponseSchema,
          502: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      ensureEnabled();
      const account = await loadOwnAccount(request, request.params.accountId);
      const items = await calendarsOf(account);
      return { items: items.filter((c) => c.url.length <= MAX_CALENDAR_PATH) };
    },
  );

  app.patch(
    '/integrations/caldav/accounts/:accountId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { accountId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['calendarUrl'],
          properties: { calendarUrl: { type: 'string', minLength: 1, maxLength: 255 } },
        },
        response: {
          200: accountSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          422: errorResponseSchema,
          502: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      ensureEnabled();
      const account = await loadOwnAccount(request, request.params.accountId);
      // Only a calendar the server just listed: the client never gets to point
      // the connector at an arbitrary URL.
      const calendars = await calendarsOf(account);
      const chosen = calendars.find((c) => c.url === request.body.calendarUrl);
      if (!chosen) {
        throw coded(
          app.httpErrors.unprocessableEntity('That calendar is not in this account'),
          'CALDAV_UNKNOWN_CALENDAR',
        );
      }
      const changed = account.default_calendar_id !== chosen.url;
      await app
        .db('calendar_accounts')
        .where({ id: account.id })
        .update({
          default_calendar_id: chosen.url,
          calendar_display_name: chosen.name,
          ...(changed ? { sync_token: null } : {}),
          updated_at: new Date(),
        });
      if (changed) {
        await enqueueWorkspaceMirrorSweep(app, account.workspace_id);
        app.calendarSync.enqueueSync(account.id);
      }
      const fresh = await app.db('calendar_accounts').where({ id: account.id }).first();
      return serializeCaldavAccount(fresh);
    },
  );

  app.delete(
    '/integrations/caldav/accounts/:accountId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { accountId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const account = await loadOwnAccount(request, request.params.accountId);
      // We cannot revoke an app-specific password (no API, CALDAV.md §3.6):
      // the ciphertext goes, and the app tells the user the second half of
      // the job — revoking it — is theirs. Our task events and their links
      // stay; a reconnect re-adopts them through the deterministic href. The
      // cached copies of the user's OWN events go in the same transaction —
      // a disconnected calendar must not keep showing — and a reconnect's
      // full listing brings them back.
      await app.db.transaction(async (trx) => {
        await trx('calendar_accounts').where({ id: account.id }).update({
          status: 'disconnected',
          encrypted_app_password: null,
          sync_token: null,
          sync_dirty_at: null,
          last_error: null,
          deleted_at: new Date(),
          updated_at: new Date(),
        });
        const cached = await trx('calendar_external_events')
          .where({ calendar_account_id: account.id })
          .whereNull('deleted_at')
          .select('id');
        const revisions = await recordSyncWrites(
          trx,
          account.workspace_id,
          cached.map((row) => ({
            entityType: 'external_event',
            entityId: row.id,
            operation: 'delete',
          })),
        );
        const now = new Date();
        for (const [i, row] of cached.entries()) {
          await trx('calendar_external_events')
            .where({ id: row.id })
            .update({ deleted_at: now, revision: revisions[i], updated_at: now });
        }
      });
      return reply.code(204).send();
    },
  );
}

/**
 * What the user typed → the URL discovery starts from, or null. https only
 * unless the admin allowed private hosts; never userinfo or a fragment. A bare
 * host gets `https://` in front.
 */
export function normalizeServerUrl(value, allowPrivateHosts) {
  if (typeof value !== 'string') return null;
  let text = value.trim();
  if (!text) return null;
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) text = `https://${text}`;
  let url;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && !(allowPrivateHosts && url.protocol === 'http:')) return null;
  if (url.username || url.password || url.hash || text.includes('#')) return null;
  if (!url.hostname) return null;
  url.search = '';
  return url.href;
}
