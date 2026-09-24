import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { ListObjectsV2Command, S3Client } from '@aws-sdk/client-s3';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { storeServerFile } from '../../src/lib/server-files.js';
import { storageTestEnv, ensureBucket } from '../helpers/minio.js';

// OPH-340 — a file the server holds, over REAL infrastructure: the object in
// MinIO, the row in MySQL, the guard asked with the size the bytes measured.
// The unit suite holds every refusal against fake storage; this one proves
// the write is what a client's upload would have produced.
const enabled = process.env.INTEGRATION === '1';

const PNG_TYPE = {
  mime: 'image/png',
  ext: 'png',
  match: (b) => b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47,
};
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);

describe.runIf(enabled)('integration: a file the server holds (MySQL + MinIO) — OPH-340', () => {
  let app;
  let small; // the same database and bucket, with a one-megabyte ceiling
  let workspaceId;
  let projectId;
  let s3;
  let bucket;

  const objectsUnder = async (prefix) => {
    const res = await s3.send(new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix }));
    return (res.Contents ?? []).map((o) => o.Key);
  };

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    app = await buildApp({ config });
    small = await buildApp({
      config: loadConfig({
        ...process.env,
        ...storageTestEnv(),
        NODE_ENV: 'test',
        STORAGE_MAX_UPLOAD_MB: '1',
      }),
    });
    bucket = config.storage.bucket;
    s3 = new S3Client({
      endpoint: config.storage.endpoint,
      region: config.storage.region,
      forcePathStyle: config.storage.forcePathStyle,
      credentials: {
        accessKeyId: config.storage.accessKeyId,
        secretAccessKey: config.storage.secretAccessKey,
      },
    });

    const reg = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `server-files-${Date.now()}@example.com`, password: 'integration-pass-1' },
    });
    expect(reg.statusCode).toBe(201);
    const body = reg.json();
    workspaceId = body.workspace.id;
    const project = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/projects`,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
      payload: { name: 'Server-held files' },
    });
    expect(project.statusCode).toBe(201);
    projectId = project.json().id;
  });

  afterAll(async () => {
    s3?.destroy();
    if (small) await small.close();
    if (app) await app.close();
  });

  it('writes the object, gives it a ready row with its revision, and asks the guard with the measured size', async () => {
    const asked = [];
    const guard = async (ctx) => {
      asked.push({ sizeBytes: ctx.sizeBytes, phase: ctx.phase, origin: ctx.origin });
      return null;
    };
    app.ee.uploadGuards.push(guard);
    let row;
    try {
      row = await storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: PNG,
        filename: 'ariza.pdf',
        types: [PNG_TYPE],
      });
    } finally {
      app.ee.uploadGuards.splice(app.ee.uploadGuards.indexOf(guard), 1);
    }

    expect(asked).toEqual([{ sizeBytes: PNG.length, phase: 'commit', origin: 'server' }]);
    expect(await app.storage.head(row.storage_key)).toEqual({ size: PNG.length });

    const stored = await app.db('files').where({ id: row.id }).first();
    expect(stored).toMatchObject({ status: 'ready', name: 'ariza.png', mime: 'image/png' });
    const revision = await app
      .db('sync_revisions')
      .where({ entity_type: 'file', entity_id: row.id, operation: 'create' })
      .first();
    expect(revision).toBeTruthy();

    // The download a person would make returns these bytes, under this name.
    const { url } = await app.storage.presignGet(stored.storage_key, {
      filename: stored.name,
      contentType: stored.mime,
    });
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(Buffer.from(await res.arrayBuffer()).equals(PNG)).toBe(true);
    expect(res.headers.get('content-type')).toBe('image/png');

    await app.storage.remove(stored.storage_key);
  });

  it("the caller's own rows ride the same transaction: when they fail, the row rolls back and the object goes", async () => {
    let written;
    await expect(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: PNG,
        filename: 'geri-alinan.png',
        types: [PNG_TYPE],
        inTransaction: async (trx, row) => {
          written = row;
          throw new Error('the caller’s row could not be written');
        },
      }),
    ).rejects.toThrow('the caller’s row could not be written');
    // It WAS inserted inside the transaction — and is not there after it.
    expect(written?.id).toBeTruthy();
    expect(await app.db('files').where({ id: written.id }).first()).toBeUndefined();
    // The object's removal rides the queue (BullMQ here — real Redis): poll
    // until the worker lands it, like files-upload does.
    let gone = null;
    for (let attempt = 0; attempt < 40; attempt += 1) {
      gone = await app.storage.head(written.storage_key);
      if (gone === null) break;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    expect(gone).toBeNull();
  });

  it('over the ceiling is refused, and nothing reaches the bucket', async () => {
    const big = Buffer.concat([PNG, Buffer.alloc(1024 * 1024)]); // one megabyte and ten bytes
    const before = await objectsUnder(`ws/${workspaceId}/`);
    await expect(
      storeServerFile(small, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: big,
        filename: 'buyuk.png',
        types: [PNG_TYPE],
      }),
    ).rejects.toMatchObject({ code: 'FILE_TOO_LARGE' });
    // No NEW key: other objects may come and go on the GC queue meanwhile,
    // and a whole-prefix comparison would be measuring them instead.
    const after = await objectsUnder(`ws/${workspaceId}/`);
    expect(after.filter((key) => !before.includes(key))).toEqual([]);
    expect(await app.db('files').where({ target_id: projectId, name: 'buyuk.png' })).toHaveLength(
      0,
    );
  });
});
