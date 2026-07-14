import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const createTask = async (payload = { title: 'Görev' }) => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
    headers: owner.headers,
    payload,
  });
  expect(res.statusCode).toBe(201);
  return res.json();
};

const post = (taskId, action) =>
  app.inject({ method: 'POST', url: `/api/v1/tasks/${taskId}/${action}`, headers: owner.headers });

const patchTask = (taskId, payload) =>
  app.inject({ method: 'PATCH', url: `/api/v1/tasks/${taskId}`, headers: owner.headers, payload });

describe('POST /tasks/:id/complete & /reopen (OPH-033)', () => {
  it('complete sets completed_at; reopen clears it', async () => {
    const task = await createTask();

    const completed = await post(task.id, 'complete');
    expect(completed.statusCode).toBe(200);
    expect(completed.json().status).toBe('completed');
    expect(completed.json().completedAt).toBeTruthy();
    expect(completed.json().revision).toBe(2);

    const reopened = await post(task.id, 'reopen');
    expect(reopened.statusCode).toBe(200);
    expect(reopened.json()).toMatchObject({ status: 'open', completedAt: null, revision: 3 });
  });

  it('complete is idempotent — the second call burns no revision', async () => {
    const task = await createTask();
    await post(task.id, 'complete');
    const syncRowsBefore = tables.sync_revisions.length;

    const again = await post(task.id, 'complete');
    expect(again.statusCode).toBe(200);
    expect(again.json().status).toBe('completed');
    expect(tables.sync_revisions).toHaveLength(syncRowsBefore);
  });

  it('reopen works from cancelled but rejects non-terminal statuses', async () => {
    const task = await createTask();
    await patchTask(task.id, { status: 'cancelled' });
    expect((await post(task.id, 'reopen')).json().status).toBe('open');

    const invalid = await post(task.id, 'reopen'); // already open
    expect(invalid.statusCode).toBe(409);
    expect(invalid.json()).toMatchObject({ code: 'TASK_INVALID_TRANSITION' });
  });

  it('completing via PATCH status also maintains completed_at', async () => {
    const task = await createTask();

    const done = await patchTask(task.id, { status: 'completed' });
    expect(done.json().completedAt).toBeTruthy();

    const undone = await patchTask(task.id, { status: 'in_progress' });
    expect(undone.json().completedAt).toBeNull();
  });
});

describe('archived immutability (OPH-033)', () => {
  it('blocks every write on an archived task except unarchiving', async () => {
    const task = await createTask();
    const item = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/checklist`,
        headers: owner.headers,
        payload: { title: 'Adım' },
      })
    ).json();
    await patchTask(task.id, { status: 'archived' });

    const writes = await Promise.all([
      patchTask(task.id, { title: 'Yeni başlık' }),
      patchTask(task.id, { status: 'open', title: 'sneaky' }), // unarchive must be lone
      post(task.id, 'complete'),
      post(task.id, 'reopen'),
      app.inject({
        method: 'PUT',
        url: `/api/v1/tasks/${task.id}/tags`,
        headers: owner.headers,
        payload: { tagIds: [] },
      }),
      app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/checklist`,
        headers: owner.headers,
        payload: { title: 'Nope' },
      }),
      app.inject({
        method: 'PATCH',
        url: `/api/v1/tasks/${task.id}/checklist/${item.id}`,
        headers: owner.headers,
        payload: { isDone: true },
      }),
      app.inject({
        method: 'DELETE',
        url: `/api/v1/tasks/${task.id}/checklist/${item.id}`,
        headers: owner.headers,
      }),
    ]);
    for (const res of writes) {
      expect(res.statusCode).toBe(409);
      expect(res.json()).toMatchObject({ code: 'TASK_ARCHIVED' });
    }

    // The single allowed write: a lone status change away from archived.
    const unarchived = await patchTask(task.id, { status: 'open' });
    expect(unarchived.statusCode).toBe(200);
    expect(unarchived.json().status).toBe('open');

    // Soft delete of an archived task stays allowed (cleanup path).
    await patchTask(task.id, { status: 'archived' });
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
  });
});
