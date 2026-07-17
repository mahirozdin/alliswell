import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { recordSyncWrite } from '../db/sync.js';
import { reconcileTaskReminder } from '../db/reminders.js';

export const PROJECT_STATUSES = ['active', 'paused', 'completed', 'archived'];
// Non-terminal task statuses the archive cascade sweeps (OPH-110); terminal
// ones (completed/cancelled/already-archived) are left untouched.
const CASCADE_TASK_STATUSES = ['inbox', 'open', 'scheduled', 'in_progress', 'waiting'];
export const COLOR_PATTERN = '^#[0-9A-Fa-f]{6}$';
const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const projectSchema = {
  type: 'object',
  required: [
    'id',
    'workspaceId',
    'name',
    'colorRgb',
    'status',
    'sortOrder',
    'isFavorite',
    'revision',
  ],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    name: { type: 'string' },
    description: { type: ['string', 'null'] },
    colorRgb: { type: 'string' },
    icon: { type: ['string', 'null'] },
    status: { type: 'string', enum: PROJECT_STATUSES },
    startAt: { type: ['string', 'null'] },
    dueAt: { type: ['string', 'null'] },
    sortOrder: { type: 'integer' },
    isFavorite: { type: 'boolean' },
    readmeNoteId: { type: ['string', 'null'] },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

// Writable fields, shared by create (with requireds) and patch (all optional).
const writableProps = {
  name: { type: 'string', minLength: 1, maxLength: 255 },
  description: { type: ['string', 'null'], maxLength: 65535 },
  colorRgb: { type: 'string', pattern: COLOR_PATTERN },
  icon: { type: ['string', 'null'], maxLength: 64 },
  status: { type: 'string', enum: PROJECT_STATUSES },
  startAt: { type: ['string', 'null'], format: 'date-time' },
  dueAt: { type: ['string', 'null'], format: 'date-time' },
  sortOrder: { type: 'integer', minimum: -1000000, maximum: 1000000 },
  isFavorite: { type: 'boolean' },
  // The project's README note (feedback round 1) — must live in the same workspace.
  readmeNoteId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
};

/** camelCase body → snake_case row values (only for keys present). */
function toRowPatch(body) {
  const map = {
    name: 'name',
    description: 'description',
    colorRgb: 'color_rgb',
    icon: 'icon',
    status: 'status',
    startAt: 'start_at',
    dueAt: 'due_at',
    sortOrder: 'sort_order',
    isFavorite: 'is_favorite',
    readmeNoteId: 'readme_note_id',
  };
  const row = {};
  for (const [camel, snake] of Object.entries(map)) {
    if (camel in body) {
      const value = body[camel];
      row[snake] = camel.endsWith('At') && value != null ? new Date(value) : value;
    }
  }
  return row;
}

export function serializeProject(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    name: row.name,
    description: row.description ?? null,
    colorRgb: row.color_rgb,
    icon: row.icon ?? null,
    status: row.status,
    startAt: toIso(row.start_at),
    dueAt: toIso(row.due_at),
    sortOrder: row.sort_order,
    isFavorite: Boolean(row.is_favorite),
    readmeNoteId: row.readme_note_id ?? null,
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

export default async function projectRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  async function loadProject(id) {
    const row = await app.db('projects').where({ id }).whereNull('deleted_at').first();
    if (!row) throw coded(app.httpErrors.notFound('Project not found'), 'PROJECT_NOT_FOUND');
    return row;
  }

  async function assertReadmeNoteUsable(noteId, workspaceId) {
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

  // ── Workspace-scoped collection ────────────────────────────────────────────

  app.get(
    '/workspaces/:workspaceId/projects',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: { status: { type: 'string', enum: PROJECT_STATUSES } },
        },
        response: {
          200: { type: 'object', properties: { items: { type: 'array', items: projectSchema } } },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      let query = app
        .db('projects')
        .where({ workspace_id: workspaceId })
        .whereNull('deleted_at')
        .orderBy('sort_order', 'asc')
        .orderBy('created_at', 'asc');
      if (request.query.status) query = query.where({ status: request.query.status });

      return { items: (await query.select()).map(serializeProject) };
    },
  );

  app.post(
    '/workspaces/:workspaceId/projects',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['name'],
          properties: writableProps,
        },
        response: { 201: projectSchema, 403: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      if (request.body.readmeNoteId) {
        await assertReadmeNoteUsable(request.body.readmeNoteId, workspaceId);
      }

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
          ...toRowPatch(request.body),
          created_by: request.user.id,
          updated_by: request.user.id,
          revision,
        });
      });

      return reply.code(201).send(serializeProject(await loadProject(id)));
    },
  );

  // ── Single-project routes ──────────────────────────────────────────────────

  app.get(
    '/projects/:projectId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { projectId: ULID_PARAM } },
        response: { 200: projectSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadProject(request.params.projectId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      return serializeProject(row);
    },
  );

  app.patch(
    '/projects/:projectId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { projectId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: writableProps,
        },
        response: { 200: projectSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadProject(request.params.projectId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      if (request.body.readmeNoteId) {
        await assertReadmeNoteUsable(request.body.readmeNoteId, row.workspace_id);
      }

      const patch = toRowPatch(request.body);
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
          .update({
            ...patch,
            revision,
            updated_by: request.user.id,
            updated_at: new Date(),
          });
      });

      return serializeProject(await loadProject(row.id));
    },
  );

  // ── Archive / unarchive with an optional cascade (OPH-110) ─────────────────
  //
  // Reversible, so member-allowed (parity with PATCH, not delete). Everything
  // happens in ONE transaction, every row revisioned so replicas converge.
  // The task cascade routes each write through reconcileTaskReminder so a
  // reminder deactivates on archive and re-arms on unarchive.
  async function transitionProject(request, { toStatus, taskFrom, taskTo, noteArchived }) {
    const row = await loadProject(request.params.projectId);
    await app.requireWorkspaceMember(request, row.workspace_id);
    const includeTasks = request.body?.includeTasks ?? false;
    const includeNotes = request.body?.includeNotes ?? false;
    let tasksChanged = 0;
    let notesChanged = 0;

    await app.db.transaction(async (trx) => {
      if (row.status !== toStatus) {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'project',
          entityId: row.id,
          operation: 'update',
          changedFields: ['status'],
        });
        await trx('projects').where({ id: row.id }).update({
          status: toStatus,
          revision,
          updated_by: request.user.id,
          updated_at: new Date(),
        });
      }

      if (includeTasks) {
        const tasks = await trx('tasks')
          .where({ project_id: row.id, workspace_id: row.workspace_id })
          .whereNull('deleted_at')
          .whereIn('status', taskFrom)
          .select();
        for (const task of tasks) {
          const revision = await recordSyncWrite(trx, {
            workspaceId: row.workspace_id,
            entityType: 'task',
            entityId: task.id,
            operation: 'update',
            changedFields: ['status'],
          });
          await trx('tasks').where({ id: task.id }).update({
            status: taskTo,
            revision,
            updated_by: request.user.id,
            updated_at: new Date(),
          });
          // Same status side-effect path PATCH uses → reminders (de)activate.
          await reconcileTaskReminder(trx, {
            workspaceId: row.workspace_id,
            task: { ...task, status: taskTo },
          });
        }
        tasksChanged = tasks.length;
      }

      if (includeNotes) {
        const notes = await trx('notes')
          .where({
            project_id: row.id,
            workspace_id: row.workspace_id,
            is_archived: !noteArchived,
          })
          .whereNull('deleted_at')
          .select('id');
        for (const note of notes) {
          const revision = await recordSyncWrite(trx, {
            workspaceId: row.workspace_id,
            entityType: 'note',
            entityId: note.id,
            operation: 'update',
            changedFields: ['is_archived'],
          });
          await trx('notes').where({ id: note.id }).update({
            is_archived: noteArchived,
            revision,
            updated_by: request.user.id,
            updated_at: new Date(),
          });
        }
        notesChanged = notes.length;
      }
    });

    return {
      project: serializeProject(await loadProject(row.id)),
      tasksChanged,
      notesChanged,
    };
  }

  const cascadeBody = {
    type: 'object',
    additionalProperties: false,
    properties: {
      includeTasks: { type: 'boolean', default: false },
      includeNotes: { type: 'boolean', default: false },
    },
  };
  const transitionResponse = {
    200: {
      type: 'object',
      properties: {
        project: projectSchema,
        tasksChanged: { type: 'integer' },
        notesChanged: { type: 'integer' },
      },
    },
    403: errorResponseSchema,
    404: errorResponseSchema,
  };

  app.post(
    '/projects/:projectId/archive',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { projectId: ULID_PARAM } },
        body: cascadeBody,
        response: transitionResponse,
      },
    },
    (request) =>
      transitionProject(request, {
        toStatus: 'archived',
        taskFrom: CASCADE_TASK_STATUSES,
        taskTo: 'archived',
        noteArchived: true,
      }),
  );

  app.post(
    '/projects/:projectId/unarchive',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { projectId: ULID_PARAM } },
        body: cascadeBody,
        response: transitionResponse,
      },
    },
    // Documented simplification: unarchive-with-cascade restores ALL archived
    // tasks/notes of the project, including any archived individually before.
    (request) =>
      transitionProject(request, {
        toStatus: 'active',
        taskFrom: ['archived'],
        taskTo: 'open',
        noteArchived: false,
      }),
  );

  app.delete(
    '/projects/:projectId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { projectId: ULID_PARAM } },
        response: {
          204: { type: 'null' },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const row = await loadProject(request.params.projectId);
      // Destructive: members can create/edit, deleting needs owner/admin.
      await app.requireWorkspaceMember(request, row.workspace_id, { roles: ['owner', 'admin'] });

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'project',
          entityId: row.id,
          operation: 'delete',
        });
        await trx('projects').where({ id: row.id }).update({
          deleted_at: new Date(),
          revision,
          updated_by: request.user.id,
          updated_at: new Date(),
        });
      });

      return reply.code(204).send();
    },
  );
}
