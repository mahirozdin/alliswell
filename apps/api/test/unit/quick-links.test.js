import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';

/**
 * OPH-197 — quick links REST (ADR-0018, BLUEPRINT §4.12): the personal
 * shortcut rail. Covers the create gate (shape, target existence, duplicate,
 * the 50 limit), the personalization patch, the soft delete that frees the
 * target slot, and the ownership rule that makes another member's row a 404.
 */
describe('quick links (OPH-197, ADR-0018)', () => {
  let app;
  let tables;
  let owner;
  let ws;

  beforeEach(async () => {
    ({ app, tables } = await buildTestApp());
    owner = await registerUser(app, { email: 'owner@example.com' });
    ws = owner.workspace.id;
  });

  const createProject = async (name = 'Ahmet') => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/projects`,
      headers: owner.headers,
      payload: { name },
    });
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const add = (payload, who = owner) =>
    app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/quick-links`,
      headers: who.headers,
      payload,
    });

  const list = (who = owner) =>
    app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ws}/quick-links`,
      headers: who.headers,
    });

  it('adds a project shortcut and lands it at the tail of the rail', async () => {
    const project = await createProject();
    const first = await add({ kind: 'project', targetId: project.id, title: 'Ahmet' });
    expect(first.statusCode).toBe(201);
    expect(first.json()).toMatchObject({
      kind: 'project',
      targetId: project.id,
      title: 'Ahmet',
      url: null,
      sortOrder: 0,
    });

    const second = await add({ kind: 'url', url: 'https://alliswell.space', title: 'Site' });
    expect(second.statusCode).toBe(201);
    expect(second.json().sortOrder).toBeGreaterThan(first.json().sortOrder);

    const items = (await list()).json().items;
    expect(items.map((i) => i.title)).toEqual(['Ahmet', 'Site']);
    // The owner id IS on the wire — always the caller's own — so the replica
    // can filter its local rail after a user switch (ADR-0018).
    expect(items.every((i) => i.userId === owner.user.id)).toBe(true);
  });

  it('refuses a missing, deleted or foreign-workspace target', async () => {
    const missing = await add({
      kind: 'project',
      targetId: '01JQZZZZZZZZZZZZZZZZZZZZZZ',
      title: 'X',
    });
    expect(missing.statusCode).toBe(404);
    expect(missing.json().code).toBe('QUICK_LINK_TARGET_NOT_FOUND');

    const project = await createProject('Silinecek');
    await app.inject({
      method: 'DELETE',
      url: `/api/v1/projects/${project.id}`,
      headers: owner.headers,
    });
    const deleted = await add({ kind: 'project', targetId: project.id, title: 'Silinecek' });
    expect(deleted.statusCode).toBe(404);

    const stranger = await registerUser(app, { email: 'stranger@example.com' });
    const theirProject = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${stranger.workspace.id}/projects`,
      headers: stranger.headers,
      payload: { name: 'Yabancı' },
    });
    const foreign = await add({
      kind: 'project',
      targetId: theirProject.json().id,
      title: 'Yabancı',
    });
    expect(foreign.statusCode).toBe(404);
    expect(foreign.json().code).toBe('QUICK_LINK_TARGET_NOT_FOUND');
  });

  it('enforces the kind/target/url shape', async () => {
    const project = await createProject();
    const both = await add({
      kind: 'project',
      targetId: project.id,
      url: 'https://x.dev',
      title: 'İkisi',
    });
    expect(both.statusCode).toBe(400);
    expect(both.json().code).toBe('QUICK_LINK_INVALID_TARGET');

    const targetless = await add({ kind: 'project', title: 'Hedefsiz' });
    expect(targetless.statusCode).toBe(400);

    const badScheme = await add({ kind: 'url', url: 'javascript:alert(1)', title: 'Kötü' });
    expect(badScheme.statusCode).toBe(400);

    const urlWithTarget = await add({
      kind: 'url',
      url: 'https://x.dev',
      targetId: project.id,
      title: 'Karışık',
    });
    expect(urlWithTarget.statusCode).toBe(400);
  });

  it('deduplicates entity targets but never urls', async () => {
    const project = await createProject();
    expect((await add({ kind: 'project', targetId: project.id, title: 'Bir' })).statusCode).toBe(
      201,
    );
    const again = await add({ kind: 'project', targetId: project.id, title: 'İki' });
    expect(again.statusCode).toBe(409);
    expect(again.json().code).toBe('QUICK_LINK_DUPLICATE');

    // Two shortcuts to the same URL with different names are legitimate: the
    // URL dialog has no add-remove toggle, so there is no invariant to protect.
    expect((await add({ kind: 'url', url: 'https://x.dev', title: 'A' })).statusCode).toBe(201);
    expect((await add({ kind: 'url', url: 'https://x.dev', title: 'B' })).statusCode).toBe(201);
  });

  it('refuses the 51st shortcut with 422 QUICK_LINK_LIMIT', async () => {
    for (let i = 0; i < 50; i += 1) {
      const res = await add({ kind: 'url', url: `https://x.dev/${i}`, title: `L${i}` });
      expect(res.statusCode).toBe(201);
    }
    const over = await add({ kind: 'url', url: 'https://x.dev/51', title: 'Fazla' });
    expect(over.statusCode).toBe(422);
    expect(over.json().code).toBe('QUICK_LINK_LIMIT');
  });

  it('patches title, emoji and colour — and refuses to retarget', async () => {
    const project = await createProject();
    const link = (await add({ kind: 'project', targetId: project.id, title: 'Ahmet' })).json();

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/v1/quick-links/${link.id}`,
      headers: owner.headers,
      // A four-person family emoji: ONE grapheme, 25 bytes — the column counts
      // characters, so it fits (BLUEPRINT §4.12).
      payload: { title: 'Ahmet Projesi', emoji: '👨‍👩‍👧‍👦', colorRgb: '#2563EB' },
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json()).toMatchObject({
      title: 'Ahmet Projesi',
      emoji: '👨‍👩‍👧‍👦',
      colorRgb: '#2563EB',
    });
    expect(patched.json().revision).toBeGreaterThan(link.revision);

    // A target is immutable (remove + add instead). Fastify's Ajv strips the
    // unknown key, so the honest answer is "nothing to update" — not a silent
    // 200 that burns a revision.
    const other = await createProject('Başka');
    const retarget = await app.inject({
      method: 'PATCH',
      url: `/api/v1/quick-links/${link.id}`,
      headers: owner.headers,
      payload: { targetId: other.id },
    });
    expect(retarget.statusCode).toBe(400);
    expect(retarget.json().code).toBe('QUICK_LINK_EMPTY_PATCH');
    expect(tables.quick_links.find((r) => r.id === link.id).target_id).toBe(project.id);

    const clearEmoji = await app.inject({
      method: 'PATCH',
      url: `/api/v1/quick-links/${link.id}`,
      headers: owner.headers,
      payload: { emoji: null, colorRgb: null },
    });
    expect(clearEmoji.json()).toMatchObject({ emoji: null, colorRgb: null });
  });

  it('soft-deletes, frees the target slot, and stays out of the list', async () => {
    const project = await createProject();
    const link = (await add({ kind: 'project', targetId: project.id, title: 'Ahmet' })).json();

    const removed = await app.inject({
      method: 'DELETE',
      url: `/api/v1/quick-links/${link.id}`,
      headers: owner.headers,
    });
    expect(removed.statusCode).toBe(204);
    expect((await list()).json().items).toHaveLength(0);

    const row = tables.quick_links.find((r) => r.id === link.id);
    expect(row.deleted_at).not.toBeNull();
    // target_id is nulled so the unique slot frees up…
    expect(row.target_id).toBeNull();
    // …which is what lets the same target be added again.
    expect((await add({ kind: 'project', targetId: project.id, title: 'Ahmet' })).statusCode).toBe(
      201,
    );
  });

  it("answers 404 QUICK_LINK_NOT_YOURS on another member's shortcut", async () => {
    const member = await registerUser(app, { email: 'member@example.com' });
    addMember(tables, { workspaceId: ws, user: member.user, role: 'member' });
    const project = await createProject();
    const mine = (await add({ kind: 'project', targetId: project.id, title: 'Benim' })).json();

    // The other member sees an empty rail of their own…
    expect((await list(member)).json().items).toHaveLength(0);

    for (const method of ['PATCH', 'DELETE']) {
      const res = await app.inject({
        method,
        url: `/api/v1/quick-links/${mine.id}`,
        headers: member.headers,
        ...(method === 'PATCH' ? { payload: { title: 'Çalındı' } } : {}),
      });
      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('QUICK_LINK_NOT_YOURS');
    }
    // …and the row is untouched.
    expect(tables.quick_links.find((r) => r.id === mine.id).title).toBe('Benim');
  });

  it('outsiders cannot even list the workspace rail', async () => {
    const stranger = await registerUser(app, { email: 'outsider@example.com' });
    expect((await list(stranger)).statusCode).toBe(403);
  });
});
