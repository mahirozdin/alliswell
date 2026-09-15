import { toIso } from '../lib/serialize.js';
import { coded } from '../lib/errors.js';
import { deviceLabel } from '../db/sessions.js';

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
  required: ['id', 'platform', 'lastSeenAt'],
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

      const existing = await app.db('notification_devices').where({ id: deviceId }).first('id');
      if (existing) {
        await app.db('notification_devices').where({ id: deviceId }).update(values);
      } else {
        // A device with no name answers no question, and OPH-284 already
        // settled what to write instead: the User-Agent, RAW, because parsing
        // one is guessing and a client can shorten a string it can see. On
        // INSERT only — a heartbeat must never overwrite a name a client set
        // on purpose, which is also why `deviceName` keeps its key-presence
        // semantics above.
        await app.db('notification_devices').insert({
          id: deviceId,
          device_name: deviceLabel(request),
          ...values,
        });
      }

      const row = await app.db('notification_devices').where({ id: deviceId }).first();
      return reply.code(existing ? 200 : 201).send(serializeDevice(row));
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
            properties: { items: { type: 'array', items: deviceSchema } },
          },
        },
      },
    },
    async (request) => {
      const rows = await app
        .db('notification_devices')
        .where({ user_id: request.user.id })
        .orderBy('last_seen_at', 'desc')
        .select();
      return { items: rows.map(serializeDevice) };
    },
  );

  // Unregister. Always 204: repeating it (or aiming at a device you no longer
  // own) must never fail a sign-out flow.
  app.delete(
    '/notification-devices/:deviceId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { deviceId: ULID_PARAM } },
        response: { 204: { type: 'null' } },
      },
    },
    async (request, reply) => {
      await app
        .db('notification_devices')
        .where({ id: request.params.deviceId, user_id: request.user.id })
        .delete();
      return reply.code(204).send();
    },
  );
}
