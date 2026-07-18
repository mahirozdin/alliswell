/**
 * Deployment-level storage status (Epic 14, ATTACHMENTS.md §6) — the app's
 * honest "are attachments on?" probe. Deployment state, not workspace state:
 * one bucket serves the whole install, so there is nothing per-workspace to
 * ask. Limits ride along so clients can fail oversized picks fast, before
 * wasting an upload round-trip.
 */
export default async function storageRoutes(app) {
  app.get(
    '/storage',
    {
      onRequest: [app.authenticate],
      schema: {
        response: {
          200: {
            type: 'object',
            properties: {
              configured: { type: 'boolean' },
              maxUploadBytes: { type: 'integer' },
              presignTtlSec: { type: 'integer' },
            },
          },
        },
      },
    },
    async () => ({
      configured: app.storage.enabled,
      maxUploadBytes: app.storage.maxUploadBytes,
      presignTtlSec: app.storage.presignTtlSec,
    }),
  );
}
