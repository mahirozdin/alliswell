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

// The project vocabulary. Like the task statuses in OPH-262, it lives in the
// domain layer because the MCP tool schemas need it and a lib → routes import
// would be upside down; routes/projects.js re-exports for its own importers.
export const PROJECT_STATUSES = ['active', 'paused', 'completed', 'archived'];

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

/**
 * Open (not completed/cancelled/archived) task counts, batched — never N+1.
 *
 * ONE query for every project, tallied in JS. It was written in OPH-261 as a
 * `groupBy` + `count` aggregate and had no caller until OPH-263 tried to use
 * it — at which point it turned out no unit test could ever have run it: the
 * in-memory knex double has no `groupBy`, and the real chain
 * (`.groupBy().select().count()`) needs a builder that stays chainable after
 * `select`. A tally over one column of one query costs a personal workspace
 * nothing and can actually be exercised; an aggregate nobody can test is how
 * this function reached today unreached.
 */
export async function openTaskCounts(app, projectIds) {
  if (projectIds.length === 0) return new Map();
  const rows = await app
    .db('tasks')
    .whereIn('project_id', projectIds)
    .whereNull('deleted_at')
    .whereNotIn('status', ['completed', 'cancelled', 'archived'])
    .select('project_id');
  const counts = new Map();
  for (const row of rows) {
    counts.set(row.project_id, (counts.get(row.project_id) ?? 0) + 1);
  }
  return counts;
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
