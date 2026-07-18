import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { createStorage } from '../../src/plugins/storage.js';
import { storageTestEnv, ensureBucket } from '../helpers/minio.js';

// OPH-150 — the REAL presigned flow against MinIO (`docker compose up -d minio`;
// in CI a plain `docker run`). This is the R2 stand-in: same S3 protocol, same
// SigV4 presigning, so what passes here is what R2 will see (ATTACHMENTS.md §12).
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('integration: storage presigned round-trip (MinIO)', () => {
  let storage;
  const key = `test/oph-150/${Date.now()}-roundtrip.txt`;
  const body = 'hello alliswell attachments';

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    storage = createStorage(config);
    expect(storage.enabled).toBe(true);
  });

  afterAll(async () => {
    if (storage?.enabled) {
      await storage.remove(key);
      await storage.close();
    }
  });

  it('PUT via presigned URL → head sees the exact byte count', async () => {
    const { url, headers } = await storage.presignPut(key, { contentType: 'text/plain' });
    const res = await fetch(url, { method: 'PUT', headers, body });
    expect(res.status).toBe(200);

    const head = await storage.head(key);
    expect(head).toEqual({ size: Buffer.byteLength(body) });
  });

  it('GET via presigned URL returns the same bytes with pinned name + type', async () => {
    const { url } = await storage.presignGet(key, {
      filename: 'Özet raporu.txt',
      contentType: 'text/plain',
    });
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(body);
    expect(res.headers.get('content-type')).toBe('text/plain');
    const disposition = res.headers.get('content-disposition');
    expect(disposition).toContain('attachment');
    expect(disposition).toContain(`filename*=UTF-8''%C3%96zet%20raporu.txt`);
  });

  it('a tampered signature is refused by the store, not by us', async () => {
    const { url } = await storage.presignGet(key, {
      filename: 'x.txt',
      contentType: 'text/plain',
    });
    const tampered = new URL(url);
    tampered.searchParams.set('X-Amz-Signature', '0'.repeat(64));
    const res = await fetch(tampered);
    expect(res.status).toBe(403);
  });

  it('remove is idempotent and head reports the object gone', async () => {
    await storage.remove(key);
    await storage.remove(key); // second delete of a missing key: still fine
    expect(await storage.head(key)).toBeNull();
  });
});
