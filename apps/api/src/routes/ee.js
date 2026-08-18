/**
 * Entitlement status (EE-003). ALWAYS registered — unlike feature routes,
 * capability discovery must exist on every build: a CE instance answers an
 * empty list with 200, never 404, so clients can cache "nothing enabled
 * here" the same way they cache "these features are on" (the aiStatus
 * pattern on the app side). Authenticated: what an instance is licensed for
 * is the operator's business, not the internet's.
 */
export default async function eeRoutes(app) {
  app.get(
    '/ee/status',
    {
      onRequest: [app.authenticate],
      schema: {
        response: {
          200: {
            type: 'object',
            additionalProperties: false,
            properties: {
              state: { type: 'string', enum: ['none', 'active', 'grace', 'readonly'] },
              features: { type: 'array', items: { type: 'string' } },
              expiresAt: { type: ['string', 'null'] },
              overlay: { type: 'string', enum: ['disabled', 'absent', 'loaded', 'error'] },
            },
          },
        },
      },
    },
    async () => ({
      state: app.entitlements.state,
      features: app.entitlements.list(),
      expiresAt: app.entitlements.expiresAt?.toISOString() ?? null,
      overlay: !app.ee?.enabled
        ? 'disabled'
        : app.ee.error
          ? 'error'
          : app.ee.loaded
            ? 'loaded'
            : 'absent',
    }),
  );
}
