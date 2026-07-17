import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com', displayName: 'Owner' });
});

afterEach(async () => {
  await app.close();
});

const createProject = (payload, headers = owner.headers, workspaceId = owner.workspace.id) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${workspaceId}/projects`,
    headers,
    payload,
  });

describe('POST /api/v1/workspaces/:wsId/projects (OPH-030)', () => {
  it('creates a project and records the sync revision in one transaction', async () => {
    const res = await createProject({
      name: 'Launch AllisWell',
      colorRgb: '#FF8800',
      description: 'v1 yol haritası',
      dueAt: '2026-08-01T12:00:00.000Z',
      isFavorite: true,
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body).toMatchObject({
      workspaceId: owner.workspace.id,
      name: 'Launch AllisWell',
      colorRgb: '#FF8800',
      status: 'active',
      isFavorite: true,
      revision: 1,
    });
    expect(body.dueAt).toBe('2026-08-01T12:00:00.000Z');

    expect(tables.projects).toHaveLength(1);
    expect(tables.projects[0].created_by).toBe(owner.user.id);

    // Sync log: workspace revision bumped and one matching log row (AGENTS.md §6).
    expect(Number(tables.workspaces[0].revision)).toBe(1);
    expect(tables.sync_revisions).toHaveLength(1);
    expect(tables.sync_revisions[0]).toMatchObject({
      workspace_id: owner.workspace.id,
      revision: 1,
      entity_type: 'project',
      entity_id: body.id,
      operation: 'create',
    });
  });

  it('rejects invalid colors, statuses and empty names', async () => {
    for (const payload of [
      { name: 'X', colorRgb: 'FF8800' }, // missing #
      { name: 'X', colorRgb: '#FF880' }, // too short
      { name: 'X', status: 'sleeping' },
      { name: '' },
      {},
    ]) {
      const res = await createProject(payload);
      expect(res.statusCode, JSON.stringify(payload)).toBe(400);
    }
    expect(tables.projects).toHaveLength(0);
  });
});

describe('GET /api/v1/workspaces/:wsId/projects (OPH-030)', () => {
  it('lists by sort_order and filters by status', async () => {
    const second = (await createProject({ name: 'Second', sortOrder: 2 })).json();
    const first = (await createProject({ name: 'First', sortOrder: 1 })).json();
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${second.id}`,
      headers: owner.headers,
      payload: { status: 'archived' },
    });

    const all = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
      headers: owner.headers,
    });
    expect(all.json().items.map((p) => p.name)).toEqual(['First', 'Second']);
    expect(all.json().items[0].id).toBe(first.id);

    const archived = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/projects?status=archived`,
      headers: owner.headers,
    });
    expect(archived.json().items.map((p) => p.name)).toEqual(['Second']);
  });
});

describe('single project routes (OPH-030)', () => {
  it('gets, patches (with sync log) and 404s after soft delete', async () => {
    const created = (await createProject({ name: 'Evolving' })).json();

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${created.id}`,
      headers: owner.headers,
      payload: { name: 'Evolved', isFavorite: true, startAt: '2026-07-20T09:00:00.000Z' },
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json()).toMatchObject({ name: 'Evolved', isFavorite: true, revision: 2 });

    const syncRow = tables.sync_revisions.at(-1);
    expect(syncRow).toMatchObject({ operation: 'update', revision: 2 });
    expect(JSON.parse(syncRow.changed_fields).sort()).toEqual(['is_favorite', 'name', 'start_at']);

    const deleted = await app.inject({
      method: 'DELETE',
      url: `/api/v1/projects/${created.id}`,
      headers: owner.headers,
    });
    expect(deleted.statusCode).toBe(204);
    expect(tables.projects[0].deleted_at).toBeTruthy();
    expect(tables.sync_revisions.at(-1)).toMatchObject({ operation: 'delete', revision: 3 });

    const gone = await app.inject({
      method: 'GET',
      url: `/api/v1/projects/${created.id}`,
      headers: owner.headers,
    });
    expect(gone.statusCode).toBe(404);
    expect(gone.json()).toMatchObject({ code: 'PROJECT_NOT_FOUND' });
  });

  it('rejects an empty patch and unknown ids', async () => {
    const created = (await createProject({ name: 'Solid' })).json();
    const empty = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${created.id}`,
      headers: owner.headers,
      payload: {},
    });
    expect(empty.statusCode).toBe(400);

    const missing = await app.inject({
      method: 'GET',
      url: '/api/v1/projects/01AAAAAAAAAAAAAAAAAAAAAAAA',
      headers: owner.headers,
    });
    expect(missing.statusCode).toBe(404);
  });
});

describe('project README note (feedback round 1)', () => {
  it('sets and clears readmeNoteId, validating the workspace', async () => {
    const project = (await createProject({ name: 'Docs' })).json();
    expect(project.readmeNoteId).toBeNull();

    const note = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
        headers: owner.headers,
        payload: { title: 'Docs README', projectId: project.id },
      })
    ).json();

    const set = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
      payload: { readmeNoteId: note.id },
    });
    expect(set.statusCode).toBe(200);
    expect(set.json().readmeNoteId).toBe(note.id);

    const cleared = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
      payload: { readmeNoteId: null },
    });
    expect(cleared.json().readmeNoteId).toBeNull();

    // A note from another workspace is rejected.
    const foreign = await registerUser(app, { email: 'readme-foreign@example.com' });
    const theirNote = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${foreign.workspace.id}/notes`,
        headers: foreign.headers,
        payload: { title: 'Theirs' },
      })
    ).json();
    const bad = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
      payload: { readmeNoteId: theirNote.id },
    });
    expect(bad.statusCode).toBe(400);
    expect(bad.json()).toMatchObject({ code: 'PROJECT_INVALID_README_NOTE' });
  });
});

describe('authorization (OPH-030)', () => {
  it('members can edit but not delete; owners can delete', async () => {
    const created = (await createProject({ name: 'Shared' })).json();
    const member = await registerUser(app, { email: 'member@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: member.user, role: 'member' });

    const patch = await app.inject({
      method: 'PATCH',
      url: `/api/v1/projects/${created.id}`,
      headers: member.headers,
      payload: { name: 'Shared v2' },
    });
    expect(patch.statusCode).toBe(200);

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/projects/${created.id}`,
      headers: member.headers,
    });
    expect(del.statusCode).toBe(403);
    expect(del.json()).toMatchObject({ code: 'AUTH_WORKSPACE_FORBIDDEN' });
  });

  it('denies every route to non-members and the unauthenticated', async () => {
    const created = (await createProject({ name: 'Private' })).json();
    const outsider = await registerUser(app, { email: 'outsider@example.com' });

    const denials = [
      app.inject({
        method: 'GET',
        url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
        headers: outsider.headers,
      }),
      createProject({ name: 'Sneaky' }, outsider.headers),
      app.inject({
        method: 'GET',
        url: `/api/v1/projects/${created.id}`,
        headers: outsider.headers,
      }),
      app.inject({
        method: 'PATCH',
        url: `/api/v1/projects/${created.id}`,
        headers: outsider.headers,
        payload: { name: 'Hijack' },
      }),
      app.inject({
        method: 'DELETE',
        url: `/api/v1/projects/${created.id}`,
        headers: outsider.headers,
      }),
    ];
    for (const res of await Promise.all(denials)) {
      expect(res.statusCode).toBe(403);
      expect(res.json()).toMatchObject({ code: 'AUTH_WORKSPACE_FORBIDDEN' });
    }

    const unauthenticated = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/projects`,
    });
    expect(unauthenticated.statusCode).toBe(401);
  });
});

describe('POST /projects/:id/archive & /unarchive (OPH-110)', () => {
  const createTask = (payload) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload,
    });
  const createNote = (payload) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
      headers: owner.headers,
      payload,
    });
  const archive = (id, body = {}, headers = owner.headers) =>
    app.inject({ method: 'POST', url: `/api/v1/projects/${id}/archive`, headers, payload: body });
  const unarchive = (id, body = {}) =>
    app.inject({ method: 'POST', url: `/api/v1/projects/${id}/unarchive`, headers: owner.headers, payload: body });

  it('archives just the project by default, leaving tasks and notes', async () => {
    const project = (await createProject({ name: 'Arşivlik' })).json();
    await createTask({ title: 'Görev', projectId: project.id });
    const res = await archive(project.id);
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.project.status).toBe('archived');
    expect(body.tasksChanged).toBe(0);
    expect(body.notesChanged).toBe(0);
    expect(tables.tasks.find((t) => t.title === 'Görev').status).not.toBe('archived');
  });

  it('cascades to tasks and notes, deactivating the reminder', async () => {
    const project = (await createProject({ name: 'Tam' })).json();
    await createTask({
      title: 'Hatırlatmalı',
      projectId: project.id,
      remindAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    await createNote({ title: 'Proje notu', projectId: project.id });
    expect(tables.reminders[0].status).toBe('scheduled');

    const body = (await archive(project.id, { includeTasks: true, includeNotes: true })).json();
    expect(body.tasksChanged).toBe(1);
    expect(body.notesChanged).toBe(1);
    expect(tables.tasks.find((t) => t.title === 'Hatırlatmalı').status).toBe('archived');
    expect(tables.notes.find((n) => n.title === 'Proje notu').is_archived).toBeTruthy();
    // The reminder is silenced with its archived task.
    expect(tables.reminders[0].status).toBe('cancelled');
  });

  it('re-archiving is idempotent (zero changes)', async () => {
    const project = (await createProject({ name: 'İki kez' })).json();
    await createTask({ title: 'G', projectId: project.id });
    await archive(project.id, { includeTasks: true });
    const again = (await archive(project.id, { includeTasks: true })).json();
    expect(again.project.status).toBe('archived');
    expect(again.tasksChanged).toBe(0);
  });

  it('unarchive with cascade revives tasks, notes and re-arms the reminder', async () => {
    const project = (await createProject({ name: 'Geri' })).json();
    await createTask({
      title: 'Hatırlatmalı',
      projectId: project.id,
      remindAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    await createNote({ title: 'Not', projectId: project.id });
    await archive(project.id, { includeTasks: true, includeNotes: true });

    const body = (await unarchive(project.id, { includeTasks: true, includeNotes: true })).json();
    expect(body.project.status).toBe('active');
    expect(body.tasksChanged).toBe(1);
    expect(body.notesChanged).toBe(1);
    expect(tables.tasks.find((t) => t.title === 'Hatırlatmalı').status).toBe('open');
    expect(tables.notes.find((n) => n.title === 'Not').is_archived).toBeFalsy();
    expect(tables.reminders.some((r) => r.status === 'scheduled')).toBe(true);
  });

  it('a member (not just owner/admin) can archive — it is reversible', async () => {
    const member = await registerUser(app, { email: 'member@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: member.user });
    const project = (await createProject({ name: 'Üye arşivler' })).json();
    const res = await archive(project.id, {}, member.headers);
    expect(res.statusCode).toBe(200);
  });
});
