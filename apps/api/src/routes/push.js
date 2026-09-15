/**
 * Web push discovery (OPH-310, ADR-0038).
 *
 * A browser cannot subscribe without the instance's VAPID **public** key, and
 * there is nowhere else to get it: it is not a compile-time constant, because a
 * self-hoster has their own. So this hands it over — and nothing else. The
 * private key stays where it was read.
 *
 * ── THE 404 IS THE FEATURE ────────────────────────────────────────────────
 *
 * This whole file is registered only when web push is configured (app.js), so
 * an instance without keys does not have the route. That makes one answer do
 * two jobs: the client asks once, and a 404 means both "no key here" and "this
 * server does not do push" — so it never offers a setting that could not work.
 * The same shape as the AI_ENABLED gate (OPH-215): conditional registration IS
 * the switch, and a feature that is off is indistinguishable from one that was
 * never built.
 *
 * Authenticated like every other /api/v1 route. The key is public by
 * construction — it ships in every client that subscribes — but the app always
 * has a session by the time it asks, so there is nothing to gain from an
 * anonymous surface.
 */
export default async function pushRoutes(app) {
  app.get(
    '/push/public-key',
    {
      onRequest: [app.authenticate],
      schema: {
        response: {
          200: {
            type: 'object',
            required: ['publicKey'],
            properties: { publicKey: { type: 'string' } },
          },
        },
      },
    },
    async () => ({ publicKey: app.config.push.webPush.publicKey }),
  );
}
