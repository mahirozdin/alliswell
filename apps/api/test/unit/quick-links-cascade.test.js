import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';
import { fakeStorage } from '../helpers/fakestorage.js';

/**
 * OPH-197 — the target cascade (ADR-0018 §4). Hard-deleting a target kills
 * EVERY member's shortcut to it, in the same transaction, each with its own
 * revision so every device's rail heals itself on the next pull. Archiving
 * must not: archives are reversible and the shortcut stays, rendered muted.
 */
describe('quick link cascade (OPH-197, ADR-0018)', () => {
  let app;
  let tables;
  let owner;
  let member;
  let ws;
  let storage;

  beforeEach(async () => {
    storage = fakeStorage();
    ({ app, tables } = await buildTestApp({ storage }));
    owner = await registerUser(app, { email: 'owner@example.com' });
    ws = owner.workspace.id;
    member = await registerUser(app, { email: 'member@example.com' });
    addMember(tables, { workspaceId: ws, user: member.user, role: 'member' });
  });

  const post = async (url, payload, who = owner) => {
    const res = await app.inject({ method: 'POST', url, headers: who.headers, payload });
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const shortcut = async (kind, targetId, who = owner) =>
    post(`/api/v1/workspaces/${ws}/quick-links`, { kind, targetId, title: kind }, who);

  const live = (id) => tables.quick_links.find((r) => r.id === id).deleted_at === null;

  const del = async (url, who = owner) => {
    const res = await app.inject({ method: 'DELETE', url, headers: who.headers });
    expect([200, 204]).toContain(res.statusCode);
    return res;
  };

  it("removes every member's shortcut when a project is deleted", async () => {
    const project = await post(`/api/v1/workspaces/${ws}/projects`, { name: 'Ahmet' });
    const mine = await shortcut('project', project.id);
    const theirs = await shortcut('project', project.id, member);
    const before = Number(tables.workspaces.find((w) => w.id === ws).revision);

    await del(`/api/v1/projects/${project.id}`);

    expect(live(mine.id)).toBe(false);
    expect(live(theirs.id)).toBe(false);
    // One revision each — a shared tombstone would leave one device stale.
    const logged = tables.sync_revisions.filter(
      (r) => r.entity_type === 'quick_link' && Number(r.revision) > before,
    );
    expect(logged).toHaveLength(2);
    expect(logged.every((r) => r.operation === 'delete')).toBe(true);
  });

  it('takes subtask shortcuts down with the parent task', async () => {
    const parent = await post(`/api/v1/workspaces/${ws}/tasks`, { title: 'Üst' });
    const child = await post(`/api/v1/workspaces/${ws}/tasks`, {
      title: 'Alt',
      parentTaskId: parent.id,
    });
    const parentLink = await shortcut('task', parent.id);
    const childLink = await shortcut('task', child.id);

    await del(`/api/v1/tasks/${parent.id}`);

    expect(live(parentLink.id)).toBe(false);
    expect(live(childLink.id)).toBe(false);
  });

  it('removes a note shortcut with the note', async () => {
    const note = await post(`/api/v1/workspaces/${ws}/notes`, { title: 'Not' });
    const link = await shortcut('note', note.id);
    await del(`/api/v1/notes/${note.id}`);
    expect(live(link.id)).toBe(false);
  });

  it('removes folder AND file shortcuts across a folder subtree', async () => {
    const root = await post(`/api/v1/workspaces/${ws}/folders`, { name: 'Belgeler' });
    const child = await post(`/api/v1/workspaces/${ws}/folders`, {
      name: 'Faturalar',
      parentId: root.id,
    });
    const file = await post(`/api/v1/workspaces/${ws}/files`, {
      targetType: 'workspace',
      targetId: ws,
      name: 'fatura.pdf',
      sizeBytes: 64,
      folderId: child.id,
    });
    storage.objects.set(`ws/${ws}/${file.file.id}`, 64);
    const done = await app.inject({
      method: 'POST',
      url: `/api/v1/files/${file.file.id}/complete`,
      headers: owner.headers,
    });
    expect(done.statusCode).toBe(200);

    const rootLink = await shortcut('folder', root.id);
    const childLink = await shortcut('folder', child.id);
    const fileLink = await shortcut('file', file.file.id);

    await del(`/api/v1/folders/${root.id}`);

    expect(live(rootLink.id)).toBe(false);
    expect(live(childLink.id)).toBe(false);
    // The file died inside the subtree, and softDeleteReadyFile is the choke
    // point that carries its shortcut along.
    expect(live(fileLink.id)).toBe(false);
  });

  it('removes a file shortcut when the file alone is deleted', async () => {
    const file = await post(`/api/v1/workspaces/${ws}/files`, {
      targetType: 'workspace',
      targetId: ws,
      name: 'tek.pdf',
      sizeBytes: 32,
    });
    storage.objects.set(`ws/${ws}/${file.file.id}`, 32);
    await app.inject({
      method: 'POST',
      url: `/api/v1/files/${file.file.id}/complete`,
      headers: owner.headers,
    });
    const link = await shortcut('file', file.file.id);
    await del(`/api/v1/files/${file.file.id}`);
    expect(live(link.id)).toBe(false);
  });

  it('leaves shortcuts alone when the target is merely archived', async () => {
    const project = await post(`/api/v1/workspaces/${ws}/projects`, { name: 'Arşivlik' });
    const task = await post(`/api/v1/workspaces/${ws}/tasks`, { title: 'Arşivlik iş' });
    const note = await post(`/api/v1/workspaces/${ws}/notes`, { title: 'Arşivlik not' });
    const links = [
      await shortcut('project', project.id),
      await shortcut('task', task.id),
      await shortcut('note', note.id),
    ];

    for (const [url, payload] of [
      [`/api/v1/projects/${project.id}`, { status: 'archived' }],
      [`/api/v1/tasks/${task.id}`, { status: 'archived' }],
      [`/api/v1/notes/${note.id}`, { isArchived: true }],
    ]) {
      const res = await app.inject({ method: 'PATCH', url, headers: owner.headers, payload });
      expect(res.statusCode).toBe(200);
    }

    // Archive is reversible; the row lives on and the UI renders it muted.
    for (const link of links) expect(live(link.id)).toBe(true);
  });
});
