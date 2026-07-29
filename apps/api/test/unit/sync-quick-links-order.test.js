import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-197/198 — the rail's order travels as ONE outbox mutation, and it does
 * so as an ordinary `update` carrying the virtual field `orderedIds`.
 *
 * Why not a new `operation: 'order'`: `sync_revisions.operation` and
 * `client_mutations.operation` are both ENUM('create','update','delete'), the
 * pull response pins the same three — and the push dispatcher routes anything
 * that is not create/update to applyDelete, so an unknown verb would silently
 * SOFT-DELETE the anchor row. The virtual-field route needs no protocol change
 * and gets LWW semantics for free (two concurrent reorders overlap on
 * `sort_order` and resolve wholesale by wall clock).
 */
let app;
let tables;
let owner;
let ws;

const CLIENT = newId();

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
  ws = owner.workspace.id;
});

afterEach(async () => {
  await app.close();
});

/** The workspace revision right now — what a synced client would push from. */
const wsRevision = () => Number(tables.workspaces.find((w) => w.id === ws).revision);

const push = (mutations, { baseRevision, clientId = CLIENT } = {}) =>
  app.inject({
    method: 'POST',
    url: '/api/v1/sync/push',
    headers: owner.headers,
    payload: { clientId, workspaceId: ws, baseRevision: baseRevision ?? wsRevision(), mutations },
  });

const orderMutation = (orderedIds, extra = {}) => ({
  clientMutationId: newId(),
  operation: 'update',
  entityType: 'quick_link',
  entityId: orderedIds[0], // the anchor is the head of the new order
  patch: { orderedIds, ...extra },
  localUpdatedAt: new Date().toISOString(),
});

const reorder = (orderedIds, extra = {}, options = {}) =>
  push([orderMutation(orderedIds, extra)], options);

const addLink = async (title) => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${ws}/quick-links`,
    headers: owner.headers,
    payload: { kind: 'url', url: `https://x.dev/${title}`, title },
  });
  expect(res.statusCode).toBe(201);
  return res.json();
};

const sortOf = (id) => Number(tables.quick_links.find((r) => r.id === id).sort_order);

describe('sync push — quick link reorder (OPH-197)', () => {
  it('rewrites every row from one mutation, one revision each', async () => {
    const a = await addLink('A');
    const b = await addLink('B');
    const c = await addLink('C');
    const before = Number(tables.workspaces.find((w) => w.id === ws).revision);

    const res = await reorder([c.id, a.id, b.id]);
    const result = res.json().results[0];
    expect(result.status).toBe('applied');

    expect(sortOf(c.id)).toBe(0);
    expect(sortOf(a.id)).toBe(1024);
    expect(sortOf(b.id)).toBe(2048);

    const logged = tables.sync_revisions.filter(
      (r) => r.entity_type === 'quick_link' && Number(r.revision) > before,
    );
    expect(logged).toHaveLength(3);
    expect(logged.every((r) => r.operation === 'update')).toBe(true);
    expect(logged.every((r) => JSON.parse(r.changed_fields).includes('sort_order'))).toBe(true);

    // client_mutations records the ANCHOR's revision — one mutation, one row.
    expect(result.revision).toBe(Number(tables.quick_links.find((r) => r.id === c.id).revision));
    const recorded = tables.client_mutations.filter((r) => r.client_id === CLIENT);
    expect(recorded).toHaveLength(1);
    expect(Number(recorded[0].result_revision)).toBe(result.revision);
  });

  it('requires the anchor to be part of the order and the order to be complete', async () => {
    const a = await addLink('A');
    const b = await addLink('B');

    const partial = await reorder([a.id]);
    expect(partial.json().results[0].errorCode).toBe('QUICK_LINK_ORDER_INCOMPLETE');
    expect(sortOf(b.id)).toBe(1024); // nothing moved

    const foreignAnchor = await push([{ ...orderMutation([a.id]), entityId: b.id }]);
    expect(foreignAnchor.json().results[0].errorCode).toBe('QUICK_LINK_ORDER_INCOMPLETE');
  });

  it('refuses to travel with other fields', async () => {
    const a = await addLink('A');
    const b = await addLink('B');
    const res = await reorder([a.id, b.id], { title: 'Aynı anda ad da' });
    expect(res.json().results[0].errorCode).toBe('SYNC_INVALID_PATCH');
  });

  it('fails atomically when the anchor was deleted meanwhile', async () => {
    const a = await addLink('A');
    const b = await addLink('B');
    await app.inject({
      method: 'DELETE',
      url: `/api/v1/quick-links/${a.id}`,
      headers: owner.headers,
    });

    const res = await reorder([a.id, b.id]);
    expect(res.json().results[0].errorCode).toBe('SYNC_ENTITY_DELETED');
    expect(sortOf(b.id)).toBe(1024); // no partial write
  });

  it('replays idempotently', async () => {
    const a = await addLink('A');
    const b = await addLink('B');
    const mutation = orderMutation([b.id, a.id]);
    const first = await push([mutation]);
    expect(first.json().results[0].status).toBe('applied');
    const revisionAfterFirst = Number(tables.workspaces.find((w) => w.id === ws).revision);

    const again = await push([mutation]);
    expect(again.json().results[0]).toMatchObject({ status: 'applied', replayed: true });
    expect(Number(tables.workspaces.find((w) => w.id === ws).revision)).toBe(revisionAfterFirst);
    expect(sortOf(b.id)).toBe(0);
    expect(sortOf(a.id)).toBe(1024);
  });

  it('a rename pushed after a reorder is not discarded (disjoint intents)', async () => {
    const a = await addLink('A');
    const b = await addLink('B');
    const base = wsRevision();
    expect((await reorder([b.id, a.id])).json().results[0].status).toBe('applied');

    // Pushed from BEFORE the reorder and with an older clock: only the
    // sibling rows' `sort_order` revisions are unattributed, and `title` does
    // not overlap them, so LWW has nothing to discard.
    const rename = await push(
      [
        {
          clientMutationId: newId(),
          operation: 'update',
          entityType: 'quick_link',
          entityId: a.id,
          patch: { title: 'Yeni ad' },
          localUpdatedAt: new Date(Date.now() - 60_000).toISOString(),
        },
      ],
      { baseRevision: base },
    );
    expect(rename.json().results[0].status).toBe('applied');
    expect(tables.quick_links.find((r) => r.id === a.id).title).toBe('Yeni ad');
  });
});
