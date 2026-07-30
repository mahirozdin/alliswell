import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-219 — the decision endpoint: append-once evidence with retry-safe
 * idempotency (the app's offline report queue depends on it).
 */

let app;
let tables;
let owner;
let actionId;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'ai-actions@example.com' });
  actionId = newId();
  tables.ai_action_log.push({
    id: actionId,
    workspace_id: owner.workspace.id,
    user_id: owner.user.id,
    source: 'voice',
    request_id: newId(),
    proposal: JSON.stringify({ intent: 'create_tasks', tasks: [{ title: 'x', confidence: 1 }] }),
    accepted: null,
    entity_refs: null,
    decided_at: null,
    created_at: new Date(),
  });
});

const decide = (payload, headers = owner.headers, id = actionId) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/ai/actions/${id}/decision`,
    headers,
    payload,
  });

describe('POST /ai/actions/:id/decision (OPH-219)', () => {
  it('records an accept with entity refs and the decision time', async () => {
    const taskId = newId();
    const res = await decide({ accepted: true, entityRefs: [{ type: 'task', id: taskId }] });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accepted).toBe(true);
    expect(body.entityRefs).toEqual([{ type: 'task', id: taskId }]);
    expect(body.decidedAt).not.toBeNull();
    expect(body.proposal.tasks[0].title).toBe('x');
  });

  it('records a reject', async () => {
    const res = await decide({ accepted: false });
    expect(res.statusCode).toBe(200);
    expect(res.json().accepted).toBe(false);
  });

  it('repeating the SAME decision is a quiet 200 no-op (retry-safe)', async () => {
    await decide({ accepted: true, entityRefs: [{ type: 'task', id: newId() }] });
    const again = await decide({ accepted: true });
    expect(again.statusCode).toBe(200);
    expect(again.json().accepted).toBe(true);
    // The original refs survive — the no-op wrote nothing.
    expect(again.json().entityRefs).toHaveLength(1);
  });

  it('a DIFFERENT second decision is a 409 — evidence is append-once', async () => {
    await decide({ accepted: true });
    const flip = await decide({ accepted: false });
    expect(flip.statusCode).toBe(409);
    expect(flip.json().code).toBe('AI_ACTION_DECIDED');
  });

  it('hides a co-member’s action as 404 and an unknown id as 404', async () => {
    const mate = await registerUser(app, { email: 'ai-actions-mate@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: mate.user });
    const res = await decide({ accepted: true }, mate.headers);
    expect(res.statusCode).toBe(404);
    expect(res.json().code).toBe('AI_ACTION_NOT_YOURS');

    const missing = await decide({ accepted: true }, owner.headers, newId());
    expect(missing.statusCode).toBe(404);
    expect(missing.json().code).toBe('AI_ACTION_NOT_FOUND');
  });
});
