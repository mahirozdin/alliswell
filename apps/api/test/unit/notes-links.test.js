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

const post = (url, payload) => app.inject({ method: 'POST', url, headers: owner.headers, payload });

async function makeProject(name = 'Proje') {
  return (await post(`/api/v1/workspaces/${owner.workspace.id}/projects`, { name })).json();
}

async function makeTask(payload) {
  return (await post(`/api/v1/workspaces/${owner.workspace.id}/tasks`, payload)).json();
}

async function makeNote(payload) {
  return (await post(`/api/v1/workspaces/${owner.workspace.id}/notes`, payload)).json();
}

describe('note links (OPH-041)', () => {
  it('links a note to a task and a project; duplicates answer 409', async () => {
    const note = await makeNote({ title: 'Bağlanacak' });
    const task = await makeTask({ title: 'Hedef görev' });
    const project = await makeProject();

    const linked = await post(`/api/v1/notes/${note.id}/links`, {
      entityType: 'task',
      entityId: task.id,
    });
    expect(linked.statusCode).toBe(201);
    expect(linked.json().links).toEqual([
      expect.objectContaining({ entityType: 'task', entityId: task.id }),
    ]);

    const projectLink = await post(`/api/v1/notes/${note.id}/links`, {
      entityType: 'project',
      entityId: project.id,
    });
    expect(projectLink.json().links).toHaveLength(2);

    const dup = await post(`/api/v1/notes/${note.id}/links`, {
      entityType: 'task',
      entityId: task.id,
    });
    expect(dup.statusCode).toBe(409);
    expect(dup.json()).toMatchObject({ code: 'NOTE_LINK_EXISTS' });
  });

  it('rejects targets outside the workspace and unknown ids', async () => {
    const note = await makeNote({ title: 'Sınırlı' });
    const foreign = await registerUser(app, { email: 'foreign@example.com' });
    const theirTask = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${foreign.workspace.id}/tasks`,
        headers: foreign.headers,
        payload: { title: 'Yabancı görev' },
      })
    ).json();

    for (const entityId of [theirTask.id, '01AAAAAAAAAAAAAAAAAAAAAAAA']) {
      const res = await post(`/api/v1/notes/${note.id}/links`, {
        entityType: 'task',
        entityId,
      });
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ code: 'NOTE_INVALID_LINK_TARGET' });
    }
  });

  it('unlinks via DELETE and bumps the note revision each time', async () => {
    const note = await makeNote({ title: 'Çözülecek' });
    const task = await makeTask({ title: 'Görev' });
    const linked = (
      await post(`/api/v1/notes/${note.id}/links`, { entityType: 'task', entityId: task.id })
    ).json();
    const linkId = linked.links[0].id;
    expect(linked.revision).toBe(3); // ws-global: note create (1), task create (2), link (3)

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/notes/${note.id}/links/${linkId}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    expect(tables.note_links).toHaveLength(0);

    const detail = await app.inject({
      method: 'GET',
      url: `/api/v1/notes/${note.id}`,
      headers: owner.headers,
    });
    expect(detail.json().links).toEqual([]);
    expect(detail.json().revision).toBeGreaterThan(linked.revision);
  });

  it('creates a note FROM a task: inherits project, links back, lists by taskId', async () => {
    const project = await makeProject('Ev Yenileme');
    const task = await makeTask({ title: 'Fayans seç', projectId: project.id });

    const res = await post(`/api/v1/tasks/${task.id}/notes`, {
      contentDelta: [{ insert: 'Mat beyaz olanlar\n' }],
    });
    expect(res.statusCode).toBe(201);
    const note = res.json();
    expect(note.title).toBe('Fayans seç'); // defaults to the task title
    expect(note.projectId).toBe(project.id); // inherited automatically
    expect(note.createdFromTaskId).toBe(task.id);
    expect(note.links).toEqual([
      expect.objectContaining({ entityType: 'task', entityId: task.id }),
    ]);

    // taskId list filter finds both link-based and created-from notes.
    const listed = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/notes?taskId=${task.id}`,
      headers: owner.headers,
    });
    expect(listed.json().items.map((n) => n.id)).toEqual([note.id]);
  });

  it('custom title in create-from-task wins over the task title', async () => {
    const task = await makeTask({ title: 'Orijinal' });
    const note = (await post(`/api/v1/tasks/${task.id}/notes`, { title: 'Özel başlık' })).json();
    expect(note.title).toBe('Özel başlık');
  });
});
