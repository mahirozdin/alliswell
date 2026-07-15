import { toIso } from '../lib/serialize.js';

/**
 * Notification device registry (OPH-060, BLUEPRINT §8): which installs may
 * receive notifications for a user. The device registers itself with a
 * client-generated ULID (the app reuses its sync client id) and re-PUTs as a
 * heartbeat — push tokens are optional because v1 notifications are local
 * (flutter_local_notifications, OPH-061); FCM/APNs land later and only ever
 * carry IDs, never task content (§8.3).
 */

const PLATFORMS = ['ios', 'android', 'macos', 'windows', 'linux', 'web'];
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
    lastSeenAt: toIso(row.last_seen_at),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
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
      const values = {
        user_id: request.user.id,
        platform: body.platform,
        ...('pushToken' in body ? { push_token: body.pushToken } : {}),
        ...('deviceName' in body ? { device_name: body.deviceName } : {}),
        ...('appVersion' in body ? { app_version: body.appVersion } : {}),
        last_seen_at: new Date(),
        updated_at: new Date(),
      };

      const existing = await app.db('notification_devices').where({ id: deviceId }).first('id');
      if (existing) {
        await app.db('notification_devices').where({ id: deviceId }).update(values);
      } else {
        await app.db('notification_devices').insert({ id: deviceId, ...values });
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
