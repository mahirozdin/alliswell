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

const post = (url, payload) => app.inject({ method: 'POST', url, headers: owner.headers, payload });

describe('GET /projects/:id/notes (OPH-042)', () => {
  it('returns attached AND linked notes, hiding archived by default', async () => {
    const project = (
      await post(`/api/v1/workspaces/${owner.workspace.id}/projects`, { name: 'Kitap' })
    ).json();

    const attached = (
      await post(`/api/v1/workspaces/${owner.workspace.id}/notes`, {
        title: 'Bölüm taslağı',
        projectId: project.id,
      })
    ).json();
    const linked = (
      await post(`/api/v1/workspaces/${owner.workspace.id}/notes`, { title: 'Araştırma' })
    ).json();
    await post(`/api/v1/notes/${linked.id}/links`, {
      entityType: 'project',
      entityId: project.id,
    });
    const archived = (
      await post(`/api/v1/workspaces/${owner.workspace.id}/notes`, {
        title: 'Eski fikirler',
        projectId: project.id,
      })
    ).json();
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${archived.id}`,
      headers: owner.headers,
      payload: { isArchived: true },
    });
    await post(`/api/v1/workspaces/${owner.workspace.id}/notes`, { title: 'Alakasız' });

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/projects/${project.id}/notes`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(
      res
        .json()
        .items.map((n) => n.id)
        .sort(),
    ).toEqual([attached.id, linked.id].sort());

    const withArchived = await app.inject({
      method: 'GET',
      url: `/api/v1/projects/${project.id}/notes?includeArchived=true`,
      headers: owner.headers,
    });
    expect(withArchived.json().items).toHaveLength(3);
  });

  it('404s on unknown projects and denies outsiders', async () => {
    const project = (
      await post(`/api/v1/workspaces/${owner.workspace.id}/projects`, { name: 'Gizli' })
    ).json();

    const missing = await app.inject({
      method: 'GET',
      url: '/api/v1/projects/01AAAAAAAAAAAAAAAAAAAAAAAA/notes',
      headers: owner.headers,
    });
    expect(missing.statusCode).toBe(404);

    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const denied = await app.inject({
      method: 'GET',
      url: `/api/v1/projects/${project.id}/notes`,
      headers: outsider.headers,
    });
    expect(denied.statusCode).toBe(403);
  });
});
