import { describe, it, expect } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { createStorage, contentDisposition } from '../../src/plugins/storage.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';

// OPH-150 — storage foundation (ATTACHMENTS.md §§1-2, §10; ADR-0011).

const FULL_ENV = {
  NODE_ENV: 'test',
  STORAGE_S3_ENDPOINT: 'http://127.0.0.1:9000',
  STORAGE_S3_BUCKET: 'alliswell-test',
  STORAGE_S3_ACCESS_KEY_ID: 'test-access',
  STORAGE_S3_SECRET_ACCESS_KEY: 'test-secret',
};

describe('config: storage block', () => {
  it('is disabled (nulls) without any storage env', () => {
    const config = loadConfig({ NODE_ENV: 'test' });
    expect(config.storage.endpoint).toBeNull();
    expect(config.storage.bucket).toBeNull();
    // Defaults still resolve so the status endpoint can report limits.
    expect(config.storage.maxUploadBytes).toBe(512 * 1024 * 1024);
    expect(config.storage.presignTtlSec).toBe(3600);
    expect(config.storage.sweepSec).toBe(3600);
    expect(config.storage.forcePathStyle).toBe(true);
    expect(config.storage.region).toBe('auto');
  });

  it('loads a full configuration', () => {
    const config = loadConfig({
      ...FULL_ENV,
      STORAGE_S3_REGION: 'weur',
      STORAGE_S3_FORCE_PATH_STYLE: 'false',
      STORAGE_MAX_UPLOAD_MB: '64',
      STORAGE_PRESIGN_TTL_SEC: '120',
      STORAGE_SWEEP_SEC: '60',
    });
    expect(config.storage.endpoint).toBe('http://127.0.0.1:9000');
    expect(config.storage.bucket).toBe('alliswell-test');
    expect(config.storage.region).toBe('weur');
    expect(config.storage.forcePathStyle).toBe(false);
    expect(config.storage.maxUploadBytes).toBe(64 * 1024 * 1024);
    expect(config.storage.presignTtlSec).toBe(120);
    expect(config.storage.sweepSec).toBe(60);
  });

  it.each([
    ['STORAGE_S3_ENDPOINT', { NODE_ENV: 'test', STORAGE_S3_ENDPOINT: 'http://x' }],
    ['STORAGE_S3_BUCKET', { NODE_ENV: 'test', STORAGE_S3_BUCKET: 'b' }],
    [
      'keys only',
      {
        NODE_ENV: 'test',
        STORAGE_S3_ACCESS_KEY_ID: 'a',
        STORAGE_S3_SECRET_ACCESS_KEY: 's',
      },
    ],
  ])('rejects partial storage config at boot (%s)', (_label, env) => {
    expect(() => loadConfig(env)).toThrow(/Partial storage config/);
  });

  it('names exactly the missing variables in the partial-config error', () => {
    expect(() => loadConfig({ NODE_ENV: 'test', STORAGE_S3_BUCKET: 'b' })).toThrow(
      /STORAGE_S3_ENDPOINT.*STORAGE_S3_ACCESS_KEY_ID.*STORAGE_S3_SECRET_ACCESS_KEY/,
    );
  });

  it('rejects out-of-range presign TTLs (60…604800 — the R2 cap)', () => {
    expect(() => loadConfig({ ...FULL_ENV, STORAGE_PRESIGN_TTL_SEC: '59' })).toThrow(/604800/);
    expect(() => loadConfig({ ...FULL_ENV, STORAGE_PRESIGN_TTL_SEC: '604801' })).toThrow(/604800/);
  });

  it('rejects a sub-1MB upload cap and a bad bool', () => {
    expect(() => loadConfig({ ...FULL_ENV, STORAGE_MAX_UPLOAD_MB: '0' })).toThrow(
      /STORAGE_MAX_UPLOAD_MB/,
    );
    expect(() => loadConfig({ ...FULL_ENV, STORAGE_S3_FORCE_PATH_STYLE: 'yep' })).toThrow(
      /STORAGE_S3_FORCE_PATH_STYLE/,
    );
  });
});

describe('contentDisposition', () => {
  it('keeps plain ASCII names in both forms', () => {
    expect(contentDisposition('report.pdf')).toBe(
      `attachment; filename="report.pdf"; filename*=UTF-8''report.pdf`,
    );
  });

  it('round-trips Turkish filenames via RFC 5987 and degrades the fallback', () => {
    const value = contentDisposition('Rapor Özeti ışığı.pdf');
    expect(value).toContain(
      `filename*=UTF-8''Rapor%20%C3%96zeti%20%C4%B1%C5%9F%C4%B1%C4%9F%C4%B1.pdf`,
    );
    expect(value).toContain('filename="Rapor _zeti _____.pdf"');
  });

  it('never lets a quote break out of the quoted fallback', () => {
    expect(contentDisposition('a"b.txt')).toContain(`filename="a'b.txt"`);
  });
});

describe('createStorage', () => {
  it('disabled mode: enabled=false, helpers refuse loudly', () => {
    const storage = createStorage(loadConfig({ NODE_ENV: 'test' }));
    expect(storage.enabled).toBe(false);
    expect(storage.maxUploadBytes).toBe(512 * 1024 * 1024);
    expect(() => storage.presignPut('k', { contentType: 'text/plain' })).toThrow(/not configured/);
    expect(() => storage.head('k')).toThrow(/not configured/);
  });

  it('presigns PUT URLs offline: SigV4 against the configured endpoint + bucket', async () => {
    const storage = createStorage(loadConfig({ ...FULL_ENV, STORAGE_PRESIGN_TTL_SEC: '900' }));
    const { url, headers, expiresAt } = await storage.presignPut('ws/W/FILE1', {
      contentType: 'image/png',
    });
    const parsed = new URL(url);
    expect(parsed.origin).toBe('http://127.0.0.1:9000');
    expect(parsed.pathname).toBe('/alliswell-test/ws/W/FILE1'); // path style
    expect(parsed.searchParams.get('X-Amz-Expires')).toBe('900');
    expect(parsed.searchParams.get('X-Amz-Signature')).toBeTruthy();
    expect(parsed.searchParams.get('X-Amz-Credential')).toContain('test-access');
    // The signed content type must travel back as a header contract.
    expect(headers).toEqual({ 'content-type': 'image/png' });
    expect(Date.parse(expiresAt)).toBeGreaterThan(Date.now());
  });

  it('presigns GET URLs pinning download name + content type from metadata', async () => {
    const storage = createStorage(loadConfig(FULL_ENV));
    const { url } = await storage.presignGet('ws/W/FILE2', {
      filename: 'Özet.png',
      contentType: 'image/png',
    });
    const parsed = new URL(url);
    expect(parsed.searchParams.get('response-content-type')).toBe('image/png');
    expect(parsed.searchParams.get('response-content-disposition')).toContain(
      `filename*=UTF-8''%C3%96zet.png`,
    );
  });
});

describe('GET /api/v1/storage', () => {
  it('requires auth', async () => {
    const { app } = await buildTestApp();
    const res = await app.inject({ method: 'GET', url: '/api/v1/storage' });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('reports not-configured honestly (default test app)', async () => {
    const { app } = await buildTestApp();
    const { headers } = await registerUser(app, { email: 'storage-off@example.com' });
    const res = await app.inject({ method: 'GET', url: '/api/v1/storage', headers });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      configured: false,
      maxUploadBytes: 512 * 1024 * 1024,
      presignTtlSec: 3600,
    });
    await app.close();
  });

  it('reports limits from an injected (configured) storage', async () => {
    const { app } = await buildTestApp({
      storage: { enabled: true, maxUploadBytes: 10 * 1024 * 1024, presignTtlSec: 300 },
    });
    const { headers } = await registerUser(app, { email: 'storage-on@example.com' });
    const res = await app.inject({ method: 'GET', url: '/api/v1/storage', headers });
    expect(res.json()).toEqual({
      configured: true,
      maxUploadBytes: 10 * 1024 * 1024,
      presignTtlSec: 300,
    });
    await app.close();
  });
});
