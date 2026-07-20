import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { ensureBucket, storageTestEnv } from '../helpers/minio.js';

// OPH-169 — folders over real MySQL + MinIO: the recursive delete's
// no-orphaned-bytes guarantee, end to end (needs migrations applied).
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('folders integration (OPH-169, ADR-0014)', () => {
  let app;
  let headers;
  let workspaceId;

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    app = await buildApp({ config });
    const email = `folders-int-${Date.now()}@example.com`;
    const register = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'sifre-12345' },
    });
    const body = register.json();
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    workspaceId = body.workspace.id;
  });

  afterAll(async () => {
    // Seeded rows stay (workspace owner FK RESTRICTs user deletes — the
    // files-upload suite leaves its rows too; unique emails keep runs clean).
    if (app) await app.close();
  });

  it('folder delete tombstones its workspace file and the OBJECT dies', async () => {
    const folder = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${workspaceId}/folders`,
        headers,
        payload: { name: `Klasör ${Date.now()}` },
      })
    ).json();

    const init = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${workspaceId}/files`,
        headers,
        payload: {
          targetType: 'workspace',
          targetId: workspaceId,
          name: 'gerçek.txt',
          sizeBytes: 11, // ASCII body below — bytes must equal the declared size

          folderId: folder.id,
        },
      })
    ).json();
    const put = await fetch(init.upload.url, {
      method: 'PUT',
      headers: init.upload.headers,
      body: 'gercek veri', // 11 ASCII bytes — 'ç' would make chars ≠ bytes
    });
    expect(put.ok).toBe(true);
    const done = await app.inject({
      method: 'POST',
      url: `/api/v1/files/${init.file.id}/complete`,
      headers,
    });
    expect(done.statusCode).toBe(200);

    // Download works while alive.
    const read = (
      await app.inject({ method: 'GET', url: `/api/v1/files/${init.file.id}`, headers })
    ).json();
    expect((await fetch(read.downloadUrl)).ok).toBe(true);

    // Recursive delete: counted, and the OBJECT is gone once the GC drains.
    const del = (
      await app.inject({ method: 'DELETE', url: `/api/v1/folders/${folder.id}`, headers })
    ).json();
    expect(del).toEqual({ deletedFolders: 1, deletedFiles: 1 });

    // The object delete rides the queue (BullMQ — real Redis): poll until
    // the worker lands it, the files-upload suite's pattern.
    const key = `ws/${workspaceId}/${init.file.id}`;
    let head = { size: -1 };
    for (let attempt = 0; attempt < 40; attempt += 1) {
      head = await app.storage.head(key);
      if (head === null) break;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    expect(head).toBeNull(); // no orphaned bytes (ADR-0011 §5, extended)
  });
});
