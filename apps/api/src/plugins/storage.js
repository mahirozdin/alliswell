import fp from 'fastify-plugin';
import {
  S3Client,
  HeadObjectCommand,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

/**
 * Object storage for attachments (Epic 14, ATTACHMENTS.md / ADR-0011).
 *
 * Speaks the S3 protocol: Cloudflare R2 is the documented primary target,
 * MinIO stands in for dev/CI, and any S3-compatible store works. Bytes never
 * pass through the API — this plugin only MINTS presigned URLs (single
 * object, single verb, expiring) and does metadata-side HEAD/DELETE calls.
 *
 * Decorates `app.storage`:
 *   enabled            — false without full STORAGE_S3_* config (feature off)
 *   maxUploadBytes     — per-file cap, enforced at upload completion
 *   presignTtlSec      — lifetime of minted URLs
 *   presignPut(key, {contentType})        → { url, headers, expiresAt }
 *   presignGet(key, {filename, contentType}) → { url, expiresAt }
 *   head(key)          → { size } | null (missing object)
 *   remove(key)        → resolves even when the object is already gone
 *
 * Tests inject a fake via `buildApp({ storage })`, exactly like `db`/`redis`.
 */

/**
 * `Content-Disposition: attachment` that survives non-ASCII filenames
 * (RFC 5987/6266): an ASCII fallback plus the UTF-8 `filename*` form —
 * Turkish filenames must round-trip through downloads.
 */
export function contentDisposition(filename) {
  const fallback = filename.replace(/"/g, "'").replace(/[^\x20-\x7e]/g, '_');
  const encoded = encodeURIComponent(filename).replace(
    /['()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
  return `attachment; filename="${fallback}"; filename*=UTF-8''${encoded}`;
}

function isMissingObjectError(err) {
  // HeadObject reports 404 as NotFound; some stores answer NoSuchKey.
  return (
    err?.name === 'NotFound' || err?.name === 'NoSuchKey' || err?.$metadata?.httpStatusCode === 404
  );
}

export function createStorage(config) {
  const { storage } = config;
  const enabled = Boolean(
    storage.endpoint && storage.bucket && storage.accessKeyId && storage.secretAccessKey,
  );

  if (!enabled) {
    const off = () => {
      throw new Error('storage is not configured (STORAGE_S3_* env) — guard with storage.enabled');
    };
    return {
      enabled: false,
      maxUploadBytes: storage.maxUploadBytes,
      presignTtlSec: storage.presignTtlSec,
      presignPut: off,
      presignGet: off,
      head: off,
      remove: off,
      close: async () => {},
    };
  }

  const client = new S3Client({
    endpoint: storage.endpoint,
    region: storage.region,
    forcePathStyle: storage.forcePathStyle,
    credentials: {
      accessKeyId: storage.accessKeyId,
      secretAccessKey: storage.secretAccessKey,
    },
  });
  const expiresIn = storage.presignTtlSec;
  const expiresAt = () => new Date(Date.now() + expiresIn * 1000).toISOString();

  return {
    enabled: true,
    maxUploadBytes: storage.maxUploadBytes,
    presignTtlSec: expiresIn,

    /** Presigned PUT for the client's direct upload. Content type is signed. */
    async presignPut(key, { contentType }) {
      const command = new PutObjectCommand({
        Bucket: storage.bucket,
        Key: key,
        ContentType: contentType,
      });
      const url = await getSignedUrl(client, command, { expiresIn });
      // The client MUST send this header — it is part of the signature.
      return { url, headers: { 'content-type': contentType }, expiresAt: expiresAt() };
    },

    /**
     * Presigned GET for downloads/inline rendering. Filename and content type
     * are pinned from OUR metadata via response-* overrides, so a renamed file
     * downloads under its current name without the object ever moving.
     */
    async presignGet(key, { filename, contentType }) {
      const command = new GetObjectCommand({
        Bucket: storage.bucket,
        Key: key,
        ResponseContentDisposition: contentDisposition(filename),
        ResponseContentType: contentType,
      });
      const url = await getSignedUrl(client, command, { expiresIn });
      return { url, expiresAt: expiresAt() };
    },

    /** Metadata probe for upload verification. `null` when the object is missing. */
    async head(key) {
      try {
        const res = await client.send(new HeadObjectCommand({ Bucket: storage.bucket, Key: key }));
        return { size: Number(res.ContentLength) };
      } catch (err) {
        if (isMissingObjectError(err)) return null;
        throw err;
      }
    },

    /** Idempotent delete — a missing object is a success, not an error. */
    async remove(key) {
      try {
        await client.send(new DeleteObjectCommand({ Bucket: storage.bucket, Key: key }));
      } catch (err) {
        if (!isMissingObjectError(err)) throw err;
      }
    },

    close: async () => client.destroy(),
  };
}

export default fp(
  async function storagePlugin(app, opts) {
    const storage = opts.storage ?? createStorage(app.config);
    app.decorate('storage', storage);
    app.addHook('onClose', async () => {
      if (!opts.storage) await storage.close?.();
    });
  },
  { name: 'alliswell-storage' },
);
