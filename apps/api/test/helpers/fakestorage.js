/**
 * In-memory stand-in for the storage plugin's surface (`buildApp({ storage })`)
 * so unit tests drive the whole upload lifecycle without S3/MinIO:
 *
 * - `objects` — Map(storageKey → size). Seed it to simulate "the client PUT
 *   the bytes" (presigned uploads bypass the API, so tests place the object
 *   the way the real world would).
 * - `removed` — every key handed to `remove`, in order (GC assertions).
 * - Presigned URLs are deterministic fakes: `https://fake-store/{verb}/{key}`.
 */
export function fakeStorage({
  enabled = true,
  maxUploadBytes = 512 * 1024 * 1024,
  presignTtlSec = 3600,
} = {}) {
  const objects = new Map();
  const removed = [];
  const expiresAt = () => new Date(Date.now() + presignTtlSec * 1000).toISOString();

  return {
    enabled,
    maxUploadBytes,
    presignTtlSec,
    objects,
    removed,
    async presignPut(key, { contentType }) {
      return {
        url: `https://fake-store/put/${key}`,
        headers: { 'content-type': contentType },
        expiresAt: expiresAt(),
      };
    },
    async presignGet(key, { filename, contentType }) {
      const q = new URLSearchParams({ filename, contentType });
      return { url: `https://fake-store/get/${key}?${q}`, expiresAt: expiresAt() };
    },
    async head(key) {
      return objects.has(key) ? { size: objects.get(key) } : null;
    },
    async remove(key) {
      removed.push(key);
      objects.delete(key);
    },
    close: async () => {},
  };
}
