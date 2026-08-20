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
              // The apex domain this instance serves, when it serves one.
              // Capability discovery, not decoration: a client cannot tell
              // `acme.example.com` (one tenant of example.com) from an
              // ordinary host by looking at it, and guessing from the label
              // count would misread `api.alliswell.space` as a tenant.
              baseDomain: { type: ['string', 'null'] },
            },
          },
        },
      },
    },
    async (request) => {
      const status = {
        state: app.entitlements.state,
        features: app.entitlements.list(),
        expiresAt: app.entitlements.expiresAt?.toISOString() ?? null,
        baseDomain: app.config.ee.baseDomain,
        overlay: !app.ee?.enabled
          ? 'disabled'
          : app.ee.error
            ? 'error'
            : app.ee.loaded
              ? 'loaded'
              : 'absent',
      };
      // An extension that serves several customers from one instance can
      // narrow this to the caller's own list. It may only NARROW: the
      // instance answer is the ceiling, and a decorator that fails leaves it
      // untouched rather than taking the endpoint down with it.
      for (const decorate of app.ee?.statusDecorators ?? []) {
        try {
          Object.assign(status, (await decorate(request, status)) ?? {});
        } catch (err) {
          app.log.warn({ err: err.message }, 'EE status decorator failed — instance answer stands');
        }
      }
      return status;
    },
  );
}
