import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fakeStorage } from '../helpers/fakestorage.js';

/**
 * OPH-169 — folders + standalone workspace files (ADR-0014): tree CRUD with
 * depth/cycle/name guards, the counted recursive delete (files tombstoned +
 * object GC queued), workspace-target uploads, and the push-pull sync entity.
 */
describe('folders (OPH-169, ADR-0014)', () => {
  let app;
  let tables;
  let owner;
  let storage;

  beforeEach(async () => {
    storage = fakeStorage();
    ({ app, tables } = await buildTestApp({ storage }));
    owner = await registerUser(app, { email: 'owner@example.com' });
  });

  const create = (name, parentId) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/folders`,
      headers: owner.headers,
      payload: { name, ...(parentId ? { parentId } : {}) },
    });

  const patch = (id, body) =>
    app.inject({
      method: 'PATCH',
      url: `/api/v1/folders/${id}`,
      headers: owner.headers,
      payload: body,
    });

  const uploadReadyFile = async (name, folderId) => {
    const init = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/files`,
      headers: owner.headers,
      payload: {
        targetType: 'workspace',
        targetId: owner.workspace.id,
        name,
        sizeBytes: 64,
        ...(folderId ? { folderId } : {}),
      },
    });
    expect(init.statusCode).toBe(201);
    const fileId = init.json().file.id;
    // "The client PUT the bytes": seed the object at the file's storage key.
    storage.objects.set(`ws/${owner.workspace.id}/${fileId}`, 64);
    const done = await app.inject({
      method: 'POST',
      url: `/api/v1/files/${fileId}/complete`,
      headers: owner.headers,
    });
    expect(done.statusCode).toBe(200);
    return init.json().file;
  };

  it('creates a tree, renames and moves with cycle/depth/name guards', async () => {
    const root = (await create('Belgeler')).json();
    expect(root.parentId).toBeNull();
    const child = (await create('Faturalar', root.id)).json();
    expect(child.parentId).toBe(root.id);

    // Same-level duplicate names refuse — case/accent-insensitively (Finder
    // semantics; the root level is API-guarded since NULLs escape the index).
    expect((await create('belgeler')).statusCode).toBe(409);
    expect((await create('Faturalar', root.id)).statusCode).toBe(409);
    // Same name on a DIFFERENT level is fine.
    expect((await create('Belgeler', root.id)).statusCode).toBe(201);

    // Rename + move.
    const renamed = (await patch(child.id, { name: 'Arşiv' })).json();
    expect(renamed.name).toBe('Arşiv');
    const moved = (await patch(child.id, { parentId: null })).json();
    expect(moved.parentId).toBeNull();

    // A folder cannot move into its own subtree.
    const inner = (await create('İç', child.id)).json();
    const cycle = await patch(child.id, { parentId: inner.id });
    expect(cycle.statusCode).toBe(400);
    expect(cycle.json().code).toBe('FOLDER_CYCLE');

    // Depth is capped at 10.
    let parent = null;
    for (let i = 0; i < 10; i += 1) {
      const res = await create(`Seviye ${i}`, parent);
      expect(res.statusCode).toBe(201);
      parent = res.json().id;
    }
    const tooDeep = await create('Seviye 10', parent);
    expect(tooDeep.statusCode).toBe(400);
    expect(tooDeep.json().code).toBe('FOLDER_TOO_DEEP');
  });

  it('workspace files: init/list per folder level, folderId rules enforced', async () => {
    const folder = (await create('Belgeler')).json();
    const rootFile = await uploadReadyFile('kök.txt');
    const inFolder = await uploadReadyFile('içeride.txt', folder.id);
    expect(inFolder.folderId).toBe(folder.id);

    // Root level = folderless files only.
    const rootList = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/files?targetType=workspace&targetId=${owner.workspace.id}`,
      headers: owner.headers,
    });
    expect(rootList.json().files.map((f) => f.id)).toEqual([rootFile.id]);

    // One folder level.
    const folderList = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/files?targetType=workspace&targetId=${owner.workspace.id}&folderId=${folder.id}`,
      headers: owner.headers,
    });
    expect(folderList.json().files.map((f) => f.id)).toEqual([inFolder.id]);

    // folderId is workspace-target-only; attached files never fold in.
    const bad = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/files`,
      headers: owner.headers,
      payload: {
        targetType: 'task',
        targetId: owner.workspace.id,
        name: 'x.txt',
        sizeBytes: 1,
        folderId: folder.id,
      },
    });
    expect(bad.statusCode).toBe(400);
    expect(bad.json().code).toBe('FILE_FOLDER_NOT_ALLOWED');

    // A workspace target must BE the workspace.
    const wrongTarget = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/files`,
      headers: owner.headers,
      payload: {
        targetType: 'workspace',
        targetId: 'X'.repeat(26),
        name: 'x.txt',
        sizeBytes: 1,
      },
    });
    expect(wrongTarget.statusCode).toBe(400);
  });

  it('recursive delete counts the blast radius, tombstones files and queues GC', async () => {
    const root = (await create('Silinecek')).json();
    const child = (await create('Alt', root.id)).json();
    await uploadReadyFile('a.txt', root.id);
    const fileB = await uploadReadyFile('b.txt', child.id);
    await uploadReadyFile('dokunulmaz.txt'); // root-level, OUTSIDE the subtree

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/folders/${root.id}`,
      headers: owner.headers,
    });
    expect(res.json()).toEqual({ deletedFolders: 2, deletedFiles: 2 });

    const liveFolders = tables.folders.filter((f) => f.deleted_at == null);
    expect(liveFolders).toHaveLength(0);
    const liveFiles = tables.files.filter((f) => f.deleted_at == null);
    expect(liveFiles.map((f) => f.name)).toEqual(['dokunulmaz.txt']);
    // Objects for the dead files are on the GC queue (fake storage records
    // removals as the inline queue drains them).
    await app.storageGc.idle();
    expect(storage.removed).toContain(`ws/${owner.workspace.id}/${fileB.id}`);
  });

  it('syncs as a push-pull entity: offline create/move/delete round-trip', async () => {
    const clientId = 'C'.repeat(26);
    const push = (mutations) =>
      app.inject({
        method: 'POST',
        url: '/api/v1/sync/push',
        headers: owner.headers,
        payload: { workspaceId: owner.workspace.id, clientId, baseRevision: 0, mutations },
      });

    // Crockford base32 excludes I/L/O/U — the OPH-156 fake-ULID lesson.
    const idA = '01FDRAAA'.padEnd(26, '0');
    const idB = '01FDRBBB'.padEnd(26, '0');
    const created = await push([
      {
        clientMutationId: 'M1'.padEnd(26, '0'),
        entityType: 'folder',
        entityId: idA,
        operation: 'create',
        patch: { name: 'Cepten Klasör' },
        localUpdatedAt: new Date().toISOString(),
      },
      {
        clientMutationId: 'M2'.padEnd(26, '0'),
        entityType: 'folder',
        entityId: idB,
        operation: 'create',
        patch: { name: 'Alt Klasör', parentId: idA },
        localUpdatedAt: new Date().toISOString(),
      },
    ]);
    expect(created.json().results.map((r) => r.status)).toEqual(['applied', 'applied']);

    // Guards hold over push too: cycle refused with a coded error.
    const cycle = await push([
      {
        clientMutationId: 'M3'.padEnd(26, '0'),
        entityType: 'folder',
        entityId: idA,
        operation: 'update',
        patch: { parentId: idB },
        localUpdatedAt: new Date().toISOString(),
      },
    ]);
    expect(cycle.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'FOLDER_CYCLE',
    });

    // Pull replicates the tree.
    const pull = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=0`,
      headers: owner.headers,
    });
    const folderChanges = pull
      .json()
      .changes.filter((c) => c.entityType === 'folder' && c.operation !== 'delete');
    expect(folderChanges.map((c) => c.data.name).sort()).toEqual(['Alt Klasör', 'Cepten Klasör']);

    // Deleting the root over push cascades the child too (customDelete).
    const del = await push([
      {
        clientMutationId: 'M4'.padEnd(26, '0'),
        entityType: 'folder',
        entityId: idA,
        operation: 'delete',
        localUpdatedAt: new Date().toISOString(),
      },
    ]);
    expect(del.json().results[0].status).toBe('applied');
    expect(tables.folders.filter((f) => f.deleted_at == null)).toHaveLength(0);
  });
});
