import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { recordSyncWrite } from './sync.js';
import { reconcileTaskReminder } from './reminders.js';

/**
 * The task domain layer (OPH-218, ADR-0022 §4): create, status transitions
 * and the detail loader, extracted from routes/tasks.js so REST and the MCP
 * tools are ONE implementation — same asserts, same revision bookkeeping,
 * same reminder reconcile, in the same transaction shape.
 *
 * routes/sync.js still carries its own generic ENTITIES engine (different
 * shapes, LWW semantics); unifying it is deliberately out of scope here —
 * the remaining duplication is recorded, not hidden.
 *
 * Serialization stays in routes/tasks.js (`serializeTask` — the module
 * routes/sync.js already imports from); this module returns rows.
 */

const CAMEL_TO_SNAKE = {
  title: 'title',
  description: 'description',
  projectId: 'project_id',
  parentTaskId: 'parent_task_id',
  status: 'status',
  priority: 'priority',
  colorRgb: 'color_rgb',
  startAt: 'start_at',
  dueAt: 'due_at',
  scheduledStartAt: 'scheduled_start_at',
  scheduledEndAt: 'scheduled_end_at',
  remindAt: 'remind_at',
  timezone: 'timezone',
  isUrgent: 'is_urgent',
  requiresAcknowledgement: 'requires_acknowledgement',
  estimatedMinutes: 'estimated_minutes',
  actualMinutes: 'actual_minutes',
  sortOrder: 'sort_order',
  calendarMirrorEnabled: 'calendar_mirror_enabled',
  alarmsMutedAt: 'alarms_muted_at',
};

const DATE_FIELDS = new Set([
  'start_at',
  'due_at',
  'scheduled_start_at',
  'scheduled_end_at',
  'remind_at',
  'alarms_muted_at',
]);

export function toRowPatch(body) {
  const row = {};
  for (const [camel, snake] of Object.entries(CAMEL_TO_SNAKE)) {
    if (camel in body) {
      const value = body[camel];
      row[snake] = DATE_FIELDS.has(snake) && value != null ? new Date(value) : value;
    }
  }
  return row;
}

/** Status side effects shared by PATCH and the transition endpoints. */
export function completionPatch(fromStatus, toStatus) {
  if (toStatus === 'completed' && fromStatus !== 'completed') {
    return { completed_at: new Date() };
  }
  if (toStatus !== 'completed' && fromStatus === 'completed') {
    return { completed_at: null };
  }
  return {};
}

export async function loadTask(app, id) {
  const row = await app.db('tasks').where({ id }).whereNull('deleted_at').first();
  if (!row) throw coded(app.httpErrors.notFound('Task not found'), 'TASK_NOT_FOUND');
  return row;
}

// OPH-034 — remind_at needs a real timezone for alarm math. The column has a
// default, so validity (not presence) is what we enforce.
export function assertValidTimezone(app, tz) {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
  } catch {
    throw coded(app.httpErrors.badRequest(`Unknown timezone: ${tz}`), 'TASK_INVALID_TIMEZONE');
  }
}

// OPH-033 — archived tasks are immutable (the sole allowed write is
// unarchiving via PATCH { status }); everything else answers 409.
export function assertNotArchived(app, row) {
  if (row.status === 'archived') {
    throw coded(
      app.httpErrors.conflict('Archived tasks are immutable — unarchive first'),
      'TASK_ARCHIVED',
    );
  }
}

export async function assertProjectUsable(app, projectId, workspaceId) {
  const project = await app
    .db('projects')
    .where({ id: projectId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first('id');
  if (!project) {
    throw coded(
      app.httpErrors.badRequest('projectId does not reference a project in this workspace'),
      'TASK_INVALID_PROJECT',
    );
  }
}

/** Parent must be a live task in the same workspace and not create a cycle. */
export async function assertParentUsable(app, parentTaskId, workspaceId, childId) {
  if (parentTaskId === childId) {
    throw coded(app.httpErrors.badRequest('A task cannot be its own parent'), 'TASK_PARENT_CYCLE');
  }
  const parent = await app
    .db('tasks')
    .where({ id: parentTaskId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first('id', 'parent_task_id');
  if (!parent) {
    throw coded(
      app.httpErrors.badRequest('parentTaskId does not reference a task in this workspace'),
      'TASK_INVALID_PARENT',
    );
  }
  // Walk up the ancestor chain — attaching below one of our own descendants
  // (or ourselves) would loop forever.
  let cursor = parent.parent_task_id;
  for (let depth = 0; cursor && depth < 100; depth += 1) {
    if (cursor === childId) {
      throw coded(
        app.httpErrors.badRequest('parentTaskId would create a subtask cycle'),
        'TASK_PARENT_CYCLE',
      );
    }
    const next = await app.db('tasks').where({ id: cursor }).first('parent_task_id');
    cursor = next?.parent_task_id ?? null;
  }
}

export async function assertTagsUsable(app, tagIds, workspaceId) {
  if (tagIds.length === 0) return;
  const rows = await app
    .db('tags')
    .whereIn('id', tagIds)
    .where({ workspace_id: workspaceId })
    .whereNull('deleted_at')
    .select('id');
  if (rows.length !== new Set(tagIds).size) {
    throw coded(
      app.httpErrors.badRequest('tagIds contains tags that do not exist in this workspace'),
      'TASK_INVALID_TAG',
    );
  }
}

/**
 * Creates a task with full REST semantics: asserts, urgent→acknowledgement
 * default, sync revision, tag links and reminder reconcile in ONE
 * transaction. Returns the new task id.
 */
export async function createTask(app, { workspaceId, userId, body: rawBody }) {
  const { tagIds = [], ...body } = rawBody;
  if (body.projectId) await assertProjectUsable(app, body.projectId, workspaceId);
  if (body.parentTaskId) await assertParentUsable(app, body.parentTaskId, workspaceId, null);
  await assertTagsUsable(app, tagIds, workspaceId);
  if (body.timezone !== undefined) assertValidTimezone(app, body.timezone);
  // Urgent alarms demand acknowledgement unless the caller opts out (OPH-034).
  if (body.isUrgent === true && body.requiresAcknowledgement === undefined) {
    body.requiresAcknowledgement = true;
  }

  const id = newId();
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: id,
      operation: 'create',
    });
    await trx('tasks').insert({
      id,
      workspace_id: workspaceId,
      ...toRowPatch(body),
      created_by: userId,
      updated_by: userId,
      revision,
    });
    if (tagIds.length > 0) {
      await trx('task_tags').insert(
        [...new Set(tagIds)].map((tagId) => ({ task_id: id, tag_id: tagId })),
      );
    }
    const fresh = await trx('tasks').where({ id }).first();
    await reconcileTaskReminder(trx, { workspaceId, task: fresh });
  });
  return id;
}

/** One status transition with the shared revision + reminder bookkeeping. */
export async function applyStatusTransition(app, { userId, row, toStatus }) {
  const patch = { status: toStatus, ...completionPatch(row.status, toStatus) };
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'task',
      entityId: row.id,
      operation: 'update',
      changedFields: Object.keys(patch),
    });
    await trx('tasks')
      .where({ id: row.id })
      .update({
        ...patch,
        revision,
        updated_by: userId,
        updated_at: new Date(),
      });
    const fresh = await trx('tasks').where({ id: row.id }).first();
    await reconcileTaskReminder(trx, { workspaceId: row.workspace_id, task: fresh });
  });
}

/** Idempotent completion (REST semantics: no revision burned on a repeat). */
export async function completeTask(app, { userId, row }) {
  assertNotArchived(app, row);
  if (row.status === 'completed') return false;
  await applyStatusTransition(app, { userId, row, toStatus: 'completed' });
  return true;
}

/** The detail loader's rows: task + sorted tag ids + live checklist rows. */
export async function taskDetailRows(app, id) {
  const row = await loadTask(app, id);
  const [tagRows, checklistRows] = await Promise.all([
    app.db('task_tags').where({ task_id: id }).select('tag_id'),
    app
      .db('checklist_items')
      .where({ task_id: id })
      .whereNull('deleted_at')
      .orderBy('sort_order', 'asc')
      .orderBy('created_at', 'asc')
      .select(),
  ]);
  return {
    row,
    tagIds: tagRows.map((r) => r.tag_id).sort(),
    checklist: checklistRows,
  };
}
