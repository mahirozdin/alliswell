import { describe, it, expect } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fakeStorage } from '../helpers/fakestorage.js';

// OPH-152 — read surface, pull-only sync, cascade cleanup, rename, usage
// (ATTACHMENTS.md §§4-6).

const CID = (n) => `01ARZ3NDEKTSV4RRFFQ69G5F${String(n).padStart(2, '0')}`.slice(0, 26);

async function setup() {
  const store = fakeStorage();
  const { app, tables } = await buildTestApp({ storage: store });
  const session = await registerUser(app, { email: `read-${Math.random()}@example.com` });
  const project = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${session.workspace.id}/projects`,
    headers: session.headers,
    payload: { name: 'Read project' },
  });
  return { app, tables, store, session, projectId: project.json().id };
}

/** init + fake PUT + complete → a READY file on the target. */
async function readyFile(ctx, { targetType, targetId, name = 'file.bin', size = 100 }) {
  const init = await ctx.app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ctx.session.workspace.id}/files`,
    headers: ctx.session.headers,
    payload: { targetType, targetId, name, sizeBytes: size },
  });
  expect(init.statusCode).toBe(201);
  const { file } = init.json();
  ctx.store.objects.set(`ws/${ctx.session.workspace.id}/${file.id}`, size);
  const complete = await ctx.app.inject({
    method: 'POST',
    url: `/api/v1/files/${file.id}/complete`,
    headers: ctx.session.headers,
  });
  expect(complete.statusCode).toBe(200);
  return complete.json().file;
}

async function makeTask(ctx, payload) {
  const res = await ctx.app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ctx.session.workspace.id}/tasks`,
    headers: ctx.session.headers,
    payload,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

async function makeNote(ctx, payload) {
  const res = await ctx.app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ctx.session.workspace.id}/notes`,
    headers: ctx.session.headers,
    payload,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

describe('GET /files/:id', () => {
  it('mints a download URL for ready files, none while uploading', async () => {
    const ctx = await setup();
    const ready = await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId });

    const res = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/files/${ready.id}`,
      headers: ctx.session.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().file.status).toBe('ready');
    expect(res.json().downloadUrl).toContain(
      `https://fake-store/get/ws/${ctx.session.workspace.id}/${ready.id}`,
    );
    expect(res.json().downloadExpiresAt).toBeTruthy();

    const uploading = await ctx.app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files`,
      headers: ctx.session.headers,
      payload: { targetType: 'project', targetId: ctx.projectId, name: 'up.bin', sizeBytes: 5 },
    });
    const pending = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/files/${uploading.json().file.id}`,
      headers: ctx.session.headers,
    });
    expect(pending.json().downloadUrl).toBeNull();
    expect(pending.json().downloadExpiresAt).toBeNull();
    await ctx.app.close();
  });
});

describe('GET /workspaces/:id/files', () => {
  it('lists one target and aggregates a whole project with sources', async () => {
    const ctx = await setup();
    const task = await makeTask(ctx, { title: 'In project', projectId: ctx.projectId });
    const note = await makeNote(ctx, { title: 'Project note', projectId: ctx.projectId });
    const otherTask = await makeTask(ctx, { title: 'Elsewhere' }); // no project

    const onProject = await readyFile(ctx, {
      targetType: 'project',
      targetId: ctx.projectId,
      name: 'p.bin',
    });
    const onTask = await readyFile(ctx, { targetType: 'task', targetId: task.id, name: 't.bin' });
    const onNote = await readyFile(ctx, { targetType: 'note', targetId: note.id, name: 'n.bin' });
    await readyFile(ctx, { targetType: 'task', targetId: otherTask.id, name: 'x.bin' });

    const byTarget = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files?targetType=task&targetId=${task.id}`,
      headers: ctx.session.headers,
    });
    expect(byTarget.json().files.map((f) => f.id)).toEqual([onTask.id]);

    const aggregate = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files?projectId=${ctx.projectId}`,
      headers: ctx.session.headers,
    });
    const files = aggregate.json().files;
    expect(files.map((f) => f.id).sort()).toEqual([onProject.id, onTask.id, onNote.id].sort());
    const sourceOf = Object.fromEntries(files.map((f) => [f.id, f.source]));
    expect(sourceOf[onProject.id]).toEqual({
      type: 'project',
      id: ctx.projectId,
      title: 'Read project',
    });
    expect(sourceOf[onTask.id]).toEqual({ type: 'task', id: task.id, title: 'In project' });
    expect(sourceOf[onNote.id]).toEqual({ type: 'note', id: note.id, title: 'Project note' });
    await ctx.app.close();
  });

  it('rejects a partial target query and unknown projects', async () => {
    const ctx = await setup();
    const partial = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files?targetType=task`,
      headers: ctx.session.headers,
    });
    expect(partial.statusCode).toBe(400);
    expect(partial.json().code).toBe('FILE_INVALID_TARGET');

    const ghost = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files?projectId=01ARZ3NDEKTSV4RRFFQ69G5FAV`,
      headers: ctx.session.headers,
    });
    expect(ghost.statusCode).toBe(404);
    expect(ghost.json().code).toBe('PROJECT_NOT_FOUND');
    await ctx.app.close();
  });
});

describe('usage', () => {
  it('sums ready bytes only', async () => {
    const ctx = await setup();
    await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId, size: 100 });
    await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId, name: 'b', size: 250 });
    await ctx.app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files`,
      headers: ctx.session.headers,
      payload: { targetType: 'project', targetId: ctx.projectId, name: 'up.bin', sizeBytes: 999 },
    });

    const res = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files/usage`,
      headers: ctx.session.headers,
    });
    expect(res.json()).toEqual({ totalBytes: 350, fileCount: 2 });
    await ctx.app.close();
  });
});

describe('PATCH /files/:id (rename)', () => {
  it('renames ready files with a sync update revision', async () => {
    const ctx = await setup();
    const file = await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId });
    const res = await ctx.app.inject({
      method: 'PATCH',
      url: `/api/v1/files/${file.id}`,
      headers: ctx.session.headers,
      payload: { name: 'Yeni isim.bin' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().file.name).toBe('Yeni isim.bin');
    expect(res.json().file.revision).toBeGreaterThan(file.revision);

    const log = ctx.tables.sync_revisions.filter(
      (r) => r.entity_type === 'file' && r.operation === 'update',
    );
    expect(log).toHaveLength(1);
    expect(JSON.parse(log[0].changed_fields)).toEqual(['name']);
    await ctx.app.close();
  });

  it('refuses uploading files and bad names', async () => {
    const ctx = await setup();
    const init = await ctx.app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files`,
      headers: ctx.session.headers,
      payload: { targetType: 'project', targetId: ctx.projectId, name: 'up.bin', sizeBytes: 5 },
    });
    const pending = await ctx.app.inject({
      method: 'PATCH',
      url: `/api/v1/files/${init.json().file.id}`,
      headers: ctx.session.headers,
      payload: { name: 'x.bin' },
    });
    expect(pending.statusCode).toBe(409);
    expect(pending.json().code).toBe('FILE_NOT_READY');

    const ready = await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId });
    const bad = await ctx.app.inject({
      method: 'PATCH',
      url: `/api/v1/files/${ready.id}`,
      headers: ctx.session.headers,
      payload: { name: '..' },
    });
    expect(bad.statusCode).toBe(400);
    expect(bad.json().code).toBe('FILE_NAME_INVALID');
    await ctx.app.close();
  });
});

describe('sync: pull-only file entity', () => {
  it('pulls creates as snapshots and deletes as tombstones', async () => {
    const ctx = await setup();
    const file = await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId });

    const pull = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ctx.session.workspace.id}&sinceRevision=0`,
      headers: ctx.session.headers,
    });
    const change = pull.json().changes.find((c) => c.entityType === 'file');
    expect(change.operation).toBe('create');
    expect(change.data).toMatchObject({
      id: file.id,
      targetType: 'project',
      name: 'file.bin',
      status: 'ready',
    });

    await ctx.app.inject({
      method: 'DELETE',
      url: `/api/v1/files/${file.id}`,
      headers: ctx.session.headers,
    });
    const pull2 = await ctx.app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ctx.session.workspace.id}&sinceRevision=0`,
      headers: ctx.session.headers,
    });
    const change2 = pull2.json().changes.find((c) => c.entityType === 'file');
    expect(change2.operation).toBe('delete');
    expect(change2.data).toBeNull();
    await ctx.app.close();
  });

  it('refuses pushed file mutations: the write path not existing IS the guarantee', async () => {
    const ctx = await setup();
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: ctx.session.headers,
      payload: {
        clientId: CID(1),
        workspaceId: ctx.session.workspace.id,
        baseRevision: 0,
        mutations: [
          {
            clientMutationId: CID(2),
            entityType: 'file',
            entityId: CID(3),
            operation: 'create',
            patch: { name: 'hack.bin' },
          },
        ],
      },
    });
    expect(res.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNSUPPORTED_ENTITY',
    });
    await ctx.app.close();
  });
});

describe('cascade: entities take their files with them', () => {
  it('task subtree delete tombstones every attached file and queues objects', async () => {
    const ctx = await setup();
    const parent = await makeTask(ctx, { title: 'Parent' });
    const child = await makeTask(ctx, { title: 'Child', parentTaskId: parent.id });
    const f1 = await readyFile(ctx, { targetType: 'task', targetId: parent.id, name: 'p.bin' });
    const f2 = await readyFile(ctx, { targetType: 'task', targetId: child.id, name: 'c.bin' });

    const res = await ctx.app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${parent.id}`,
      headers: ctx.session.headers,
    });
    expect(res.statusCode).toBe(204);
    await ctx.app.storageGc.idle();

    for (const f of [f1, f2]) {
      const row = ctx.tables.files.find((r) => r.id === f.id);
      expect(row.deleted_at).not.toBeNull();
      expect(ctx.store.removed).toContain(`ws/${ctx.session.workspace.id}/${f.id}`);
      expect(
        ctx.tables.sync_revisions.some(
          (r) => r.entity_type === 'file' && r.entity_id === f.id && r.operation === 'delete',
        ),
      ).toBe(true);
    }
    await ctx.app.close();
  });

  it('an uploading leftover on a deleted task is hard-deleted (no tombstone)', async () => {
    const ctx = await setup();
    const task = await makeTask(ctx, { title: 'Doomed' });
    const init = await ctx.app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ctx.session.workspace.id}/files`,
      headers: ctx.session.headers,
      payload: { targetType: 'task', targetId: task.id, name: 'half.bin', sizeBytes: 10 },
    });
    const fileId = init.json().file.id;

    await ctx.app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${task.id}`,
      headers: ctx.session.headers,
    });
    await ctx.app.storageGc.idle();
    expect(ctx.tables.files.find((r) => r.id === fileId)).toBeUndefined();
    expect(ctx.store.removed).toContain(`ws/${ctx.session.workspace.id}/${fileId}`);
    expect(ctx.tables.sync_revisions.some((r) => r.entity_id === fileId)).toBe(false);
    await ctx.app.close();
  });

  it('note delete cascades; project delete touches only project-targeted files', async () => {
    const ctx = await setup();
    const note = await makeNote(ctx, { title: 'Doomed note', projectId: ctx.projectId });
    const task = await makeTask(ctx, { title: 'Survivor', projectId: ctx.projectId });
    const onNote = await readyFile(ctx, { targetType: 'note', targetId: note.id, name: 'n.bin' });
    const onProject = await readyFile(ctx, {
      targetType: 'project',
      targetId: ctx.projectId,
      name: 'p.bin',
    });
    const onTask = await readyFile(ctx, { targetType: 'task', targetId: task.id, name: 't.bin' });

    await ctx.app.inject({
      method: 'DELETE',
      url: `/api/v1/notes/${note.id}`,
      headers: ctx.session.headers,
    });
    expect(ctx.tables.files.find((r) => r.id === onNote.id).deleted_at).not.toBeNull();

    await ctx.app.inject({
      method: 'DELETE',
      url: `/api/v1/projects/${ctx.projectId}`,
      headers: ctx.session.headers,
    });
    expect(ctx.tables.files.find((r) => r.id === onProject.id).deleted_at).not.toBeNull();
    // The task itself was not deleted — its file lives.
    expect(ctx.tables.files.find((r) => r.id === onTask.id).deleted_at ?? null).toBeNull();
    await ctx.app.close();
  });

  it('sync-push deletes cascade exactly like REST', async () => {
    const ctx = await setup();
    const task = await makeTask(ctx, { title: 'Pushed away' });
    const file = await readyFile(ctx, { targetType: 'task', targetId: task.id });

    const res = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: ctx.session.headers,
      payload: {
        clientId: CID(4),
        workspaceId: ctx.session.workspace.id,
        baseRevision: 0,
        mutations: [
          {
            clientMutationId: CID(5),
            entityType: 'task',
            entityId: task.id,
            operation: 'delete',
          },
        ],
      },
    });
    expect(res.json().results[0].status).toBe('applied');
    await ctx.app.storageGc.idle();
    expect(ctx.tables.files.find((r) => r.id === file.id).deleted_at).not.toBeNull();
    expect(ctx.store.removed).toContain(`ws/${ctx.session.workspace.id}/${file.id}`);
    await ctx.app.close();
  });

  it('archiving a project deletes no files', async () => {
    const ctx = await setup();
    const file = await readyFile(ctx, { targetType: 'project', targetId: ctx.projectId });
    const res = await ctx.app.inject({
      method: 'POST',
      url: `/api/v1/projects/${ctx.projectId}/archive`,
      headers: ctx.session.headers,
      payload: { includeTasks: true, includeNotes: true },
    });
    expect(res.statusCode).toBe(200);
    expect(ctx.tables.files.find((r) => r.id === file.id).deleted_at ?? null).toBeNull();
    expect(ctx.store.removed).toHaveLength(0);
    await ctx.app.close();
  });
});
