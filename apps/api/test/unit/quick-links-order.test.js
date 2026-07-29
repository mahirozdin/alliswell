import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';

/**
 * OPH-197 — `PUT /workspaces/:id/quick-links/order`. The payload must be the
 * caller's EXACT live id set: `sort_order = index * step` only defines a total
 * order if the list is total, so a partial list would leave unlisted rows at
 * stale offsets that interleave arbitrarily. The refusal is 422 — the body is
 * well-formed, the request is not processable.
 */
describe('quick link order (OPH-197)', () => {
  let app;
  let tables;
  let owner;
  let ws;

  beforeEach(async () => {
    ({ app, tables } = await buildTestApp());
    owner = await registerUser(app, { email: 'owner@example.com' });
    ws = owner.workspace.id;
  });

  const add = async (title) => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/quick-links`,
      headers: owner.headers,
      payload: { kind: 'url', url: `https://x.dev/${title}`, title },
    });
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const order = (orderedIds, who = owner) =>
    app.inject({
      method: 'PUT',
      url: `/api/v1/workspaces/${ws}/quick-links/order`,
      headers: who.headers,
      payload: { orderedIds },
    });

  it('writes the whole order and gives every row its own revision', async () => {
    const a = await add('A');
    const b = await add('B');
    const c = await add('C');
    const before = tables.workspaces.find((w) => w.id === ws).revision;

    const res = await order([c.id, a.id, b.id]);
    expect(res.statusCode).toBe(200);
    expect(res.json().items.map((i) => i.title)).toEqual(['C', 'A', 'B']);
    expect(res.json().items.map((i) => i.sortOrder)).toEqual([0, 1024, 2048]);

    // Three rows moved → three revisions, so every device converges.
    const after = tables.workspaces.find((w) => w.id === ws).revision;
    expect(Number(after) - Number(before)).toBe(3);
    const logged = tables.sync_revisions.filter(
      (r) => r.entity_type === 'quick_link' && Number(r.revision) > Number(before),
    );
    expect(logged).toHaveLength(3);
    expect(logged.every((r) => r.operation === 'update')).toBe(true);
    expect(JSON.parse(logged[0].changed_fields)).toEqual(['sort_order']);
  });

  it('refuses a partial list, duplicates, foreign ids and an empty list', async () => {
    const a = await add('A');
    const b = await add('B');

    const partial = await order([a.id]);
    expect(partial.statusCode).toBe(422);
    expect(partial.json().code).toBe('QUICK_LINK_ORDER_INCOMPLETE');

    const dupes = await order([a.id, a.id]);
    expect(dupes.statusCode).toBe(422);

    // Another member's shortcut is not part of "my list", even though it lives
    // in the same workspace (ADR-0018).
    const member = await registerUser(app, { email: 'member@example.com' });
    addMember(tables, { workspaceId: ws, user: member.user, role: 'member' });
    const theirs = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/quick-links`,
      headers: member.headers,
      payload: { kind: 'url', url: 'https://x.dev/m', title: 'M' },
    });
    const foreign = await order([a.id, theirs.json().id]);
    expect(foreign.statusCode).toBe(422);

    const empty = await order([]);
    expect(empty.statusCode).toBe(400); // minItems — malformed, not unprocessable

    // Nothing moved through any of the refusals.
    expect(tables.quick_links.filter((r) => r.user_id === owner.user.id).map((r) => r.sort_order)) //
      .toEqual([a.sortOrder, b.sortOrder]);
  });
});
