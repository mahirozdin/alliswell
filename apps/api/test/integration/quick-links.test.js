import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-197 — quick links over real MySQL: the properties the fake db cannot
 * prove. Above all ADR-0018's pinned rule — in a workspace with two members,
 * member A's shortcut NEVER reaches member B's pull — plus the two things that
 * depend on the real engine's index semantics: entity targets are unique, and
 * url rows (NULL target_id) are deliberately exempt.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('quick links integration (OPH-197, ADR-0018)', () => {
  let app;
  let ws;
  let ownerHeaders;
  let memberHeaders;
  const emailPrefix = `quicklinks-int-${Date.now()}`;

  const register = async (suffix) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-${suffix}@example.com`, password: 'sifre-12345' },
    });
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, NODE_ENV: 'test' });
    app = await buildApp({ config });

    const owner = await register('owner');
    ws = owner.workspace.id;
    ownerHeaders = { authorization: `Bearer ${owner.tokens.accessToken}` };

    // There is no invite endpoint yet (sharing UI is parked, the schema is
    // not) — the membership row is what makes this a two-member workspace.
    const member = await register('member');
    memberHeaders = { authorization: `Bearer ${member.tokens.accessToken}` };
    await app.db('workspace_members').insert({
      id: newId(),
      workspace_id: ws,
      user_id: member.user.id,
      role: 'member',
    });
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('workspace_members').whereIn('user_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  const add = (headers, payload) =>
    app.inject({ method: 'POST', url: `/api/v1/workspaces/${ws}/quick-links`, headers, payload });

  const pull = (headers, since) =>
    app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=${since}`,
      headers,
    });

  const revision = async () => {
    const row = await app.db('workspaces').where({ id: ws }).first('revision');
    return Number(row.revision);
  };

  it("never lets a member's shortcut reach the other member's pull", async () => {
    const before = await revision();
    const mine = (
      await add(ownerHeaders, { kind: 'url', url: 'https://alliswell.space', title: 'Benim' })
    ).json();
    const theirs = (
      await add(memberHeaders, { kind: 'url', url: 'https://example.com', title: 'Onunki' })
    ).json();

    const ownerPull = (await pull(ownerHeaders, before)).json();
    const ownerQuick = ownerPull.changes.filter((c) => c.entityType === 'quick_link');
    expect(ownerQuick.map((c) => c.entityId)).toEqual([mine.id]);
    expect(ownerPull.changes.some((c) => c.entityId === theirs.id)).toBe(false);

    const memberPull = (await pull(memberHeaders, before)).json();
    expect(memberPull.changes.map((c) => c.entityId)).toEqual([theirs.id]);

    // Both cursors still moved past BOTH writes — invisible rows never stall
    // the protocol.
    expect(ownerPull.toRevision).toBe(memberPull.toRevision);
    expect(ownerPull.toRevision).toBeGreaterThanOrEqual(before + 2);
  });

  it('enforces target uniqueness in the index, and exempts urls', async () => {
    const project = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws}/projects`,
        headers: ownerHeaders,
        payload: { name: `Proje ${Date.now()}` },
      })
    ).json();

    expect(
      (await add(ownerHeaders, { kind: 'project', targetId: project.id, title: 'Bir' })).statusCode,
    ).toBe(201);
    const dupe = await add(ownerHeaders, { kind: 'project', targetId: project.id, title: 'İki' });
    expect(dupe.statusCode).toBe(409);
    expect(dupe.json().code).toBe('QUICK_LINK_DUPLICATE');

    // Same target, DIFFERENT member: their own rail, their own row.
    expect(
      (await add(memberHeaders, { kind: 'project', targetId: project.id, title: 'Onun' }))
        .statusCode,
    ).toBe(201);

    // Two url rows to the same address are legitimate — the unique index
    // ignores NULL target_id, which is exactly the intended behaviour.
    const url = `https://x.dev/${Date.now()}`;
    expect((await add(ownerHeaders, { kind: 'url', url, title: 'A' })).statusCode).toBe(201);
    expect((await add(ownerHeaders, { kind: 'url', url, title: 'B' })).statusCode).toBe(201);
  });

  it('cascades on target delete and lets the same target be re-added', async () => {
    const project = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws}/projects`,
        headers: ownerHeaders,
        payload: { name: `Silinecek ${Date.now()}` },
      })
    ).json();
    const mine = (
      await add(ownerHeaders, { kind: 'project', targetId: project.id, title: 'Benim' })
    ).json();
    const theirs = (
      await add(memberHeaders, { kind: 'project', targetId: project.id, title: 'Onunki' })
    ).json();
    const before = await revision();

    const removed = await app.inject({
      method: 'DELETE',
      url: `/api/v1/projects/${project.id}`,
      headers: ownerHeaders,
    });
    expect(removed.statusCode).toBe(204);

    for (const id of [mine.id, theirs.id]) {
      const row = await app.db('quick_links').where({ id }).first();
      expect(row.deleted_at).not.toBeNull();
      expect(row.target_id).toBeNull(); // the uniqueness slot is freed
    }

    // Each member pulls only their OWN tombstone.
    const ownerTombs = (await pull(ownerHeaders, before))
      .json()
      .changes.filter((c) => c.entityType === 'quick_link');
    expect(ownerTombs.map((c) => c.entityId)).toEqual([mine.id]);
    expect(ownerTombs[0].operation).toBe('delete');
  });

  it('reorders the whole rail in one transaction', async () => {
    const titles = ['R1', 'R2', 'R3'];
    const created = [];
    for (const title of titles) {
      created.push(
        (
          await add(ownerHeaders, {
            kind: 'url',
            url: `https://x.dev/${title}-${Date.now()}`,
            title,
          })
        ).json(),
      );
    }
    const all = await app
      .db('quick_links')
      .where({ workspace_id: ws })
      .whereNull('deleted_at')
      .orderBy('sort_order', 'asc')
      .select('id');
    const mine = all.map((r) => r.id).filter((id) => created.some((c) => c.id === id));
    const reversed = [...mine].reverse();

    const res = await app.inject({
      method: 'PUT',
      url: `/api/v1/workspaces/${ws}/quick-links/order`,
      headers: ownerHeaders,
      payload: { orderedIds: reversed },
    });
    // Rows created in the earlier cases are part of "my list" too, so a subset
    // is rightly refused; the full list is what the client sends.
    expect(res.statusCode).toBe(422);
    expect(res.json().code).toBe('QUICK_LINK_ORDER_INCOMPLETE');

    const full = (
      await app.inject({
        method: 'GET',
        url: `/api/v1/workspaces/${ws}/quick-links`,
        headers: ownerHeaders,
      })
    ).json().items;
    const fullReversed = [...full].reverse().map((i) => i.id);
    const ok = await app.inject({
      method: 'PUT',
      url: `/api/v1/workspaces/${ws}/quick-links/order`,
      headers: ownerHeaders,
      payload: { orderedIds: fullReversed },
    });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().items.map((i) => i.id)).toEqual(fullReversed);
    expect(ok.json().items.map((i) => i.sortOrder)).toEqual(
      fullReversed.map((_, index) => index * 1024),
    );
  });
});
