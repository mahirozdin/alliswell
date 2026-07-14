import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { recordSyncWrite } from '../db/sync.js';
import { reconcileTaskReminder } from '../db/reminders.js';
import { COLOR_PATTERN } from './projects.js';

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

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const MAX_PAGE_SIZE = 200;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const taskSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'title', 'status', 'priority', 'revision'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    projectId: { type: ['string', 'null'] },
    parentTaskId: { type: ['string', 'null'] },
    title: { type: 'string' },
    description: { type: ['string', 'null'] },
    status: { type: 'string', enum: TASK_STATUSES },
    priority: { type: 'string', enum: TASK_PRIORITIES },
    colorRgb: { type: ['string', 'null'] },
    startAt: { type: ['string', 'null'] },
    dueAt: { type: ['string', 'null'] },
    scheduledStartAt: { type: ['string', 'null'] },
    scheduledEndAt: { type: ['string', 'null'] },
    remindAt: { type: ['string', 'null'] },
    snoozedUntil: { type: ['string', 'null'] },
    timezone: { type: 'string' },
    isUrgent: { type: 'boolean' },
    requiresAcknowledgement: { type: 'boolean' },
    repeatRule: { type: ['string', 'null'] },
    estimatedMinutes: { type: ['integer', 'null'] },
    actualMinutes: { type: ['integer', 'null'] },
    sortOrder: { type: 'integer' },
    completedAt: { type: ['string', 'null'] },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

const taskDetailSchema = {
  ...taskSchema,
  properties: {
    ...taskSchema.properties,
    tagIds: { type: 'array', items: { type: 'string' } },
    checklist: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          isDone: { type: 'boolean' },
          sortOrder: { type: 'integer' },
          revision: { type: 'integer' },
        },
      },
    },
  },
};

const checklistItemSchema = {
  type: 'object',
  required: ['id', 'taskId', 'title', 'isDone', 'sortOrder', 'revision'],
  properties: {
    id: { type: 'string' },
    taskId: { type: 'string' },
    title: { type: 'string' },
    isDone: { type: 'boolean' },
    sortOrder: { type: 'integer' },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

// Writable fields shared by create and patch. Status/priority transitions get
// dedicated rules in OPH-033; remind/urgent semantics in OPH-034; snoozing has
// its own endpoint (OPH-035) — snoozed_until/completed_at are not writable here.
const writableProps = {
  title: { type: 'string', minLength: 1, maxLength: 500 },
  description: { type: ['string', 'null'], maxLength: 65535 },
  projectId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
  parentTaskId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
  status: { type: 'string', enum: TASK_STATUSES },
  priority: { type: 'string', enum: TASK_PRIORITIES },
  colorRgb: { anyOf: [{ type: 'null' }, { type: 'string', pattern: COLOR_PATTERN }] },
  startAt: { type: ['string', 'null'], format: 'date-time' },
  dueAt: { type: ['string', 'null'], format: 'date-time' },
  scheduledStartAt: { type: ['string', 'null'], format: 'date-time' },
  scheduledEndAt: { type: ['string', 'null'], format: 'date-time' },
  remindAt: { type: ['string', 'null'], format: 'date-time' },
  timezone: { type: 'string', minLength: 1, maxLength: 64 },
  isUrgent: { type: 'boolean' },
  requiresAcknowledgement: { type: 'boolean' },
  repeatRule: { type: ['string', 'null'], maxLength: 2000 },
  estimatedMinutes: { type: ['integer', 'null'], minimum: 0, maximum: 60000 },
  actualMinutes: { type: ['integer', 'null'], minimum: 0, maximum: 60000 },
  sortOrder: { type: 'integer', minimum: -1000000, maximum: 1000000 },
};

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
  repeatRule: 'repeat_rule',
  estimatedMinutes: 'estimated_minutes',
  actualMinutes: 'actual_minutes',
  sortOrder: 'sort_order',
};

const DATE_FIELDS = new Set([
  'start_at',
  'due_at',
  'scheduled_start_at',
  'scheduled_end_at',
  'remind_at',
]);

function toRowPatch(body) {
  const row = {};
  for (const [camel, snake] of Object.entries(CAMEL_TO_SNAKE)) {
    if (camel in body) {
      const value = body[camel];
      row[snake] = DATE_FIELDS.has(snake) && value != null ? new Date(value) : value;
    }
  }
  return row;
}

export function serializeTask(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    projectId: row.project_id ?? null,
    parentTaskId: row.parent_task_id ?? null,
    title: row.title,
    description: row.description ?? null,
    status: row.status,
    priority: row.priority,
    colorRgb: row.color_rgb ?? null,
    startAt: toIso(row.start_at),
    dueAt: toIso(row.due_at),
    scheduledStartAt: toIso(row.scheduled_start_at),
    scheduledEndAt: toIso(row.scheduled_end_at),
    remindAt: toIso(row.remind_at),
    snoozedUntil: toIso(row.snoozed_until),
    timezone: row.timezone,
    isUrgent: Boolean(row.is_urgent),
    requiresAcknowledgement: Boolean(row.requires_acknowledgement),
    repeatRule: row.repeat_rule ?? null,
    estimatedMinutes: row.estimated_minutes ?? null,
    actualMinutes: row.actual_minutes ?? null,
    sortOrder: row.sort_order,
    completedAt: toIso(row.completed_at),
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

function serializeChecklistItem(row) {
  return {
    id: row.id,
    taskId: row.task_id,
    title: row.title,
    isDone: Boolean(row.is_done),
    sortOrder: row.sort_order,
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

export default async function taskRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  async function loadTask(id) {
    const row = await app.db('tasks').where({ id }).whereNull('deleted_at').first();
    if (!row) throw coded(app.httpErrors.notFound('Task not found'), 'TASK_NOT_FOUND');
    return row;
  }

  // OPH-034 — remind_at needs a real timezone for alarm math. The column has a
  // default, so validity (not presence) is what we enforce; aliases like
  // Asia/Istanbul are fine — Intl throws on genuinely unknown zones.
  function assertValidTimezone(tz) {
    try {
      new Intl.DateTimeFormat('en-US', { timeZone: tz });
    } catch {
      throw coded(app.httpErrors.badRequest(`Unknown timezone: ${tz}`), 'TASK_INVALID_TIMEZONE');
    }
  }

  // OPH-033 — archived tasks are immutable (the sole allowed write is
  // unarchiving via PATCH { status }); everything else answers 409.
  function assertNotArchived(row) {
    if (row.status === 'archived') {
      throw coded(
        app.httpErrors.conflict('Archived tasks are immutable — unarchive first'),
        'TASK_ARCHIVED',
      );
    }
  }

  /** Status side effects shared by PATCH and the transition endpoints. */
  function completionPatch(fromStatus, toStatus) {
    if (toStatus === 'completed' && fromStatus !== 'completed') {
      return { completed_at: new Date() };
    }
    if (toStatus !== 'completed' && fromStatus === 'completed') {
      return { completed_at: null };
    }
    return {};
  }

  async function assertProjectUsable(projectId, workspaceId) {
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
  async function assertParentUsable(parentTaskId, workspaceId, childId) {
    if (parentTaskId === childId) {
      throw coded(
        app.httpErrors.badRequest('A task cannot be its own parent'),
        'TASK_PARENT_CYCLE',
      );
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

  async function assertTagsUsable(tagIds, workspaceId) {
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

  // ── Collection: create + filtered, cursor-paginated list ─────────────────

  app.post(
    '/workspaces/:workspaceId/tasks',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['title'],
          properties: {
            ...writableProps,
            tagIds: { type: 'array', maxItems: 50, items: ULID_PARAM },
          },
        },
        response: { 201: taskDetailSchema, 400: errorResponseSchema, 403: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      const { tagIds = [], ...body } = request.body;
      if (body.projectId) await assertProjectUsable(body.projectId, workspaceId);
      if (body.parentTaskId) await assertParentUsable(body.parentTaskId, workspaceId, null);
      await assertTagsUsable(tagIds, workspaceId);
      if (body.timezone !== undefined) assertValidTimezone(body.timezone);
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
          created_by: request.user.id,
          updated_by: request.user.id,
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

      return reply.code(201).send(await taskDetail(id));
    },
  );

  app.get(
    '/workspaces/:workspaceId/tasks',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            status: { type: 'array', items: { type: 'string', enum: TASK_STATUSES } },
            projectId: ULID_PARAM,
            parentTaskId: ULID_PARAM,
            tagId: ULID_PARAM,
            dueFrom: { type: 'string', format: 'date-time' },
            dueTo: { type: 'string', format: 'date-time' },
            urgent: { type: 'boolean' },
            limit: { type: 'integer', minimum: 1, maximum: MAX_PAGE_SIZE, default: 50 },
            cursor: ULID_PARAM,
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              items: { type: 'array', items: taskSchema },
              nextCursor: { type: ['string', 'null'] },
            },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const q = request.query;

      // ULIDs sort by creation time, so (order by id desc, id < cursor) is a
      // stable newest-first cursor with no offset drift.
      let query = app
        .db('tasks')
        .where({ workspace_id: workspaceId })
        .whereNull('deleted_at')
        .orderBy('id', 'desc')
        .limit(q.limit);
      if (q.cursor) query = query.where('id', '<', q.cursor);
      if (q.status?.length) query = query.whereIn('status', q.status);
      if (q.projectId) query = query.where({ project_id: q.projectId });
      if (q.parentTaskId) query = query.where({ parent_task_id: q.parentTaskId });
      if (q.urgent !== undefined) query = query.where({ is_urgent: q.urgent });
      if (q.dueFrom) query = query.where('due_at', '>=', new Date(q.dueFrom));
      if (q.dueTo) query = query.where('due_at', '<=', new Date(q.dueTo));
      if (q.tagId) {
        const tagged = await app.db('task_tags').where({ tag_id: q.tagId }).select('task_id');
        query = query.whereIn(
          'id',
          tagged.map((r) => r.task_id),
        );
      }

      const rows = await query.select();
      return {
        items: rows.map(serializeTask),
        nextCursor: rows.length === q.limit ? rows.at(-1).id : null,
      };
    },
  );

  // ── Single task ───────────────────────────────────────────────────────────

  async function taskDetail(id) {
    const row = await loadTask(id);
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
      ...serializeTask(row),
      tagIds: tagRows.map((r) => r.tag_id).sort(),
      checklist: checklistRows.map(serializeChecklistItem),
    };
  }

  app.get(
    '/tasks/:taskId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        response: { 200: taskDetailSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      return taskDetail(row.id);
    },
  );

  app.patch(
    '/tasks/:taskId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: writableProps,
        },
        response: {
          200: taskDetailSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      const body = request.body;
      // Archived tasks accept exactly one write: a lone `status` unarchiving them.
      const isUnarchive =
        Object.keys(body).length === 1 && body.status !== undefined && body.status !== 'archived';
      if (!isUnarchive) assertNotArchived(row);

      if (body.projectId) await assertProjectUsable(body.projectId, row.workspace_id);
      if (body.parentTaskId) await assertParentUsable(body.parentTaskId, row.workspace_id, row.id);
      if (body.timezone !== undefined) assertValidTimezone(body.timezone);
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
          .update({
            ...patch,
            revision,
            updated_by: request.user.id,
            updated_at: new Date(),
          });
        const fresh = await trx('tasks').where({ id: row.id }).first();
        await reconcileTaskReminder(trx, { workspaceId: row.workspace_id, task: fresh });
      });

      return taskDetail(row.id);
    },
  );

  // ── Status transitions (OPH-033) ──────────────────────────────────────────

  async function applyTransition(request, row, toStatus) {
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
          updated_by: request.user.id,
          updated_at: new Date(),
        });
      const fresh = await trx('tasks').where({ id: row.id }).first();
      await reconcileTaskReminder(trx, { workspaceId: row.workspace_id, task: fresh });
    });
  }

  const transitionSchema = {
    params: { type: 'object', properties: { taskId: ULID_PARAM } },
    response: {
      200: taskDetailSchema,
      403: errorResponseSchema,
      404: errorResponseSchema,
      409: errorResponseSchema,
    },
  };

  app.post('/tasks/:taskId/complete', { ...auth, schema: transitionSchema }, async (request) => {
    const row = await loadTask(request.params.taskId);
    await app.requireWorkspaceMember(request, row.workspace_id);
    assertNotArchived(row);

    // Idempotent: completing a completed task changes nothing and costs no revision.
    if (row.status !== 'completed') await applyTransition(request, row, 'completed');
    return taskDetail(row.id);
  });

  app.post('/tasks/:taskId/reopen', { ...auth, schema: transitionSchema }, async (request) => {
    const row = await loadTask(request.params.taskId);
    await app.requireWorkspaceMember(request, row.workspace_id);
    assertNotArchived(row);

    if (row.status !== 'completed' && row.status !== 'cancelled') {
      throw coded(
        app.httpErrors.conflict('Only completed or cancelled tasks can be reopened'),
        'TASK_INVALID_TRANSITION',
      );
    }
    await applyTransition(request, row, 'open');
    return taskDetail(row.id);
  });

  app.delete(
    '/tasks/:taskId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      await app.db.transaction(async (trx) => {
        // Soft delete the whole subtree; every task is its own sync entity, so
        // each level gets its own revision + log row.
        let frontier = [row.id];
        const seen = new Set(frontier);
        while (frontier.length > 0) {
          for (const id of frontier) {
            const revision = await recordSyncWrite(trx, {
              workspaceId: row.workspace_id,
              entityType: 'task',
              entityId: id,
              operation: 'delete',
            });
            await trx('tasks').where({ id }).update({
              deleted_at: new Date(),
              revision,
              updated_by: request.user.id,
              updated_at: new Date(),
            });
            const fresh = await trx('tasks').where({ id }).first();
            await reconcileTaskReminder(trx, { workspaceId: row.workspace_id, task: fresh });
          }
          const children = await trx('tasks')
            .whereIn('parent_task_id', frontier)
            .whereNull('deleted_at')
            .select('id');
          frontier = children.map((c) => c.id).filter((id) => !seen.has(id));
          for (const id of frontier) seen.add(id);
        }
      });

      return reply.code(204).send();
    },
  );

  // ── Tags (replace-set semantics) ──────────────────────────────────────────

  app.put(
    '/tasks/:taskId/tags',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['tagIds'],
          properties: { tagIds: { type: 'array', maxItems: 50, items: ULID_PARAM } },
        },
        response: {
          200: taskDetailSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      assertNotArchived(row);

      const desired = [...new Set(request.body.tagIds)];
      await assertTagsUsable(desired, row.workspace_id);

      const current = (await app.db('task_tags').where({ task_id: row.id }).select('tag_id')).map(
        (r) => r.tag_id,
      );
      const toAdd = desired.filter((id) => !current.includes(id));
      const toRemove = current.filter((id) => !desired.includes(id));

      if (toAdd.length > 0 || toRemove.length > 0) {
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
            await trx('task_tags').insert(
              toAdd.map((tagId) => ({ task_id: row.id, tag_id: tagId })),
            );
          }
          await trx('tasks').where({ id: row.id }).update({
            revision,
            updated_by: request.user.id,
            updated_at: new Date(),
          });
        });
      }

      return taskDetail(row.id);
    },
  );

  // ── Checklist sub-resource ────────────────────────────────────────────────

  async function loadChecklistItem(taskId, itemId) {
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

  app.post(
    '/tasks/:taskId/checklist',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['title'],
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 500 },
            sortOrder: { type: 'integer', minimum: -1000000, maximum: 1000000 },
          },
        },
        response: { 201: checklistItemSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const task = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, task.workspace_id);
      assertNotArchived(task);

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
          title: request.body.title,
          ...(request.body.sortOrder !== undefined ? { sort_order: request.body.sortOrder } : {}),
          revision,
        });
      });

      return reply.code(201).send(serializeChecklistItem(await loadChecklistItem(task.id, id)));
    },
  );

  app.patch(
    '/tasks/:taskId/checklist/:itemId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM, itemId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 500 },
            isDone: { type: 'boolean' },
            sortOrder: { type: 'integer', minimum: -1000000, maximum: 1000000 },
          },
        },
        response: { 200: checklistItemSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const task = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, task.workspace_id);
      assertNotArchived(task);
      const item = await loadChecklistItem(task.id, request.params.itemId);

      const patch = {};
      if ('title' in request.body) patch.title = request.body.title;
      if ('isDone' in request.body) patch.is_done = request.body.isDone;
      if ('sortOrder' in request.body) patch.sort_order = request.body.sortOrder;

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
      });

      return serializeChecklistItem(await loadChecklistItem(task.id, item.id));
    },
  );

  app.delete(
    '/tasks/:taskId/checklist/:itemId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM, itemId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const task = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, task.workspace_id);
      assertNotArchived(task);
      const item = await loadChecklistItem(task.id, request.params.itemId);

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: task.workspace_id,
          entityType: 'checklist_item',
          entityId: item.id,
          operation: 'delete',
        });
        await trx('checklist_items')
          .where({ id: item.id })
          .update({ deleted_at: new Date(), revision, updated_at: new Date() });
      });

      return reply.code(204).send();
    },
  );
}
