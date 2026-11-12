import { coded } from '../lib/errors.js';
import { ULID_RE } from '../lib/ids.js';
import { widgetTokenRateBucket } from '../lib/tokens.js';
import { liveFamilyOfDevice, mintWidgetToken } from '../db/widget-tokens.js';

/**
 * Widget tokens (OPH-458, issue #50, ADR-0070).
 *
 * The iOS widget extension builds its timeline while the app is swiped away,
 * and it needs an identity of its own to fetch `GET /widget/snapshot` with: a
 * read-only `aww_` token, one per notification device, that never rotates.
 *
 * SESSION ONLY: `rejectApiKeys` — a key minting a credential would make the
 * key's own revocation meaningless (ADR-0032 §4) — and a widget token is not
 * a session either (`app.authenticate` refuses `aww_`).
 *
 * The device must be one of the caller's `notification_devices` rows with a
 * live session bound to it (`refresh_tokens.device_id`, OPH-434): that session
 * family is the one the token is tied to, so the token dies when the device's
 * session ends. Anything else is 404 DEVICE_NOT_FOUND — the app registers the
 * device and tries again at its next foreground.
 *
 * The secret leaves the server once, in the 201 body; minting again for the
 * device replaces it (the previous token stops working in the same write).
 *
 * REST only (I-12): device infrastructure. The data a widget shows is already
 * readable through REST and MCP, and minting a credential has no place in MCP.
 */

/**
 * Route config for the widget snapshot (ADR-0070 §3, ADR-0045): 30 requests an
 * hour per widget token, the bucket read from the header before
 * authentication; without a widget token the IP is the bucket.
 */
export const WIDGET_RATE_LIMIT_PER_HOUR = 30;
export const widgetRateLimit = Object.freeze({
  rateLimit: {
    max: WIDGET_RATE_LIMIT_PER_HOUR,
    timeWindow: '1 hour',
    keyGenerator: (request) => widgetTokenRateBucket(request) ?? `ip:${request.ip}`,
  },
});

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

export default async function widgetTokenRoutes(app) {
  app.post(
    '/widget-tokens',
    {
      onRequest: [app.authenticate],
      preHandler: [app.rejectApiKeys],
      schema: {
        description:
          'Mints the read-only widget token (`aww_…`) for one of your notification devices. Session only; the token is shown once, opens GET /widget/snapshot alone, lives 90 days, and dies with the device or the session that minted it. Minting again for the device revokes the previous token.',
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['deviceId'],
          properties: {
            deviceId: {
              type: 'string',
              pattern: ULID_RE.source,
              description: 'The notification device (its id from PUT /notification-devices).',
            },
          },
        },
        response: {
          201: {
            type: 'object',
            additionalProperties: false,
            required: ['token', 'deviceId', 'expiresAt'],
            properties: {
              // The ONLY time this value exists outside the caller's hands.
              token: { type: 'string' },
              deviceId: { type: 'string' },
              expiresAt: { type: 'string' },
            },
          },
          400: errorResponseSchema,
          401: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = request.user.id;
      const { deviceId } = request.body;
      const device = await app
        .db('notification_devices')
        .where({ id: deviceId, user_id: userId })
        .first('id');
      const familyId = device ? await liveFamilyOfDevice(app.db, userId, deviceId) : null;
      if (!familyId) {
        throw coded(app.httpErrors.notFound('Device not found'), 'DEVICE_NOT_FOUND');
      }
      const { token, expiresAt } = await mintWidgetToken(app.db, app.config.auth.refreshSecret, {
        userId,
        deviceId,
        familyId,
      });
      // Never the token, at any level.
      request.log.info({ deviceId }, 'widget token minted');
      return reply.code(201).send({ token, deviceId, expiresAt: expiresAt.toISOString() });
    },
  );
}
