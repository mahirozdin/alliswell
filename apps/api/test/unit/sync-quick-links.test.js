import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-197 — `quick_link` in the sync protocol (ADR-0018): the first
 * user-scoped entity. Two properties are pinned here forever:
 *
 * 1. A member's pull NEVER carries another member's quick link — not even as
 *    a tombstone, because an id and a write timestamp are private too.
 * 2. Dropping those rows cannot stall the cursor: `toRevision` comes from the
 *    raw revision window, so the client still advances past them.
 */
let app;
let tables;
let owner;
let member;
let ws;

const CLIENT = newId();

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
  ws = owner.workspace.id;
  member = await registerUser(app, { email: 'member@example.com' });
  addMember(tables, { workspaceId: ws, user: member.user, role: 'member' });
});

afterEach(async () => {
  await app.close();
});

const pull = (since, who = owner) =>
  app.inject({
    method: 'GET',
    url: `/api/v1/sync/pull?workspaceId=${ws}&sinceRevision=${since}`,
    headers: who.headers,
  });

const push = (mutations, { who = owner, baseRevision = 0, clientId = CLIENT } = {}) =>
  app.inject({
    method: 'POST',
    url: '/api/v1/sync/push',
    headers: who.headers,
    payload: { clientId, workspaceId: ws, baseRevision, mutations },
  });

const mut = (overrides) => ({ clientMutationId: newId(), operation: 'create', ...overrides });

const addLink = async (title, who = owner) => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ws}/quick-links`,
    headers: who.headers,
    payload: { kind: 'url', url: `https://x.dev/${title}`, title },
  });
  expect(res.statusCode).toBe(201);
  return res.json();
};

describe('sync pull — user-scoped quick links (OPH-197, ADR-0018)', () => {
  it("hands a member their own rows and drops the other member's entirely", async () => {
    const before = Number(tables.workspaces.find((w) => w.id === ws).revision);
    const mine = await addLink('Benim');
    const theirs = await addLink('Onunki', member);

    const ours = (await pull(before)).json();
    const quick = ours.changes.filter((c) => c.entityType === 'quick_link');
    expect(quick).toHaveLength(1);
    expect(quick[0].entityId).toBe(mine.id);
    expect(quick[0].data.title).toBe('Benim');
    // Not even a tombstone for the other member's row.
    expect(ours.changes.some((c) => c.entityId === theirs.id)).toBe(false);

    const other = (await pull(before, member)).json();
    expect(other.changes.filter((c) => c.entityType === 'quick_link')).toHaveLength(1);
    expect(other.changes[0].entityId).toBe(theirs.id);
  });

  it('advances the cursor past invisible rows instead of stalling', async () => {
    const before = Number(tables.workspaces.find((w) => w.id === ws).revision);
    await addLink('Sadece-onunki', member);

    const res = (await pull(before)).json();
    expect(res.changes).toHaveLength(0); // nothing to apply…
    expect(res.toRevision).toBeGreaterThan(before); // …but the cursor moved
    expect(res.hasMore).toBe(false);
    // A second pull from the new cursor is quiet — no infinite re-fetch loop.
    expect((await pull(res.toRevision)).json().changes).toHaveLength(0);
  });

  it("still delivers the owner's OWN tombstone", async () => {
    const mine = await addLink('Silinecek');
    const before = Number(tables.workspaces.find((w) => w.id === ws).revision);
    await app.inject({
      method: 'DELETE',
      url: `/api/v1/quick-links/${mine.id}`,
      headers: owner.headers,
    });

    const changes = (await pull(before)).json().changes;
    expect(changes).toHaveLength(1);
    expect(changes[0]).toMatchObject({ entityId: mine.id, operation: 'delete', data: null });
  });
});

describe('sync push — quick links (OPH-197, ADR-0018)', () => {
  it('stamps the owner server-side and refuses a userId in the payload', async () => {
    const id = newId();
    const res = await push([
      mut({
        entityType: 'quick_link',
        entityId: id,
        patch: { kind: 'url', url: 'https://x.dev', title: 'Site' },
      }),
    ]);
    expect(res.json().results[0].status).toBe('applied');
    expect(tables.quick_links.find((r) => r.id === id).user_id).toBe(owner.user.id);

    const spoof = await push([
      mut({
        entityType: 'quick_link',
        entityId: newId(),
        patch: { kind: 'url', url: 'https://x.dev/2', title: 'Sahte', userId: member.user.id },
      }),
    ]);
    expect(spoof.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNKNOWN_FIELD',
    });
  });

  it('applies the REST create rules offline too', async () => {
    const project = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws}/projects`,
        headers: owner.headers,
        payload: { name: 'Ahmet' },
      })
    ).json();

    const ok = await push([
      mut({
        entityType: 'quick_link',
        entityId: newId(),
        patch: { kind: 'project', targetId: project.id, title: 'Ahmet' },
      }),
    ]);
    expect(ok.json().results[0].status).toBe('applied');

    const duplicate = await push([
      mut({
        entityType: 'quick_link',
        entityId: newId(),
        patch: { kind: 'project', targetId: project.id, title: 'Yine Ahmet' },
      }),
    ]);
    expect(duplicate.json().results[0].errorCode).toBe('QUICK_LINK_DUPLICATE');

    const missing = await push([
      mut({
        entityType: 'quick_link',
        entityId: newId(),
        patch: { kind: 'project', targetId: newId(), title: 'Yok' },
      }),
    ]);
    expect(missing.json().results[0].errorCode).toBe('QUICK_LINK_TARGET_NOT_FOUND');

    const shapeless = await push([
      mut({
        entityType: 'quick_link',
        entityId: newId(),
        patch: { kind: 'url', title: 'Adressiz' },
      }),
    ]);
    expect(shapeless.json().results[0].errorCode).toBe('QUICK_LINK_INVALID_TARGET');
  });

  it("refuses to update or delete another member's shortcut", async () => {
    const theirs = await addLink('Onunki', member);

    const renamed = await push([
      mut({
        entityType: 'quick_link',
        entityId: theirs.id,
        operation: 'update',
        patch: { title: 'Çalındı' },
      }),
    ]);
    expect(renamed.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'QUICK_LINK_NOT_YOURS',
    });

    // The delete path never calls `guard`, so ownership HAS to live in
    // `ownershipOk` — this case is why.
    const removed = await push([
      mut({ entityType: 'quick_link', entityId: theirs.id, operation: 'delete' }),
    ]);
    expect(removed.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'QUICK_LINK_NOT_YOURS',
    });
    expect(tables.quick_links.find((r) => r.id === theirs.id).deleted_at).toBeNull();
  });

  it('treats kind/targetId/url as create-only', async () => {
    const mine = await addLink('Benim');
    const res = await push([
      mut({
        entityType: 'quick_link',
        entityId: mine.id,
        operation: 'update',
        patch: { url: 'https://başka.dev' },
      }),
    ]);
    expect(res.json().results[0].errorCode).toBe('SYNC_UNKNOWN_FIELD');
  });

  it('is idempotent on replay', async () => {
    const id = newId();
    const mutation = mut({
      entityType: 'quick_link',
      entityId: id,
      patch: { kind: 'url', url: 'https://x.dev', title: 'Site' },
    });
    const first = await push([mutation]);
    const second = await push([mutation]);
    expect(second.json().results[0]).toMatchObject({
      status: 'applied',
      replayed: true,
      revision: first.json().results[0].revision,
    });
    expect(tables.quick_links.filter((r) => r.id === id)).toHaveLength(1);
  });
});
