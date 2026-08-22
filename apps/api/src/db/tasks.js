import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { nextMorningIn } from '../lib/time.js';
import { recordSyncWrite } from './sync.js';
import { notifyEntityWrite } from '../lib/ee.js';
import { reconcileTaskReminder } from './reminders.js';
import { propagateSeriesScope } from './task-series.js';

/**
 * The task domain layer (OPH-218, ADR-0022 §4): create, update, status
 * transitions, snooze, tags, checklist and the detail loader, extracted from
 * routes/tasks.js so REST and the MCP tools are ONE implementation — same
 * asserts, same revision bookkeeping, same reminder reconcile, in the same
 * transaction shape.
 *
 * OPH-218 moved create/complete/detail (all the MCP surface of the day needed).
 * OPH-262 moved the rest of the write verbs, because the second wave of tools
 * (`update_task`, `snooze_task`, checklist) would otherwise have had to choose
 * between duplicating the route closures and reaching past them — the exact
 * choice ADR-0022 §4 exists to remove. Same contract as the OPH-261 note
 * extraction: identical behaviour, and the proof is that the route suites pass
 * untouched.
 *
 * routes/sync.js still carries its own generic ENTITIES engine (different
 * shapes, LWW semantics); unifying it is deliberately out of scope here —
 * the remaining duplication is recorded, not hidden.
 *
 * Serialization stays in routes/tasks.js (`serializeTask` — the module
 * routes/sync.js already imports from); this module returns rows.
 */

// Snooze presets (BLUEPRINT §4.9): fixed offsets in minutes, plus
// tomorrow_morning which is 09:00 next day on the TASK's wall clock.
const SNOOZE_PRESET_MINUTES = { '5_min': 5, '30_min': 30, '1_hour': 60 };
export const SNOOZE_PRESETS = [...Object.keys(SNOOZE_PRESET_MINUTES), 'tomorrow_morning'];

// The task vocabulary. It lived in routes/tasks.js until OPH-262; the MCP tool
// schemas need it too, and a lib → routes import would be upside down
// (lib/ai/schema.js says so in as many words), so the domain layer owns it and
// the route re-exports for its existing importers.
export const TASK_STATUSES = [
  'inbox',
  'open',
  'scheduled',
  'in_progress',
  'waiting',
  'completed',
  'cancelled',
  'archived',
];
export const TASK_PRIORITIES = ['none', 'low', 'medium', 'high', 'urgent'];

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

/**
 * Applies a patch to a live task row: the asserts, the archived rule, the
 * urgent→acknowledgement default, the completion side effect, the revision and
 * the reminder reconcile — plus the series propagation, in the SAME
 * transaction (a half-applied scope would be a lie, OPH-206).
 *
 * `body` is the REST PATCH body (camelCase); `seriesScope` rides along in it.
 */
export async function updateTask(app, { row, userId, body }) {
  // Archived tasks accept exactly one write: a lone `status` unarchiving them.
  const isUnarchive =
    Object.keys(body).length === 1 && body.status !== undefined && body.status !== 'archived';
  if (!isUnarchive) assertNotArchived(app, row);

  if (body.projectId) await assertProjectUsable(app, body.projectId, row.workspace_id);
  if (body.parentTaskId) await assertParentUsable(app, body.parentTaskId, row.workspace_id, row.id);
  if (body.timezone !== undefined) assertValidTimezone(app, body.timezone);
  // Turning a task urgent defaults acknowledgement on unless set explicitly.
  if (body.isUrgent === true && body.requiresAcknowledgement === undefined) {
    body.requiresAcknowledgement = true;
  }

  const patch = {
    ...toRowPatch(body),
    ...(body.status !== undefined ? completionPatch(row.status, body.status) : {}),
  };
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
      .update({ ...patch, revision, updated_by: userId, updated_at: new Date() });
    const fresh = await trx('tasks').where({ id: row.id }).first();
    await reconcileTaskReminder(trx, { workspaceId: row.workspace_id, task: fresh });
    await propagateSeriesScope(trx, {
      workspaceId: row.workspace_id,
      task: fresh,
      patch: body,
      scope: body.seriesScope,
      userId,
    });
  });
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
    // A status change is the one task edit that reads as an EVENT rather than
    // a revision, so it is described for observers rather than merely counted.
    await notifyEntityWrite(app, trx, {
      workspaceId: row.workspace_id,
      entityType: 'task',
      entityId: row.id,
      operation: 'update',
      actorId: userId,
      before: { status: row.status },
      after: { status: toStatus },
    });
  });
}

/** Idempotent completion (REST semantics: no revision burned on a repeat). */
export async function completeTask(app, { userId, row }) {
  assertNotArchived(app, row);
  if (row.status === 'completed') return false;
  await applyStatusTransition(app, { userId, row, toStatus: 'completed' });
  return true;
}

/** Back to `open` — only a finished task can be reopened (OPH-033). */
export async function reopenTask(app, { userId, row }) {
  assertNotArchived(app, row);
  if (row.status !== 'completed' && row.status !== 'cancelled') {
    throw coded(
      app.httpErrors.conflict('Only completed or cancelled tasks can be reopened'),
      'TASK_INVALID_TRANSITION',
    );
  }
  await applyStatusTransition(app, { userId, row, toStatus: 'open' });
}

/**
 * Snoozes a task and silences its live alarm(s) until the same moment
 * (OPH-035/OPH-175). Exactly one of `preset` / `snoozeUntil` is used; a task
 * can own two alarms (reminder + deadline) — `reminderId` silences just that
 * one, omitting it silences all of them. Returns the instant chosen.
 */
export async function snoozeTask(app, { row, userId, preset, snoozeUntil, reminderId }) {
  assertNotArchived(app, row);
  if (row.status === 'completed' || row.status === 'cancelled') {
    throw coded(
      app.httpErrors.conflict('Completed or cancelled tasks cannot be snoozed'),
      'TASK_INVALID_TRANSITION',
    );
  }

  let until;
  if (snoozeUntil) {
    until = new Date(snoozeUntil);
    if (until.getTime() <= Date.now()) {
      throw coded(
        app.httpErrors.badRequest('snoozeUntil must be in the future'),
        'TASK_SNOOZE_IN_PAST',
      );
    }
  } else if (preset === 'tomorrow_morning') {
    until = nextMorningIn(row.timezone);
  } else {
    until = new Date(Date.now() + SNOOZE_PRESET_MINUTES[preset] * 60 * 1000);
  }

  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'task',
      entityId: row.id,
      operation: 'update',
      changedFields: ['snoozed_until'],
    });
    await trx('tasks').where({ id: row.id }).update({
      snoozed_until: until,
      revision,
      updated_by: userId,
      updated_at: new Date(),
    });

    const query = trx('reminders')
      .where({ task_id: row.id })
      .whereNull('deleted_at')
      .whereIn('status', ['scheduled', 'snoozed', 'delivered']);
    if (reminderId) query.where({ id: reminderId });
    const active = await query.orderBy('created_at', 'desc').select();
    for (const alarm of active) {
      const reminderRevision = await recordSyncWrite(trx, {
        workspaceId: row.workspace_id,
        entityType: 'reminder',
        entityId: alarm.id,
        operation: 'update',
        changedFields: ['status', 'snoozed_until', 'snooze_count'],
      });
      await trx('reminders')
        .where({ id: alarm.id })
        .update({
          status: 'snoozed',
          snoozed_until: until,
          // Which round the next ring is (OPH-177) — the alert says so.
          snooze_count: Number(alarm.snooze_count ?? 0) + 1,
          revision: reminderRevision,
          updated_at: new Date(),
        });
    }
  });

  return until;
}

/**
 * Replace-set of a task's tags — the `setNoteTags` twin (OPH-261). The links
 * are their own rows, so the revision is stamped on the TASK: that is what a
 * client pulls to learn its tags changed.
 */
export async function setTaskTags(app, { row, userId, tagIds }) {
  // The archived rule belongs HERE, not in the route: a tags-only `update_task`
  // from MCP never passes through [updateTask], and an archived task would have
  // slipped through with its tags rewritten while REST refused the same edit.
  assertNotArchived(app, row);
  const desired = [...new Set(tagIds)];
  await assertTagsUsable(app, desired, row.workspace_id);

  const current = (await app.db('task_tags').where({ task_id: row.id }).select('tag_id')).map(
    (r) => r.tag_id,
  );
  const toAdd = desired.filter((id) => !current.includes(id));
  const toRemove = current.filter((id) => !desired.includes(id));
  if (toAdd.length === 0 && toRemove.length === 0) return false;

  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'task',
      entityId: row.id,
      operation: 'update',
      changedFields: ['tags'],
    });
    if (toRemove.length > 0) {
      await trx('task_tags').where({ task_id: row.id }).whereIn('tag_id', toRemove).delete();
    }
    if (toAdd.length > 0) {
      await trx('task_tags').insert(toAdd.map((tagId) => ({ task_id: row.id, tag_id: tagId })));
    }
    await trx('tasks').where({ id: row.id }).update({
      revision,
      updated_by: userId,
      updated_at: new Date(),
    });
  });
  return true;
}

/** Loads one live checklist item of a task, or throws the route's 404. */
export async function loadChecklistItem(app, taskId, itemId) {
  const item = await app
    .db('checklist_items')
    .where({ id: itemId, task_id: taskId })
    .whereNull('deleted_at')
    .first();
  if (!item) {
    throw coded(app.httpErrors.notFound('Checklist item not found'), 'CHECKLIST_ITEM_NOT_FOUND');
  }
  return item;
}

/** Adds one checklist item to a live task. Returns the new id. */
export async function addChecklistItem(app, { task, title, sortOrder }) {
  assertNotArchived(app, task);
  const id = newId();
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: task.workspace_id,
      entityType: 'checklist_item',
      entityId: id,
      operation: 'create',
    });
    await trx('checklist_items').insert({
      id,
      task_id: task.id,
      title,
      ...(sortOrder !== undefined ? { sort_order: sortOrder } : {}),
      revision,
    });
  });
  return id;
}

/** Patches one checklist item (`title` / `isDone` / `sortOrder`). */
export async function updateChecklistItem(app, { task, item, body, userId = null }) {
  assertNotArchived(app, task);
  const patch = {};
  if ('title' in body) patch.title = body.title;
  if ('isDone' in body) patch.is_done = body.isDone;
  if ('sortOrder' in body) patch.sort_order = body.sortOrder;

  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: task.workspace_id,
      entityType: 'checklist_item',
      entityId: item.id,
      operation: 'update',
      changedFields: Object.keys(patch),
    });
    await trx('checklist_items')
      .where({ id: item.id })
      .update({ ...patch, revision, updated_at: new Date() });
    await notifyEntityWrite(app, trx, {
      workspaceId: task.workspace_id,
      entityType: 'checklist_item',
      entityId: item.id,
      operation: 'update',
      actorId: userId,
      // The parent is part of the change here: a subtask being ticked is a
      // fact about the TASK, and an observer that had to look it up would be
      // querying inside somebody else's transaction to learn something the
      // caller already had.
      before: { isDone: Boolean(item.is_done), taskId: task.id, title: item.title },
      after: { isDone: Boolean(patch.is_done ?? item.is_done), taskId: task.id, title: patch.title ?? item.title },
    });
  });
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
