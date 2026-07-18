import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { storageTestEnv, ensureBucket } from '../helpers/minio.js';

// OPH-151 — the full upload lifecycle over REAL infrastructure: MySQL rows,
// MinIO objects, actual presigned PUTs (ATTACHMENTS.md §12). What passes here
// is byte-for-byte what R2 will see.
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('integration: file upload lifecycle (MySQL + MinIO)', () => {
  let app;
  let headers;
  let workspaceId;
  let projectId;

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    app = await buildApp({ config });

    const email = `files-int-${Date.now()}@example.com`;
    const reg = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'integration-pass-1' },
    });
    expect(reg.statusCode).toBe(201);
    const body = reg.json();
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    workspaceId = body.workspace.id;

    const project = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/projects`,
      headers,
      payload: { name: 'Attachment integration' },
    });
    expect(project.statusCode).toBe(201);
    projectId = project.json().id;
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  async function initUpload(payloadOverrides = {}) {
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/files`,
      headers,
      payload: {
        targetType: 'project',
        targetId: projectId,
        name: 'Özet raporu.txt',
        sizeBytes: 26,
        mime: 'text/plain',
        ...payloadOverrides,
      },
    });
    expect(res.statusCode).toBe(201);
    return res.json();
  }

  it('init → presigned PUT → complete: row ready, revision recorded', async () => {
    const body = 'twenty-six bytes exactly!!';
    expect(Buffer.byteLength(body)).toBe(26);
    const init = await initUpload();

    const put = await fetch(init.upload.url, {
      method: 'PUT',
      headers: init.upload.headers,
      body,
    });
    expect(put.status).toBe(200);

    const complete = await app.inject({
      method: 'POST',
      url: `/api/v1/files/${init.file.id}/complete`,
      headers,
    });
    expect(complete.statusCode).toBe(200);
    expect(complete.json().file.status).toBe('ready');

    const row = await app.db('files').where({ id: init.file.id }).first();
    expect(row.status).toBe('ready');
    const log = await app
      .db('sync_revisions')
      .where({ workspace_id: workspaceId, entity_type: 'file', entity_id: init.file.id })
      .select();
    expect(log).toHaveLength(1);
    expect(log[0].operation).toBe('create');
    expect(Number(row.revision)).toBe(Number(log[0].revision));
  });

  it('a mismatched upload is destroyed: object deleted, row gone', async () => {
    const init = await initUpload({ name: 'liar.bin', sizeBytes: 1000 });
    const put = await fetch(init.upload.url, {
      method: 'PUT',
      headers: init.upload.headers,
      body: 'way fewer bytes',
    });
    expect(put.status).toBe(200);

    const complete = await app.inject({
      method: 'POST',
      url: `/api/v1/files/${init.file.id}/complete`,
      headers,
    });
    expect(complete.statusCode).toBe(409);
    expect(complete.json().code).toBe('FILE_UPLOAD_MISMATCH');

    expect(await app.db('files').where({ id: init.file.id }).first()).toBeUndefined();
    expect(await app.storage.head(`ws/${workspaceId}/${init.file.id}`)).toBeNull();
  });

  it('deleting a ready file tombstones the row and removes the object', async () => {
    const body = 'twenty-six bytes exactly!!';
    const init = await initUpload({ name: 'to-delete.txt' });
    await fetch(init.upload.url, { method: 'PUT', headers: init.upload.headers, body });
    await app.inject({
      method: 'POST',
      url: `/api/v1/files/${init.file.id}/complete`,
      headers,
    });

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/files/${init.file.id}`,
      headers,
    });
    expect(del.statusCode).toBe(204);

    const row = await app.db('files').where({ id: init.file.id }).first();
    expect(row.deleted_at).not.toBeNull();

    // The object delete rides the queue (BullMQ here — real Redis): poll
    // until the worker lands it, like the calendar integration tests do.
    const key = `ws/${workspaceId}/${init.file.id}`;
    let gone = null;
    for (let attempt = 0; attempt < 40; attempt += 1) {
      gone = await app.storage.head(key);
      if (gone === null) break;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    expect(gone).toBeNull();
  });
});
