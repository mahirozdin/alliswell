import { toIso } from '../lib/serialize.js';
import { coded } from '../lib/errors.js';
import {
  deviceLabel,
  deviceSignedOut,
  devicesWithSession,
  revokeDeviceSessions,
} from '../db/sessions.js';
import { transactionWithRetry } from '../db/tx.js';
import {
  RINGS_URGENT_SOURCES,
  anyRinging,
  decideForNewRow,
  lockUsers,
  platformLabel,
  promoteIfNoneRings,
} from '../db/notification-devices.js';

/**
 * Notification device registry (OPH-060, BLUEPRINT §8): which installs may
 * receive notifications for a user. The device registers itself with a
 * client-generated ULID (the app reuses its sync client id) and re-PUTs as a
 * heartbeat — push tokens are optional because v1 notifications are local
 * (flutter_local_notifications, OPH-061); FCM/APNs land later and only ever
 * carry IDs, never task content (§8.3).
 *
 * **Somebody calls it now (OPH-309).** For six weeks this route was correct and
 * unused: EE measured it on 2026-08-24 and wrote down that `notification_devices`
 * is empty on every real instance, because nothing in the Flutter app had ever
 * called it. Epic 30 rests on this table — `last_seen_at` is the whole of the
 * staleness test that decides who gets pushed to — so the app now registers on
 * sign-in, re-PUTs when it comes back to the foreground, and DELETEs on the way
 * out.
 *
 * `locale` is the device's, not the account's: the fallback push renders a fixed
 * string and a phone can be in a different language from the laptop (ADR-0038).
 *
 * **Which device rings urgent alarms (OPH-433, ADR-0069).** `ringsUrgent` is
 * decided by the server when a row is created for a user (insert or takeover),
 * with the user's row locked; a heartbeat never touches it, `PATCH` is the
 * user's choice, and deleting the last ringing row promotes another one. The
 * rule itself lives in `db/notification-devices.js`. REST only: MCP does not
 * get these routes — they are device infrastructure, not task data, and
 * removing a device is delete-like (I-12).
 *
 * **Removing a device signs it out (OPH-435, #48).** `DELETE` revokes every
 * refresh family bound to the device (`refresh_tokens.device_id`, OPH-434) in
 * the transaction that removes the row; the reverse holds too — a session
 * that ends takes its bound device with it (`db/sessions.js`). `GET` says per
 * device whether a live session is still bound to it (`hasSession`). A
 * removed device cannot `PUT` its row back while its access token lasts: a
 * device whose bound sessions have all ended gets 401 `AUTH_SESSION_REVOKED`.
 */

const PLATFORMS = ['ios', 'android', 'macos', 'windows', 'linux', 'web'];
const PUSH_PROVIDERS = ['fcm', 'webpush'];
const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const deviceSchema = {
  type: 'object',
  required: ['id', 'platform', 'lastSeenAt', 'ringsUrgent'],
  properties: {
    id: { type: 'string' },
    platform: { type: 'string', enum: PLATFORMS },
    pushToken: { type: ['string', 'null'] },
    deviceName: { type: ['string', 'null'] },
    appVersion: { type: ['string', 'null'] },
    locale: { type: ['string', 'null'] },
    pushProvider: { type: ['string', 'null'], enum: [...PUSH_PROVIDERS, null] },
    pushEndpoint: { type: ['string', 'null'] },
    invalidAt: { type: ['string', 'null'] },
    lastPushAt: { type: ['string', 'null'] },
    lastSeenAt: { type: 'string' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
    // OPH-433: does this device ring urgent alarms, and who decided — the
    // server's first-device rule ('auto'), the user ('user') or the OPH-432
    // migration ('backfill'). Old clients ignore both.
    ringsUrgent: { type: 'boolean' },
    ringsUrgentSource: { type: ['string', 'null'], enum: [...RINGS_URGENT_SOURCES, null] },
  },
};

// GET only: is somebody still signed in on this device — a live refresh family
// bound to it (OPH-435). False for a device whose session ended and for one an
// older client registered without binding its sign-in.
const listedDeviceSchema = {
  ...deviceSchema,
  required: [...deviceSchema.required, 'hasSession'],
  properties: { ...deviceSchema.properties, hasSession: { type: 'boolean' } },
};

const patchResponseSchema = {
  ...deviceSchema,
  required: [...deviceSchema.required, 'warnings'],
  properties: {
    ...deviceSchema.properties,
    // 'NO_URGENT_DEVICE' when none of the user's devices rings any more:
    // allowed, never blocked, so the client can warn instead.
    warnings: { type: 'array', items: { type: 'string', enum: ['NO_URGENT_DEVICE'] } },
  },
};

function serializeDevice(row) {
  return {
    id: row.id,
    platform: row.platform,
    pushToken: row.push_token ?? null,
    deviceName: row.device_name ?? null,
    appVersion: row.app_version ?? null,
    locale: row.locale ?? null,
    pushProvider: row.push_provider ?? null,
    pushEndpoint: row.push_endpoint ?? null,
    // `push_p256dh` and `push_auth` are deliberately absent. They are what
    // encrypts a payload TO this browser; the client that registered them
    // already has them, so echoing them only widens what a leaked response is
    // worth.
    invalidAt: toIso(row.invalid_at) ?? null,
    lastPushAt: toIso(row.last_push_at) ?? null,
    lastSeenAt: toIso(row.last_seen_at),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
    // mysql2 reads BOOLEAN (TINYINT(1)) back as 0/1.
    ringsUrgent: Boolean(Number(row.rings_urgent ?? 0)),
    ringsUrgentSource: row.rings_urgent_source ?? null,
  };
}

/** Is this body registering something a sender could actually send to? */
function carriesCredentials(body) {
  return Boolean(body.pushToken || body.pushEndpoint);
}

/**
 * A subscription is an endpoint AND two keys, or it is not a subscription.
 *
 * The config block refuses half a VAPID pair for the same reason (OPH-310): a
 * half-filled row looks registered, is skipped by every sender that reads it,
 * and its silence is indistinguishable from "nothing was due".
 */
function assertDeliverable(app, body) {
  if (body.pushProvider !== 'webpush') return;
  const required = {
    pushEndpoint: body.pushEndpoint,
    pushP256dh: body.pushP256dh,
    pushAuth: body.pushAuth,
  };
  const missing = Object.entries(required)
    .filter(([, value]) => !value)
    .map(([name]) => name);
  if (missing.length > 0) {
    throw coded(
      app.httpErrors.badRequest(
        `A web push subscription needs ${missing.join(', ')} as well as the endpoint`,
      ),
      'PUSH_SUBSCRIPTION_INCOMPLETE',
    );
  }
}

export default async function notificationDeviceRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  // Register or heartbeat (idempotent upsert). A device that signs into a
  // different account is taken over by that account — exactly one owner per
  // install at any time.
  app.put(
    '/notification-devices/:deviceId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { deviceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['platform'],
          properties: {
            platform: { type: 'string', enum: PLATFORMS },
            pushToken: { type: ['string', 'null'], maxLength: 512 },
            deviceName: { type: ['string', 'null'], maxLength: 255 },
            appVersion: { type: ['string', 'null'], maxLength: 64 },
            locale: { type: ['string', 'null'], maxLength: 16 },
            pushProvider: { type: ['string', 'null'], enum: [...PUSH_PROVIDERS, null] },
            pushEndpoint: { type: ['string', 'null'], maxLength: 2048 },
            pushP256dh: { type: ['string', 'null'], maxLength: 128 },
            pushAuth: { type: ['string', 'null'], maxLength: 64 },
          },
        },
        response: {
          200: deviceSchema,
          201: deviceSchema,
          400: errorResponseSchema,
          401: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { deviceId } = request.params;
      const body = request.body;
      assertDeliverable(app, body);
      const values = {
        user_id: request.user.id,
        platform: body.platform,
        ...('pushToken' in body ? { push_token: body.pushToken } : {}),
        ...('deviceName' in body ? { device_name: body.deviceName } : {}),
        ...('appVersion' in body ? { app_version: body.appVersion } : {}),
        ...('locale' in body ? { locale: body.locale } : {}),
        ...('pushEndpoint' in body ? { push_endpoint: body.pushEndpoint } : {}),
        ...('pushP256dh' in body ? { push_p256dh: body.pushP256dh } : {}),
        ...('pushAuth' in body ? { push_auth: body.pushAuth } : {}),
        // A token is an FCM token — this system has no other kind, because
        // iPhones are reached through FCM's APNs relay (ADR-0038). Saying so
        // here keeps an older client that sends only a token unambiguous to the
        // sender instead of leaving it to guess.
        ...('pushProvider' in body
          ? { push_provider: body.pushProvider }
          : body.pushToken
            ? { push_provider: 'fcm' }
            : {}),
        // Registering credentials is a device saying it is reachable again, so
        // it clears the dead mark. A plain heartbeat does NOT: a subscription
        // the browser revoked stays revoked however often the tab is opened.
        ...(carriesCredentials(body) ? { invalid_at: null } : {}),
        last_seen_at: new Date(),
        updated_at: new Date(),
      };

      const userId = request.user.id;
      const existing = await app
        .db('notification_devices')
        .where({ id: deviceId })
        .first('id', 'user_id');

      let status = 200;
      // Heartbeat: the common path, no lock, and `rings_urgent` untouched. It
      // only writes while the row is still ours: an unlocked read can be
      // overtaken by another account's takeover, and an update by id alone
      // would then hand the install back with the other account's `ringsUrgent`
      // still set — two automatic ringers for one user. Zero rows means the
      // read is stale, so the locked insert/takeover path decides instead.
      const beat =
        existing && existing.user_id === userId
          ? await app
              .db('notification_devices')
              .where({ id: deviceId, user_id: userId })
              .update(values)
          : 0;
      if (beat === 0) {
        // Insert or takeover: the urgent-device rule runs with the user's row
        // locked (and the previous owner's, whose ringing device may leave).
        status = await transactionWithRetry(app.db, async (trx) => {
          await lockUsers(trx, [userId, existing?.user_id]);
          const current = await trx('notification_devices')
            .where({ id: deviceId })
            .forUpdate()
            .first('id', 'user_id', 'rings_urgent');
          if (current && current.user_id === userId) {
            // Lost a race to our own first registration: a heartbeat now.
            await trx('notification_devices').where({ id: deviceId }).update(values);
            return 200;
          }
          // A device removed from the account (or whose session ended) is
          // signed out: the access token it still holds must not recreate
          // its row, or its pushes would outlive the sign-out (OPH-435). The
          // 401 sends the client to /auth/refresh, which is refused, and the
          // client then signs itself out.
          if (await deviceSignedOut(trx, userId, deviceId)) {
            throw coded(
              app.httpErrors.unauthorized('This device was signed out'),
              'AUTH_SESSION_REVOKED',
            );
          }
          const flags = await decideForNewRow(trx, userId, deviceId, body.platform);
          if (current) {
            await trx('notification_devices')
              .where({ id: deviceId })
              .update({ ...values, ...flags });
            if (Number(current.rings_urgent) === 1) {
              await promoteIfNoneRings(trx, current.user_id);
            }
            return 200;
          }
          // A device with no name answers no question, and OPH-284 already
          // settled what to write instead: the User-Agent, RAW, because
          // parsing one is guessing and a client can shorten a string it can
          // see. On INSERT only — a heartbeat must never overwrite a name a
          // client set on purpose, which is also why `deviceName` keeps its
          // key-presence semantics above.
          await trx('notification_devices').insert({
            id: deviceId,
            device_name: deviceLabel(request),
            ...values,
            ...flags,
          });
          return 201;
        });
      }

      const row = await app.db('notification_devices').where({ id: deviceId }).first();
      return reply.code(status).send(serializeDevice(row));
    },
  );

  app.get(
    '/notification-devices',
    {
      ...auth,
      schema: {
        response: {
          200: {
            type: 'object',
            properties: { items: { type: 'array', items: listedDeviceSchema } },
          },
        },
      },
    },
    async (request) => {
      const userId = request.user.id;
      const rows = await app
        .db('notification_devices')
        .where({ user_id: userId })
        .orderBy('last_seen_at', 'desc')
        .select();
      const signedIn = await devicesWithSession(
        app.db,
        userId,
        rows.map((row) => row.id),
      );
      return {
        items: rows.map((row) => ({ ...serializeDevice(row), hasSession: signedIn.has(row.id) })),
      };
    },
  );

  // The user's own choices for one of their devices (OPH-433): whether it rings
  // urgent alarms, and its name. Another account's device answers 404, the
  // same as one that does not exist.
  app.patch(
    '/notification-devices/:deviceId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { deviceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          properties: {
            ringsUrgent: { type: 'boolean' },
            deviceName: { type: ['string', 'null'], maxLength: 255 },
          },
        },
        response: {
          200: patchResponseSchema,
          400: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { deviceId } = request.params;
      const userId = request.user.id;
      const body = request.body ?? {};
      return transactionWithRetry(app.db, async (trx) => {
        await lockUsers(trx, [userId]);
        const row = await trx('notification_devices')
          .where({ id: deviceId, user_id: userId })
          .first('id', 'platform');
        if (!row) {
          throw coded(app.httpErrors.notFound('Device not found'), 'DEVICE_NOT_FOUND');
        }
        const changes = {};
        if ('ringsUrgent' in body) {
          changes.rings_urgent = body.ringsUrgent;
          changes.rings_urgent_source = 'user';
        }
        if ('deviceName' in body) {
          const name = (body.deviceName ?? '').trim();
          changes.device_name = name === '' ? platformLabel(row.platform) : name;
        }
        if (Object.keys(changes).length > 0) {
          await trx('notification_devices')
            .where({ id: deviceId })
            .update({ ...changes, updated_at: new Date() });
        }
        const updated = await trx('notification_devices').where({ id: deviceId }).first();
        return {
          ...serializeDevice(updated),
          warnings: (await anyRinging(trx, userId)) ? [] : ['NO_URGENT_DEVICE'],
        };
      });
    },
  );

  // Unregister, which is also a remote sign-out (OPH-435). Always 204:
  // repeating it (or aiming at a device you no longer own, or one that does
  // not exist) must never fail a sign-out flow, and such a call revokes
  // nothing. On the caller's own row, in one transaction: every refresh family
  // bound to the device is revoked, the row is removed, and removing the
  // device that rang hands the alarm to the most recently seen remaining one
  // (OPH-433).
  //
  // The app's own sign-out calls this on its own device BEFORE /auth/logout,
  // so it revokes its own family first; /auth/logout is always 204 and the
  // sign-out completes unchanged.
  //
  // The limit: an access token is a stateless JWT, so the removed device keeps
  // the one it holds until it expires (at most AUTH_ACCESS_TTL_SEC, 15 minutes
  // by default). It cannot register its row again with it (PUT answers 401
  // AUTH_SESSION_REVOKED); its next refresh is refused and the client signs
  // out then, and a refused refresh of a revoked family removes any row of
  // its device that is still there.
  //
  // Closed to API keys: signing a device out is session management, which a
  // delegated machine credential never reaches (ADR-0032).
  app.delete(
    '/notification-devices/:deviceId',
    {
      ...auth,
      preHandler: [app.rejectApiKeys],
      schema: {
        params: { type: 'object', properties: { deviceId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const userId = request.user.id;
      const where = { id: request.params.deviceId, user_id: userId };
      await transactionWithRetry(app.db, async (trx) => {
        await lockUsers(trx, [userId]);
        const row = await trx('notification_devices').where(where).first('id', 'rings_urgent');
        if (!row) return;
        await revokeDeviceSessions(trx, { userId, deviceId: row.id });
        await trx('notification_devices').where(where).delete();
        if (Number(row.rings_urgent) === 1) await promoteIfNoneRings(trx, userId);
      });
      return reply.code(204).send();
    },
  );
}
