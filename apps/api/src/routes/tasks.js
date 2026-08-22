import { toIso } from '../lib/serialize.js';
import { recordSyncWrite } from '../db/sync.js';
import { reconcileTaskReminder } from '../db/reminders.js';
import { cascadeDeleteFiles } from '../db/files.js';
import { cascadeDeleteQuickLinks } from '../db/quick-links.js';
import { SERIES_SCOPES, occurrenceDayOf } from '../db/task-series.js';
// OPH-218 (extended by OPH-262): create/update/transition/snooze/tags/
// checklist and the detail loader live in the domain layer so the MCP tools
// and REST are one implementation (ADR-0022 §4).
import * as taskDb from '../db/tasks.js';
import { SNOOZE_PRESETS, TASK_STATUSES, TASK_PRIORITIES } from '../db/tasks.js';
import { COLOR_PATTERN } from './projects.js';

// The vocabulary moved to the domain layer in OPH-262; routes/sync.js and the
// suites keep importing it from here.
export { SNOOZE_PRESETS, TASK_STATUSES, TASK_PRIORITIES };

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
    alarmsMutedAt: { type: ['string', 'null'] },
    timezone: { type: 'string' },
    isUrgent: { type: 'boolean' },
    requiresAcknowledgement: { type: 'boolean' },
    repeatRule: { type: ['string', 'null'] },
    seriesId: { type: ['string', 'null'] },
    occurrenceDate: { type: ['string', 'null'] },
    estimatedMinutes: { type: ['integer', 'null'] },
    actualMinutes: { type: ['integer', 'null'] },
    sortOrder: { type: 'integer' },
    calendarMirrorEnabled: { type: 'boolean' },
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
  // `repeatRule` is gone from the write path as of OPH-205 (ADR-0020 §7):
  // recurrence lives in `task_series`, and this column was a live wire with no
  // human end — REST wrote it, sync wrote it, db/reminders.js copied it onto
  // reminder rows, and no surface ever produced a value. The column stays
  // (migrations are append-only) and still serializes as null.
  estimatedMinutes: { type: ['integer', 'null'], minimum: 0, maximum: 60000 },
  actualMinutes: { type: ['integer', 'null'], minimum: 0, maximum: 60000 },
  sortOrder: { type: 'integer', minimum: -1000000, maximum: 1000000 },
  // Epic 08: opt this task into calendar mirroring (BLUEPRINT §7.1).
  calendarMirrorEnabled: { type: 'boolean' },
  // Round 9 (OPH-178): silence this task's alarms indefinitely without
  // completing it. A timestamp mutes, null gives them back.
  alarmsMutedAt: { type: ['string', 'null'], format: 'date-time' },
};

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
    alarmsMutedAt: toIso(row.alarms_muted_at),
    timezone: row.timezone,
    isUrgent: Boolean(row.is_urgent),
    requiresAcknowledgement: Boolean(row.requires_acknowledgement),
    repeatRule: row.repeat_rule ?? null,
    // OPH-205: which series produced this task, and which day of it this is.
    // Server-owned — clients read them, they never push them.
    seriesId: row.series_id ?? null,
    occurrenceDate: occurrenceDayOf(row.occurrence_date),
    estimatedMinutes: row.estimated_minutes ?? null,
    actualMinutes: row.actual_minutes ?? null,
    sortOrder: row.sort_order,
    calendarMirrorEnabled: Boolean(row.calendar_mirror_enabled),
    completedAt: toIso(row.completed_at),
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

export function serializeChecklistItem(row) {
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

  // Thin delegates: the implementations moved to db/tasks.js (OPH-218) so the
  // MCP tools share them; the local names keep every call site unchanged.
  const loadTask = (id) => taskDb.loadTask(app, id);
  const assertNotArchived = (row) => taskDb.assertNotArchived(app, row);

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
      const id = await taskDb.createTask(app, {
        workspaceId,
        userId: request.user.id,
        body: request.body,
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
            // OPH-167: free-text search over title+description — the notes
            // `q` twin, riding the ft_tasks_title_description index that has
            // waited unused since the first migration. Secondary to the
            // app's local fold search (ADR-0013: the ai_ci collation folds
            // ç/ü/ö/İ but NOT ı — documented gap on this path).
            q: { type: 'string', minLength: 1, maxLength: 200 },
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
      if (q.q) {
        query = query.whereRaw('MATCH(title, description) AGAINST (? IN NATURAL LANGUAGE MODE)', [
          q.q,
        ]);
      }
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
    const { row, tagIds, checklist } = await taskDb.taskDetailRows(app, id);
    return {
      ...serializeTask(row),
      tagIds,
      checklist: checklist.map(serializeChecklistItem),
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
          properties: {
            ...writableProps,
            // OPH-206: how far this edit reaches when the task is one
            // occurrence of a series. Absent means `this` — a plain task edit.
            seriesScope: { type: 'string', enum: SERIES_SCOPES },
          },
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
      await taskDb.updateTask(app, { row, userId: request.user.id, body: request.body });
      return taskDetail(row.id);
    },
  );

  // ── Status transitions (OPH-033) ──────────────────────────────────────────

  const applyTransition = (request, row, toStatus) =>
    taskDb.applyStatusTransition(app, { userId: request.user.id, row, toStatus });

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
    await taskDb.reopenTask(app, { userId: request.user.id, row });
    return taskDetail(row.id);
  });

  // ── Snooze (OPH-035) ──────────────────────────────────────────────────────

  app.post(
    '/tasks/:taskId/snooze',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          properties: {
            preset: { type: 'string', enum: SNOOZE_PRESETS },
            snoozeUntil: { type: 'string', format: 'date-time' },
            // OPH-175: which alarm is being snoozed. A ringing alarm knows its
            // own id, so it silences only itself; omitted (the app's older
            // call, and every task-level "not now") snoozes ALL of the task's
            // active alarms.
            reminderId: ULID_PARAM,
          },
          // Exactly one of the two: with both present, both branches match and
          // oneOf fails; with neither, neither matches.
          oneOf: [{ required: ['preset'] }, { required: ['snoozeUntil'] }],
        },
        response: {
          200: taskDetailSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadTask(request.params.taskId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      await taskDb.snoozeTask(app, {
        row,
        userId: request.user.id,
        preset: request.body.preset,
        snoozeUntil: request.body.snoozeUntil,
        reminderId: request.body.reminderId,
      });
      return taskDetail(row.id);
    },
  );

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
        // Every task in the subtree takes its attachments with it (Epic 14)
        // and every member's shortcut to it (OPH-197) — subtasks included.
        await cascadeDeleteFiles(trx, app, {
          workspaceId: row.workspace_id,
          targets: [...seen].map((id) => ({ type: 'task', id })),
        });
        await cascadeDeleteQuickLinks(trx, {
          workspaceId: row.workspace_id,
          targets: [...seen].map((id) => ({ type: 'task', id })),
        });
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

      await taskDb.setTaskTags(app, {
        row,
        userId: request.user.id,
        tagIds: request.body.tagIds,
      });

      return taskDetail(row.id);
    },
  );

  // ── Checklist sub-resource ────────────────────────────────────────────────

  const loadChecklistItem = (taskId, itemId) => taskDb.loadChecklistItem(app, taskId, itemId);

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

      const id = await taskDb.addChecklistItem(app, {
        task,
        title: request.body.title,
        sortOrder: request.body.sortOrder,
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

      await taskDb.updateChecklistItem(app, {
        task,
        item,
        body: request.body,
        userId: request.user.id,
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
