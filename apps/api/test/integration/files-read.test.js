import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { storageTestEnv, ensureBucket } from '../helpers/minio.js';

// OPH-152 — read surface + cascade over REAL infrastructure: the aggregate
// project listing, a presigned download of real bytes, and a task delete whose
// cascade tombstones the file AND removes the object via the BullMQ worker.
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('integration: file read surface + cascade (MySQL + MinIO)', () => {
  let app;
  let headers;
  let workspaceId;
  let projectId;

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    app = await buildApp({ config });

    const reg = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `files-read-${Date.now()}@example.com`, password: 'integration-pass-1' },
    });
    const body = reg.json();
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    workspaceId = body.workspace.id;
    const project = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/projects`,
      headers,
      payload: { name: 'Aggregate' },
    });
    projectId = project.json().id;
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  async function uploadReady({ targetType, targetId, name, body }) {
    const init = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/files`,
      headers,
      payload: { targetType, targetId, name, sizeBytes: Buffer.byteLength(body) },
    });
    expect(init.statusCode).toBe(201);
    const { file, upload } = init.json();
    const put = await fetch(upload.url, { method: 'PUT', headers: upload.headers, body });
    expect(put.status).toBe(200);
    const complete = await app.inject({
      method: 'POST',
      url: `/api/v1/files/${file.id}/complete`,
      headers,
    });
    expect(complete.statusCode).toBe(200);
    return complete.json().file;
  }

  it('aggregates project files with sources and downloads real bytes', async () => {
    const task = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/tasks`,
      headers,
      payload: { title: 'Carrier', projectId },
    });
    const taskId = task.json().id;

    const onProject = await uploadReady({
      targetType: 'project',
      targetId: projectId,
      name: 'proje.txt',
      body: 'project bytes',
    });
    const onTask = await uploadReady({
      targetType: 'task',
      targetId: taskId,
      name: 'görev.txt',
      body: 'task bytes',
    });

    const aggregate = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${workspaceId}/files?projectId=${projectId}`,
      headers,
    });
    const files = aggregate.json().files;
    expect(files.map((f) => f.id).sort()).toEqual([onProject.id, onTask.id].sort());
    expect(files.find((f) => f.id === onTask.id).source).toMatchObject({
      type: 'task',
      title: 'Carrier',
    });

    const meta = await app.inject({
      method: 'GET',
      url: `/api/v1/files/${onTask.id}`,
      headers,
    });
    const res = await fetch(meta.json().downloadUrl);
    expect(await res.text()).toBe('task bytes');
    expect(res.headers.get('content-disposition')).toContain(`filename*=UTF-8''g%C3%B6rev.txt`);

    // Cascade: deleting the task tombstones its file, syncs the delete, and
    // the queued worker removes the object from the bucket.
    const del = await app.inject({ method: 'DELETE', url: `/api/v1/tasks/${taskId}`, headers });
    expect(del.statusCode).toBe(204);

    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${workspaceId}&sinceRevision=0`,
      headers,
    });
    const change = pull
      .json()
      .changes.find((c) => c.entityType === 'file' && c.entityId === onTask.id);
    expect(change.operation).toBe('delete');
    expect(change.data).toBeNull();

    const key = `ws/${workspaceId}/${onTask.id}`;
    let gone = null;
    for (let attempt = 0; attempt < 40; attempt += 1) {
      gone = await app.storage.head(key);
      if (gone === null) break;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    expect(gone).toBeNull();

    // The project's own file is untouched by the task cascade.
    expect(await app.storage.head(`ws/${workspaceId}/${onProject.id}`)).not.toBeNull();
  });
});
