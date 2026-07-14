import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

let app;
let owner;

beforeEach(async () => {
  ({ app } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const pull = (qs, headers = owner.headers) =>
  app.inject({ method: 'GET', url: `/api/v1/sync/pull?${qs}`, headers });

const api = (method, url, payload) => app.inject({ method, url, headers: owner.headers, payload });

describe('GET /sync/pull (OPH-051)', () => {
  it('returns snapshots for live entities and tombstones for deleted ones', async () => {
    const project = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/projects`, { name: 'Yolculuk' })
    ).json(); // rev 1
    const tag = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tags`, { name: 'acil' })
    ).json(); // rev 2
    const task = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
        title: 'Bilet al',
        projectId: project.id,
        tagIds: [tag.id],
      })
    ).json(); // rev 3
    await api('POST', `/api/v1/workspaces/${owner.workspace.id}/notes`, {
      title: 'Plan',
      contentDelta: [{ insert: 'içerik\n' }],
    }); // rev 4
    await api('DELETE', `/api/v1/tags/${tag.id}`); // rev 5 (delete)

    const res = await pull(`workspaceId=${owner.workspace.id}&sinceRevision=0`);
    expect(res.statusCode).toBe(200);
    const body = res.json();

    expect(body).toMatchObject({
      workspaceId: owner.workspace.id,
      fromRevision: 0,
      toRevision: 5,
      hasMore: false,
    });
    expect(body.changes.map((c) => [c.entityType, c.operation])).toEqual([
      ['project', 'create'],
      ['task', 'create'],
      ['note', 'create'],
      ['tag', 'delete'],
    ]);

    const taskChange = body.changes.find((c) => c.entityType === 'task');
    expect(taskChange.data).toMatchObject({ id: task.id, title: 'Bilet al', tagIds: [tag.id] });
    const noteChange = body.changes.find((c) => c.entityType === 'note');
    expect(noteChange.data.contentDelta).toEqual([{ insert: 'içerik\n' }]);
    expect(noteChange.data.plainText).toBe('içerik');
    const tombstone = body.changes.find((c) => c.entityType === 'tag');
    expect(tombstone).toMatchObject({ entityId: tag.id, operation: 'delete', data: null });
  });

  it('coalesces multiple changes of one entity into its latest snapshot', async () => {
    const task = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, { title: 'v1' })
    ).json();
    await api('PATCH', `/api/v1/tasks/${task.id}`, { title: 'v2' });
    await api('PATCH', `/api/v1/tasks/${task.id}`, { title: 'v3', priority: 'high' });

    const body = (await pull(`workspaceId=${owner.workspace.id}&sinceRevision=0`)).json();
    const taskChanges = body.changes.filter((c) => c.entityId === task.id);
    expect(taskChanges).toHaveLength(1);
    expect(taskChanges[0]).toMatchObject({ revision: 3, operation: 'update' });
    expect(taskChanges[0].data).toMatchObject({ title: 'v3', priority: 'high', revision: 3 });
  });

  it('pages with hasMore and resumes from toRevision; deletes past the window tombstone early', async () => {
    const first = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, { title: 'kalıcı' })
    ).json(); // rev 1
    const doomed = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/notes`, { title: 'silinecek' })
    ).json(); // rev 2
    await api('PATCH', `/api/v1/notes/${doomed.id}`, { title: 'hala silinecek' }); // rev 3
    await api('DELETE', `/api/v1/notes/${doomed.id}`); // rev 4

    const page1 = (await pull(`workspaceId=${owner.workspace.id}&sinceRevision=0&limit=3`)).json();
    expect(page1.hasMore).toBe(true);
    expect(page1.toRevision).toBe(3);
    // The note's delete sits past the window, but the snapshot is already
    // soft-deleted — the client must see a tombstone, not stale live data.
    const noteChange = page1.changes.find((c) => c.entityId === doomed.id);
    expect(noteChange).toMatchObject({ operation: 'delete', data: null });
    expect(page1.changes.find((c) => c.entityId === first.id).data.title).toBe('kalıcı');

    const page2 = (await pull(`workspaceId=${owner.workspace.id}&sinceRevision=3&limit=3`)).json();
    expect(page2.hasMore).toBe(false);
    expect(page2.toRevision).toBe(4);
    expect(page2.changes).toEqual([
      { revision: 4, entityType: 'note', entityId: doomed.id, operation: 'delete', data: null },
    ]);
  });

  it('returns an empty batch when the client is current', async () => {
    const body = (await pull(`workspaceId=${owner.workspace.id}&sinceRevision=0`)).json();
    expect(body).toMatchObject({ fromRevision: 0, toRevision: 0, hasMore: false, changes: [] });
  });

  it('includes reminder and checklist_item entities produced by task writes', async () => {
    const task = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
        title: 'Alarmlı',
        remindAt: '2030-05-01T09:00:00.000Z',
      })
    ).json(); // rev 1 (task) + rev 2 (reminder create)
    await api('POST', `/api/v1/tasks/${task.id}/checklist`, { title: 'adım 1' }); // rev 3

    const body = (await pull(`workspaceId=${owner.workspace.id}&sinceRevision=0`)).json();
    const types = body.changes.map((c) => c.entityType).sort();
    expect(types).toEqual(['checklist_item', 'reminder', 'task']);
    const reminder = body.changes.find((c) => c.entityType === 'reminder');
    expect(reminder.data).toMatchObject({
      taskId: task.id,
      status: 'scheduled',
      remindAt: '2030-05-01T09:00:00.000Z',
    });
    const item = body.changes.find((c) => c.entityType === 'checklist_item');
    expect(item.data).toMatchObject({ taskId: task.id, title: 'adım 1', isDone: false });
  });

  it('denies non-members', async () => {
    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const res = await pull(`workspaceId=${owner.workspace.id}&sinceRevision=0`, outsider.headers);
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('AUTH_WORKSPACE_FORBIDDEN');
  });
});
