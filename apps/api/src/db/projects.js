import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { recordSyncWrite } from './sync.js';

/**
 * The project domain (OPH-261) — the third of the extractions ADR-0022 §4 asks
 * for, so OPH-263's `list_projects` / `create_project` / `update_project` tools
 * call this rather than writing their own SQL.
 *
 * The archive cascade deliberately stayed in `routes/projects.js` for now: it
 * reaches across tasks and notes and has its own confirm semantics, so moving
 * it is a bigger question than this task's "same behaviour, new home" contract
 * allows. Recorded rather than silently skipped.
 */

export async function loadProject(app, id) {
  const row = await app.db('projects').where({ id }).whereNull('deleted_at').first();
  if (!row) throw coded(app.httpErrors.notFound('Project not found'), 'PROJECT_NOT_FOUND');
  return row;
}

export async function assertReadmeNoteUsable(app, noteId, workspaceId) {
  const note = await app
    .db('notes')
    .where({ id: noteId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first('id');
  if (!note) {
    throw coded(
      app.httpErrors.badRequest('readmeNoteId does not reference a note in this workspace'),
      'PROJECT_INVALID_README_NOTE',
    );
  }
}

/** Workspace projects in the product's own order: manual, then creation. */
export async function listProjects(app, workspaceId, { status } = {}) {
  let query = app
    .db('projects')
    .where({ workspace_id: workspaceId })
    .whereNull('deleted_at')
    .orderBy('sort_order', 'asc')
    .orderBy('created_at', 'asc');
  if (status) query = query.where({ status });
  return query.select();
}

/** Open (not completed/cancelled/archived) task counts, batched — never N+1. */
export async function openTaskCounts(app, projectIds) {
  if (projectIds.length === 0) return new Map();
  const rows = await app
    .db('tasks')
    .whereIn('project_id', projectIds)
    .whereNull('deleted_at')
    .whereNotIn('status', ['completed', 'cancelled', 'archived'])
    .groupBy('project_id')
    .select('project_id')
    .count({ count: '*' });
  return new Map(rows.map((r) => [r.project_id, Number(r.count)]));
}

export async function createProject(app, { workspaceId, userId, body, toRowPatch }) {
  if (body.readmeNoteId) await assertReadmeNoteUsable(app, body.readmeNoteId, workspaceId);

  const id = newId();
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'project',
      entityId: id,
      operation: 'create',
    });
    await trx('projects').insert({
      id,
      workspace_id: workspaceId,
      ...toRowPatch(body),
      created_by: userId,
      updated_by: userId,
      revision,
    });
  });
  return id;
}

export async function updateProject(app, { row, userId, body, toRowPatch }) {
  if (body.readmeNoteId) await assertReadmeNoteUsable(app, body.readmeNoteId, row.workspace_id);

  const patch = toRowPatch(body);
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'project',
      entityId: row.id,
      operation: 'update',
      changedFields: Object.keys(patch),
    });
    await trx('projects')
      .where({ id: row.id })
      .update({ ...patch, revision, updated_by: userId, updated_at: new Date() });
  });
}
