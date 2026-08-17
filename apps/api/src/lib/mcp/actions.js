import { newId } from '../ids.js';

/**
 * The MCP write ledger (OPH-262, ADR-0022 Decision 4).
 *
 * Every MCP write owes two rows: an `ai_action_log(source='mcp')` entry — the
 * user's record of what the AI did in their workspace — and, when the host
 * sent an `idempotencyKey`, an `mcp_mutations` row so a retry replays instead
 * of duplicating. Until this module those two inserts were copy-pasted inside
 * `create_task` and `complete_task` (finding #8 of the Epic 25 survey), which
 * is exactly the shape that grows a hole the sixth time it is copied.
 *
 * **Ledger LAST** is preserved on purpose: the entity write commits first, and
 * only then does the ledger. A crash in between re-creates on retry rather
 * than replaying a half-made entity; the unique index on `mcp_mutations`
 * breaks the race. That trade-off is documented, not accidental.
 */

/** Has this idempotency key already been spent in this workspace? */
export async function findMcpReplay(app, auth, idempotencyKey) {
  if (!idempotencyKey) return null;
  const row = await app
    .db('mcp_mutations')
    .where({
      workspace_id: auth.workspaceId,
      user_id: auth.userId,
      idempotency_key: idempotencyKey,
    })
    .first();
  return row ?? null;
}

/**
 * Writes the audit row (and the idempotency row, when a key was given).
 * Call AFTER the entity write has committed.
 *
 * @param {object} app fastify instance
 * @param {{workspaceId: string, userId: string, clientId: string}} auth
 * @param {object} options
 * @param {string} [options.idempotencyKey] the host's retry key
 * @param {string} options.entityType 'task' | 'checklist_item' | 'reminder' | …
 * @param {string} options.entityId the row the tool touched
 * @param {object} options.proposal what the host asked for (stored verbatim)
 * @param {Array<{type: string, id: string}>} [options.entityRefs] defaults to
 *   the single entity above
 */
export async function recordMcpAction(
  app,
  auth,
  { idempotencyKey, entityType, entityId, proposal, entityRefs },
) {
  await app.db('ai_action_log').insert({
    id: newId(),
    workspace_id: auth.workspaceId,
    user_id: auth.userId,
    source: 'mcp',
    proposal: JSON.stringify(proposal),
    accepted: true,
    entity_refs: JSON.stringify(entityRefs ?? [{ type: entityType, id: entityId }]),
    decided_at: new Date(),
  });

  if (!idempotencyKey) return;
  try {
    await app.db('mcp_mutations').insert({
      id: newId(),
      workspace_id: auth.workspaceId,
      user_id: auth.userId,
      client_id: auth.clientId,
      idempotency_key: idempotencyKey,
      entity_type: entityType,
      entity_id: entityId,
    });
  } catch (err) {
    // Two concurrent retries: the loser's row is redundant, not an error.
    if (err?.code !== 'ER_DUP_ENTRY') throw err;
  }
}
