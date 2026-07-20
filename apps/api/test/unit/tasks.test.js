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

const wsUrl = (path = '') => `/api/v1/workspaces/${owner.workspace.id}/tasks${path}`;

const createTask = (payload, headers = owner.headers) =>
  app.inject({ method: 'POST', url: wsUrl(), headers, payload });

const listTasks = (qs = '', headers = owner.headers) =>
  app.inject({ method: 'GET', url: wsUrl(qs), headers });

describe('POST /workspaces/:wsId/tasks (OPH-032)', () => {
  it('creates with defaults and records the sync revision', async () => {
    const res = await createTask({ title: 'Yarın sunum hazırla' });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body).toMatchObject({
      title: 'Yarın sunum hazırla',
      status: 'open',
      priority: 'none',
      projectId: null,
      parentTaskId: null,
      tagIds: [],
      checklist: [],
      revision: 1,
    });
    expect(tables.sync_revisions.at(-1)).toMatchObject({
      entity_type: 'task',
      operation: 'create',
    });
  });

  it('validates project, parent and tag references against the workspace', async () => {
    const foreign = await registerUser(app, { email: 'foreign@example.com' });
    const foreignProject = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${foreign.workspace.id}/projects`,
        headers: foreign.headers,
        payload: { name: 'Theirs' },
      })
    ).json();

    const badProject = await createTask({ title: 'X', projectId: foreignProject.id });
    expect(badProject.statusCode).toBe(400);
    expect(badProject.json()).toMatchObject({ code: 'TASK_INVALID_PROJECT' });

    const badParent = await createTask({
      title: 'X',
      parentTaskId: '01AAAAAAAAAAAAAAAAAAAAAAAA',
    });
    expect(badParent.statusCode).toBe(400);
    expect(badParent.json()).toMatchObject({ code: 'TASK_INVALID_PARENT' });

    const badTag = await createTask({ title: 'X', tagIds: ['01AAAAAAAAAAAAAAAAAAAAAAAA'] });
    expect(badTag.statusCode).toBe(400);
    expect(badTag.json()).toMatchObject({ code: 'TASK_INVALID_TAG' });
    expect(tables.tasks).toHaveLength(0);
  });

  it('attaches valid project and tags at creation', async () => {
    const project = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
        headers: owner.headers,
        payload: { name: 'Sprint' },
      })
    ).json();
    const tag = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
        headers: owner.headers,
        payload: { name: 'Focus' },
      })
    ).json();

    const res = await createTask({
      title: 'Design review',
      projectId: project.id,
      tagIds: [tag.id],
      priority: 'high',
      dueAt: '2026-07-20T10:00:00.000Z',
    });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      projectId: project.id,
      tagIds: [tag.id],
      priority: 'high',
      dueAt: '2026-07-20T10:00:00.000Z',
    });
    expect(tables.task_tags).toHaveLength(1);
  });
});

describe('GET /workspaces/:wsId/tasks — filters & pagination (OPH-032)', () => {
  it('paginates newest-first with a stable cursor', async () => {
    for (let i = 1; i <= 5; i += 1) {
      expect((await createTask({ title: `Task ${i}` })).statusCode).toBe(201);
    }

    const seen = [];
    let cursor = null;
    for (const expectedSize of [2, 2, 1]) {
      const qs = `?limit=2${cursor ? `&cursor=${cursor}` : ''}`;
      const page = (await listTasks(qs)).json();
      expect(page.items).toHaveLength(expectedSize);
      seen.push(...page.items.map((t) => t.id));
      cursor = page.nextCursor;
    }
    expect(cursor).toBeNull();
    expect(new Set(seen).size).toBe(5); // no overlaps, no gaps
  });

  it('filters by status, urgency, project, due range and tag', async () => {
    const project = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
        headers: owner.headers,
        payload: { name: 'P' },
      })
    ).json();
    const tag = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
        headers: owner.headers,
        payload: { name: 'T' },
      })
    ).json();

    await createTask({ title: 'inbox-urgent', status: 'inbox', isUrgent: true });
    await createTask({ title: 'in-project', projectId: project.id });
    await createTask({ title: 'due-soon', dueAt: '2026-07-15T09:00:00.000Z' });
    await createTask({ title: 'tagged', tagIds: [tag.id] });

    const byStatus = (await listTasks('?status=inbox')).json();
    expect(byStatus.items.map((t) => t.title)).toEqual(['inbox-urgent']);

    const byUrgent = (await listTasks('?urgent=true')).json();
    expect(byUrgent.items.map((t) => t.title)).toEqual(['inbox-urgent']);

    const byProject = (await listTasks(`?projectId=${project.id}`)).json();
    expect(byProject.items.map((t) => t.title)).toEqual(['in-project']);

    const byDue = (
      await listTasks('?dueFrom=2026-07-15T00:00:00.000Z&dueTo=2026-07-15T23:59:59.000Z')
    ).json();
    expect(byDue.items.map((t) => t.title)).toEqual(['due-soon']);

    const byTag = (await listTasks(`?tagId=${tag.id}`)).json();
    expect(byTag.items.map((t) => t.title)).toEqual(['tagged']);
  });

  it('searches title+description with ?q= (OPH-167, the notes-q twin)', async () => {
    await createTask({ title: 'Sunum hazırla', description: 'pazartesi teslim' });
    await createTask({ title: 'Alakasız iş' });

    // Title hit and description hit both ride ft_tasks_title_description
    // (the fake mimics MATCH…AGAINST as a substring test — same shape).
    const byTitle = (await listTasks('?q=Sunum')).json();
    expect(byTitle.items.map((t) => t.title)).toEqual(['Sunum hazırla']);

    const byDescription = (await listTasks('?q=teslim')).json();
    expect(byDescription.items.map((t) => t.title)).toEqual(['Sunum hazırla']);

    const none = (await listTasks('?q=bulunmaz')).json();
    expect(none.items).toEqual([]);
  });
});

describe('subtasks (OPH-032)', () => {
  it('nests, lists by parent filter, and blocks cycles', async () => {
    const parent = (await createTask({ title: 'Parent' })).json();
    const child = (await createTask({ title: 'Child', parentTaskId: parent.id })).json();
    const grandchild = (await createTask({ title: 'Grandchild', parentTaskId: child.id })).json();

    const children = (await listTasks(`?parentTaskId=${parent.id}`)).json();
    expect(children.items.map((t) => t.id)).toEqual([child.id]);

    // parent → its own grandchild would loop the chain.
    const cycle = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${parent.id}`,
      headers: owner.headers,
      payload: { parentTaskId: grandchild.id },
    });
    expect(cycle.statusCode).toBe(400);
    expect(cycle.json()).toMatchObject({ code: 'TASK_PARENT_CYCLE' });

    const selfParent = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${parent.id}`,
      headers: owner.headers,
      payload: { parentTaskId: parent.id },
    });
    expect(selfParent.statusCode).toBe(400);
  });

  it('soft-deleting a parent takes the whole subtree, each with its own sync row', async () => {
    const parent = (await createTask({ title: 'Parent' })).json();
    const child = (await createTask({ title: 'Child', parentTaskId: parent.id })).json();
    const grandchild = (await createTask({ title: 'Grandchild', parentTaskId: child.id })).json();

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${parent.id}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(204);

    expect(tables.tasks.every((t) => t.deleted_at)).toBe(true);
    const deleteRows = tables.sync_revisions.filter(
      (r) => r.entity_type === 'task' && r.operation === 'delete',
    );
    expect(deleteRows.map((r) => r.entity_id).sort()).toEqual(
      [parent.id, child.id, grandchild.id].sort(),
    );
    expect((await listTasks()).json().items).toHaveLength(0);
  });
});

describe('PATCH /tasks/:id and PUT /tasks/:id/tags (OPH-032)', () => {
  it('patches fields and replaces the tag set diff-wise', async () => {
    const mkTag = async (name) =>
      (
        await app.inject({
          method: 'POST',
          url: `/api/v1/workspaces/${owner.workspace.id}/tags`,
          headers: owner.headers,
          payload: { name },
        })
      ).json();
    const [t1, t2, t3] = [await mkTag('One'), await mkTag('Two'), await mkTag('Three')];
    const task = (await createTask({ title: 'Retag me', tagIds: [t1.id, t2.id] })).json();

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
      payload: { title: 'Retagged', priority: 'urgent', description: 'now with body' },
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json()).toMatchObject({ title: 'Retagged', priority: 'urgent', revision: 5 });

    const retag = await app.inject({
      method: 'PUT',
      url: `/api/v1/tasks/${task.id}/tags`,
      headers: owner.headers,
      payload: { tagIds: [t2.id, t3.id] },
    });
    expect(retag.statusCode).toBe(200);
    expect(retag.json().tagIds.sort()).toEqual([t2.id, t3.id].sort());
    expect(tables.task_tags.map((r) => r.tag_id).sort()).toEqual([t2.id, t3.id].sort());

    // No-op replace does not burn a revision.
    const before = tables.sync_revisions.length;
    await app.inject({
      method: 'PUT',
      url: `/api/v1/tasks/${task.id}/tags`,
      headers: owner.headers,
      payload: { tagIds: [t3.id, t2.id] },
    });
    expect(tables.sync_revisions).toHaveLength(before);
  });
});

describe('checklist sub-resource (OPH-032)', () => {
  it('creates, orders, toggles and deletes items under their task', async () => {
    const task = (await createTask({ title: 'With checklist' })).json();
    const other = (await createTask({ title: 'Other task' })).json();

    const second = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/checklist`,
        headers: owner.headers,
        payload: { title: 'Second', sortOrder: 2 },
      })
    ).json();
    const first = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/checklist`,
        headers: owner.headers,
        payload: { title: 'First', sortOrder: 1 },
      })
    ).json();

    const detail = (
      await app.inject({
        method: 'GET',
        url: `/api/v1/tasks/${task.id}`,
        headers: owner.headers,
      })
    ).json();
    expect(detail.checklist.map((i) => i.title)).toEqual(['First', 'Second']);

    const toggled = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}/checklist/${first.id}`,
      headers: owner.headers,
      payload: { isDone: true },
    });
    expect(toggled.statusCode).toBe(200);
    expect(toggled.json().isDone).toBe(true);

    // Item ids are scoped to their task — wrong task 404s.
    const wrongTask = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${other.id}/checklist/${first.id}`,
      headers: owner.headers,
      payload: { isDone: false },
    });
    expect(wrongTask.statusCode).toBe(404);
    expect(wrongTask.json()).toMatchObject({ code: 'CHECKLIST_ITEM_NOT_FOUND' });

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${task.id}/checklist/${second.id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    const after = (
      await app.inject({
        method: 'GET',
        url: `/api/v1/tasks/${task.id}`,
        headers: owner.headers,
      })
    ).json();
    expect(after.checklist.map((i) => i.title)).toEqual(['First']);
  });
});

describe('authorization (OPH-032)', () => {
  it('denies non-members across the surface', async () => {
    const task = (await createTask({ title: 'Private' })).json();
    const outsider = await registerUser(app, { email: 'outsider@example.com' });

    const denials = await Promise.all([
      listTasks('', outsider.headers),
      createTask({ title: 'Sneaky' }, outsider.headers),
      app.inject({ method: 'GET', url: `/api/v1/tasks/${task.id}`, headers: outsider.headers }),
      app.inject({
        method: 'PATCH',
        url: `/api/v1/tasks/${task.id}`,
        headers: outsider.headers,
        payload: { title: 'Hijack' },
      }),
      app.inject({
        method: 'PUT',
        url: `/api/v1/tasks/${task.id}/tags`,
        headers: outsider.headers,
        payload: { tagIds: [] },
      }),
      app.inject({
        method: 'POST',
        url: `/api/v1/tasks/${task.id}/checklist`,
        headers: outsider.headers,
        payload: { title: 'Nope' },
      }),
      app.inject({ method: 'DELETE', url: `/api/v1/tasks/${task.id}`, headers: outsider.headers }),
    ]);
    for (const res of denials) {
      expect(res.statusCode).toBe(403);
    }

    expect((await app.inject({ method: 'GET', url: wsUrl() })).statusCode).toBe(401);
  });
});
