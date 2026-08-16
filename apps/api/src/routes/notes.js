import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { slugify } from '../lib/slug.js';
import { recordSyncWrite } from '../db/sync.js';
import * as domain from '../db/notes.js';
import { parseDelta } from '../db/notes.js';
import { cascadeDeleteFiles } from '../db/files.js';
import { cascadeDeleteQuickLinks } from '../db/quick-links.js';

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const SNIPPET_LENGTH = 160;
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

// List rows carry a snippet instead of the full content.
const noteRowSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'title', 'isPinned', 'isArchived', 'revision'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    projectId: { type: ['string', 'null'] },
    createdFromTaskId: { type: ['string', 'null'] },
    title: { type: 'string' },
    snippet: { type: 'string' },
    isPinned: { type: 'boolean' },
    isArchived: { type: 'boolean' },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

const noteDetailSchema = {
  ...noteRowSchema,
  properties: {
    ...noteRowSchema.properties,
    contentDelta: { type: ['array', 'null'] },
    contentMarkdown: { type: ['string', 'null'] },
    contentFormat: { type: 'string', enum: ['delta', 'markdown'] },
    plainText: { type: ['string', 'null'] },
    tagIds: { type: 'array', items: { type: 'string' } },
    links: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          entityType: { type: 'string' },
          entityId: { type: 'string' },
        },
      },
    },
  },
};

const writableProps = {
  title: { type: 'string', minLength: 1, maxLength: 500 },
  contentDelta: { type: ['array', 'null'], maxItems: 20000 },
  contentMarkdown: { type: ['string', 'null'], maxLength: 1000000 },
  // Which field is canonical (ADR-0028 §1). The schema constrains it here AND
  // a CHECK constraint constrains it in the table: a value the app has never
  // heard of would silently decide how somebody's note is edited.
  contentFormat: { type: 'string', enum: ['delta', 'markdown'] },
  projectId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
  isPinned: { type: 'boolean' },
  isArchived: { type: 'boolean' },
};

export function serializeNoteRow(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    projectId: row.project_id ?? null,
    createdFromTaskId: row.created_from_task_id ?? null,
    title: row.title,
    snippet: (row.plain_text ?? '').slice(0, SNIPPET_LENGTH),
    isPinned: Boolean(row.is_pinned),
    isArchived: Boolean(row.is_archived),
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * Full note snapshot (row + preloaded note_links rows) — the shape note
 * detail responses and sync pull snapshots share.
 */
export function serializeNoteSnapshot(row, links, tagIds = []) {
  return {
    ...serializeNoteRow(row),
    // OPH-261: `note_tags` has existed since the first migration and had no
    // endpoint and no serialization — a column nobody could read or write,
    // which is §22 at the schema level.
    tagIds,
    contentDelta: parseDelta(row.content_delta),
    contentMarkdown: row.content_markdown ?? null,
    // Rows written before OPH-248 have no column value in flight; 'delta' is
    // both the table default and the right answer for anything the WYSIWYG
    // wrote, which is every note that existed before this.
    contentFormat: row.content_format ?? 'delta',
    plainText: row.plain_text ?? null,
    links: links.map((l) => ({
      id: l.id,
      entityType: l.linked_entity_type,
      entityId: l.linked_entity_id,
    })),
  };
}

export default async function noteRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  // OPH-261: the writes live in `db/notes.js` so MCP and REST are ONE
  // implementation (ADR-0022 §4). What stays here is HTTP: schemas, codes and
  // the serializers the sync pull also imports.
  const loadNote = (id) => domain.loadNote(app, id);

  async function serializeNoteDetail(row) {
    const { links, tagIds } = await domain.noteRelations(app, row.id);
    return serializeNoteSnapshot(row, links, tagIds);
  }

  // ── Collection ────────────────────────────────────────────────────────────

  app.get(
    '/workspaces/:workspaceId/notes',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            pinned: { type: 'boolean' },
            // archived=true lists ONLY archived notes (the archive view);
            // includeArchived=true mixes them into the normal list.
            archived: { type: 'boolean' },
            includeArchived: { type: 'boolean', default: false },
            // README notes (a project's readme_note_id) live in the project
            // Overview, not the notes list (OPH-109). Absent/false excludes
            // them; readme=true lists ONLY them.
            readme: { type: 'boolean' },
            projectId: ULID_PARAM,
            taskId: ULID_PARAM,
            q: { type: 'string', minLength: 1, maxLength: 200 },
            limit: { type: 'integer', minimum: 1, maximum: MAX_PAGE_SIZE, default: 50 },
            cursor: ULID_PARAM,
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              items: { type: 'array', items: noteRowSchema },
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

      let query = app
        .db('notes')
        .where({ workspace_id: workspaceId })
        .whereNull('deleted_at')
        .orderBy('id', 'desc')
        .limit(q.limit);
      if (q.cursor) query = query.where('id', '<', q.cursor);
      if (q.pinned !== undefined) query = query.where({ is_pinned: q.pinned });
      if (q.archived !== undefined) {
        query = query.where({ is_archived: q.archived });
      } else if (!q.includeArchived) {
        query = query.where({ is_archived: false });
      }
      // README filter (OPH-109): two cheap queries + whereIn/whereNotIn keeps
      // the unit fakedb viable and avoids subquery-support questions.
      const readmeRows = await app
        .db('projects')
        .where({ workspace_id: workspaceId })
        .whereNotNull('readme_note_id')
        .select('readme_note_id');
      const readmeIds = readmeRows.map((r) => r.readme_note_id);
      if (q.readme === true) {
        // Empty list → knex emits `1 = 0`, i.e. no rows (correct).
        query = query.whereIn('id', readmeIds);
      } else if (readmeIds.length) {
        query = query.whereNotIn('id', readmeIds);
      }
      if (q.projectId) query = query.where({ project_id: q.projectId });
      if (q.taskId) {
        // Linked to the task either explicitly or by "created from task".
        const links = await app
          .db('note_links')
          .where({ linked_entity_type: 'task', linked_entity_id: q.taskId })
          .select('note_id');
        const noteIds = new Set(links.map((l) => l.note_id));
        const created = await app
          .db('notes')
          .where({ created_from_task_id: q.taskId })
          .whereNull('deleted_at')
          .select('id');
        for (const row of created) noteIds.add(row.id);
        query = query.whereIn('id', [...noteIds]);
      }
      if (q.q) {
        query = query.whereRaw('MATCH(title, plain_text) AGAINST (? IN NATURAL LANGUAGE MODE)', [
          q.q,
        ]);
      }

      const rows = await query.select();
      return {
        items: rows.map(serializeNoteRow),
        nextCursor: rows.length === q.limit ? rows.at(-1).id : null,
      };
    },
  );

  app.post(
    '/workspaces/:workspaceId/notes',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['title'],
          properties: writableProps,
        },
        response: { 201: noteDetailSchema, 400: errorResponseSchema, 403: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const id = await domain.createNote(app, {
        workspaceId,
        userId: request.user.id,
        body: request.body,
      });
      return reply.code(201).send(await serializeNoteDetail(await loadNote(id)));
    },
  );

  // ── Single note ───────────────────────────────────────────────────────────

  app.get(
    '/notes/:noteId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        response: { 200: noteDetailSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      return serializeNoteDetail(row);
    },
  );

  // Markdown export (OPH-045). The delta is canonical (BLUEPRINT §9.1), so the
  // export is derived server-side from it — the client-supplied
  // content_markdown is only the fallback for delta-less notes.
  app.get(
    '/notes/:noteId/export',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: { format: { type: 'string', enum: ['md'], default: 'md' } },
        },
        // No 200 schema: the body is raw markdown, not JSON.
        response: { 400: errorResponseSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      const markdown = await domain.exportNoteMarkdown(app, row);
      return reply
        .header('content-type', 'text/markdown; charset=utf-8')
        .header('content-disposition', `attachment; filename="${slugify(row.title, 'note')}.md"`)
        .send(markdown);
    },
  );

  app.patch(
    '/notes/:noteId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: writableProps,
        },
        response: {
          200: noteDetailSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      await domain.updateNote(app, { row, userId: request.user.id, body: request.body });
      return serializeNoteDetail(await loadNote(row.id));
    },
  );

  app.delete(
    '/notes/:noteId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'note',
          entityId: row.id,
          operation: 'delete',
        });
        await trx('notes').where({ id: row.id }).update({
          deleted_at: new Date(),
          revision,
          updated_by: request.user.id,
          updated_at: new Date(),
        });
        // A deleted note takes its attachments (inline embeds included) with
        // it — Epic 14, ATTACHMENTS.md §5 — and its shortcuts (OPH-197).
        await cascadeDeleteFiles(trx, app, {
          workspaceId: row.workspace_id,
          targets: [{ type: 'note', id: row.id }],
        });
        await cascadeDeleteQuickLinks(trx, {
          workspaceId: row.workspace_id,
          targets: [{ type: 'note', id: row.id }],
        });
      });

      return reply.code(204).send();
    },
  );

  // ── Polymorphic links (OPH-041): v1 targets are tasks and projects ────────

  const LINKABLE = {
    task: { table: 'tasks', code: 'NOTE_INVALID_LINK_TARGET' },
    project: { table: 'projects', code: 'NOTE_INVALID_LINK_TARGET' },
  };

  async function assertLinkTarget(entityType, entityId, workspaceId) {
    const target = LINKABLE[entityType];
    const row = await app
      .db(target.table)
      .where({ id: entityId, workspace_id: workspaceId })
      .whereNull('deleted_at')
      .first('id');
    if (!row) {
      throw coded(
        app.httpErrors.badRequest(`${entityType} not found in this workspace`),
        target.code,
      );
    }
  }

  app.post(
    '/notes/:noteId/links',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['entityType', 'entityId'],
          properties: {
            entityType: { type: 'string', enum: Object.keys(LINKABLE) },
            entityId: ULID_PARAM,
          },
        },
        response: {
          201: noteDetailSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      const { entityType, entityId } = request.body;
      await assertLinkTarget(entityType, entityId, row.workspace_id);

      const existing = await app
        .db('note_links')
        .where({ note_id: row.id, linked_entity_type: entityType, linked_entity_id: entityId })
        .first('id');
      if (existing) {
        throw coded(app.httpErrors.conflict('This link already exists'), 'NOTE_LINK_EXISTS');
      }

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'note',
          entityId: row.id,
          operation: 'update',
          changedFields: ['links'],
        });
        await trx('note_links').insert({
          id: newId(),
          note_id: row.id,
          linked_entity_type: entityType,
          linked_entity_id: entityId,
        });
        await trx('notes')
          .where({ id: row.id })
          .update({ revision, updated_by: request.user.id, updated_at: new Date() });
      });

      return reply.code(201).send(await serializeNoteDetail(await loadNote(row.id)));
    },
  );

  // OPH-261: notes can be tagged. `note_tags` shipped with the very first
  // migration and never grew an endpoint, so the table sat there for a year
  // holding nothing — the schema-level twin of the reachability rule (§22).
  //
  // Replace-set, exactly like `PUT /tasks/:taskId/tags`: one call states what
  // the tags ARE, so a client never has to diff. Deliberately NOT part of the
  // note's sync fields — tags stay out of the note push protocol in v1, and
  // the pull snapshot reads them alongside links instead.
  app.put(
    '/notes/:noteId/tags',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['tagIds'],
          properties: { tagIds: { type: 'array', maxItems: 50, items: ULID_PARAM } },
        },
        response: {
          200: noteDetailSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      await domain.setNoteTags(app, {
        row,
        userId: request.user.id,
        tagIds: request.body.tagIds,
      });
      return serializeNoteDetail(await loadNote(row.id));
    },
  );

  app.delete(
    '/notes/:noteId/links/:linkId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM, linkId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadNote(request.params.noteId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      const link = await app
        .db('note_links')
        .where({ id: request.params.linkId, note_id: row.id })
        .first('id');
      if (!link) {
        throw coded(app.httpErrors.notFound('Link not found'), 'NOTE_LINK_NOT_FOUND');
      }

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'note',
          entityId: row.id,
          operation: 'update',
          changedFields: ['links'],
        });
        await trx('note_links').where({ id: link.id }).delete();
        await trx('notes')
          .where({ id: row.id })
          .update({ revision, updated_by: request.user.id, updated_at: new Date() });
      });

      return reply.code(204).send();
    },
  );

  // Project notes listing (OPH-042): both directly-attached (project_id) and
  // link-attached notes, newest first.
  app.get(
    '/projects/:projectId/notes',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { projectId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            includeArchived: { type: 'boolean', default: false },
            limit: { type: 'integer', minimum: 1, maximum: MAX_PAGE_SIZE, default: 50 },
            cursor: ULID_PARAM,
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              items: { type: 'array', items: noteRowSchema },
              nextCursor: { type: ['string', 'null'] },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const project = await app
        .db('projects')
        .where({ id: request.params.projectId })
        .whereNull('deleted_at')
        .first('id', 'workspace_id');
      if (!project) {
        throw coded(app.httpErrors.notFound('Project not found'), 'PROJECT_NOT_FOUND');
      }
      await app.requireWorkspaceMember(request, project.workspace_id);
      const q = request.query;

      const links = await app
        .db('note_links')
        .where({ linked_entity_type: 'project', linked_entity_id: project.id })
        .select('note_id');
      const linkedIds = links.map((l) => l.note_id);

      // Two id sets (attached ∪ linked) resolved in one paged query.
      const attached = await app
        .db('notes')
        .where({ project_id: project.id })
        .whereNull('deleted_at')
        .select('id');
      const ids = [...new Set([...linkedIds, ...attached.map((n) => n.id)])];

      let query = app
        .db('notes')
        .whereIn('id', ids)
        .whereNull('deleted_at')
        .orderBy('id', 'desc')
        .limit(q.limit);
      if (q.cursor) query = query.where('id', '<', q.cursor);
      if (!q.includeArchived) query = query.where({ is_archived: false });

      const rows = await query.select();
      return {
        items: rows.map(serializeNoteRow),
        nextCursor: rows.length === q.limit ? rows.at(-1).id : null,
      };
    },
  );

  // "Create note from task" (OPH-041): inherits the task's project and starts
  // linked to it — the capture path from a task detail screen.
  app.post(
    '/tasks/:taskId/notes',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { taskId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 500 },
            contentDelta: writableProps.contentDelta,
            contentMarkdown: writableProps.contentMarkdown,
          },
        },
        response: { 201: noteDetailSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const task = await app
        .db('tasks')
        .where({ id: request.params.taskId })
        .whereNull('deleted_at')
        .first();
      if (!task) throw coded(app.httpErrors.notFound('Task not found'), 'TASK_NOT_FOUND');
      await app.requireWorkspaceMember(request, task.workspace_id);

      const id = await domain.createNoteFromTask(app, {
        task,
        userId: request.user.id,
        body: request.body,
      });
      return reply.code(201).send(await serializeNoteDetail(await loadNote(id)));
    },
  );
}
