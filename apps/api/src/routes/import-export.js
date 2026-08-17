import { toIso } from '../lib/serialize.js';
import { parseDelta, createNote, setNoteTags, loadNote } from '../db/notes.js';
import { createTask, TASK_PRIORITIES } from '../db/tasks.js';

/**
 * Bulk import / export (OPH-266, issue #3's acceptance test).
 *
 * This is the surface a script uses to get its data IN and OUT — the reason
 * API keys exist at all (ADR-0032). Three rules shape it:
 *
 * 1. **Writes go through the domain layer**, one entity at a time
 *    (`db/notes.js`, `db/tasks.js`). So an imported note is indistinguishable
 *    from a typed one: same asserts, same sync revision, same reminder
 *    reconcile — and every device converges on its own, with no import-aware
 *    code anywhere in the clients.
 * 2. **Partial success is reported, not hidden.** A 500-item import where item
 *    #37 names a dead project creates 499 rows and says exactly which one
 *    failed and why. The alternative — one giant transaction — turns a typo
 *    into "nothing imported" and gives the caller nothing to fix.
 * 3. **The export shape is an external contract**, so it is written out here
 *    rather than reusing an internal serializer whose fields move when the
 *    app's needs move.
 *
 * Deliberately NOT here: a zip archive (v1 is JSON; a single note already
 * exports as markdown at `/notes/:id/export`), and any MCP tool — bulk import
 * is a script-shaped operation on the key surface, and the assistant already
 * has `create_note` / `create_task` for one thing at a time (AGENTS rule 12,
 * written reason).
 */

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const MAX_EXPORT_PAGE = 200;
const MAX_IMPORT_ITEMS = 500;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const importResultSchema = {
  type: 'object',
  required: ['created', 'errors'],
  properties: {
    created: { type: 'array', items: { type: 'string' } },
    errors: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'integer' },
          code: { type: 'string' },
          message: { type: 'string' },
        },
      },
    },
  },
};

/** The export contract for one note (see rule 3 above). */
function exportNote(row, links, tagIds) {
  return {
    id: row.id,
    title: row.title,
    contentFormat: row.content_format ?? 'delta',
    contentMarkdown: row.content_markdown ?? null,
    contentDelta: parseDelta(row.content_delta),
    plainText: row.plain_text ?? null,
    projectId: row.project_id ?? null,
    tagIds,
    links: links.map((l) => ({
      entityType: l.linked_entity_type,
      entityId: l.linked_entity_id,
    })),
    isPinned: Boolean(row.is_pinned),
    isArchived: Boolean(row.is_archived),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * Runs `work` per item and collects failures instead of aborting.
 * Domain refusals carry a stable `code`; anything else is UNKNOWN and logged,
 * because a caller can act on a code and can do nothing with a stack trace.
 */
async function importEach(request, items, work) {
  const created = [];
  const errors = [];
  for (const [index, item] of items.entries()) {
    try {
      created.push(await work(item, index));
    } catch (err) {
      if (err?.statusCode >= 400 && err.statusCode < 500 && err.code) {
        errors.push({ index, code: err.code, message: err.message });
      } else {
        request.log.error({ err: err?.message, index }, 'import item failed');
        errors.push({ index, code: 'IMPORT_ITEM_FAILED', message: 'Could not import this item' });
      }
    }
  }
  return { created, errors };
}

export default async function importExportRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  // ── Export ────────────────────────────────────────────────────────────────

  app.get(
    '/workspaces/:workspaceId/export/notes',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: MAX_EXPORT_PAGE, default: 100 },
            cursor: ULID_PARAM,
            // Archived notes are part of "all my notes" — an export that
            // quietly dropped them would be the wrong kind of tidy.
            includeArchived: { type: 'boolean', default: true },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              notes: { type: 'array', items: { type: 'object', additionalProperties: true } },
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
      if (!q.includeArchived) query = query.where({ is_archived: false });
      const rows = await query.select();

      // Two batched reads for the whole page — never one per note.
      const ids = rows.map((r) => r.id);
      const [linkRows, tagRows] = await Promise.all([
        ids.length ? app.db('note_links').whereIn('note_id', ids).select() : [],
        ids.length ? app.db('note_tags').whereIn('note_id', ids).select() : [],
      ]);
      const linksByNote = new Map();
      for (const link of linkRows) {
        linksByNote.set(link.note_id, [...(linksByNote.get(link.note_id) ?? []), link]);
      }
      const tagsByNote = new Map();
      for (const tag of tagRows) {
        tagsByNote.set(tag.note_id, [...(tagsByNote.get(tag.note_id) ?? []), tag.tag_id]);
      }

      return {
        notes: rows.map((row) =>
          exportNote(row, linksByNote.get(row.id) ?? [], (tagsByNote.get(row.id) ?? []).sort()),
        ),
        nextCursor: rows.length === q.limit ? rows.at(-1).id : null,
      };
    },
  );

  // ── Import ────────────────────────────────────────────────────────────────

  app.post(
    '/workspaces/:workspaceId/import/notes',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['notes'],
          properties: {
            notes: {
              type: 'array',
              minItems: 1,
              maxItems: MAX_IMPORT_ITEMS,
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['title'],
                properties: {
                  title: { type: 'string', minLength: 1, maxLength: 500 },
                  contentMarkdown: { type: 'string', maxLength: 1000000 },
                  projectId: ULID_PARAM,
                  tagIds: { type: 'array', maxItems: 50, items: ULID_PARAM },
                  isPinned: { type: 'boolean' },
                  isArchived: { type: 'boolean' },
                },
              },
            },
          },
        },
        response: { 200: importResultSchema, 400: errorResponseSchema, 403: errorResponseSchema },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      return importEach(request, request.body.notes, async (item) => {
        const id = await createNote(app, {
          workspaceId,
          userId: request.user.id,
          // OPH-267: the version row says where this came from — and the
          // ordering note in OPH-266 said this line would land here.
          origin: 'import',
          body: {
            title: item.title,
            // Imported notes are markdown documents (ADR-0028): the caller
            // sent markdown, so markdown is what is canonical — and that is
            // what makes them findable, exportable and editable as written.
            contentFormat: 'markdown',
            contentMarkdown: item.contentMarkdown ?? '',
            ...(item.projectId ? { projectId: item.projectId } : {}),
            ...(item.isPinned !== undefined ? { isPinned: item.isPinned } : {}),
            ...(item.isArchived !== undefined ? { isArchived: item.isArchived } : {}),
          },
        });
        if (item.tagIds?.length) {
          // Its own write, and its own failure: a note that arrived without
          // its tags is still an imported note, and the error says so.
          await setNoteTags(app, {
            row: await loadNote(app, id),
            userId: request.user.id,
            tagIds: item.tagIds,
          });
        }
        return id;
      });
    },
  );

  app.post(
    '/workspaces/:workspaceId/import/tasks',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['tasks'],
          properties: {
            tasks: {
              type: 'array',
              minItems: 1,
              maxItems: MAX_IMPORT_ITEMS,
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['title'],
                properties: {
                  title: { type: 'string', minLength: 1, maxLength: 500 },
                  description: { type: 'string', maxLength: 65535 },
                  dueAt: { type: 'string', format: 'date-time' },
                  remindAt: { type: 'string', format: 'date-time' },
                  priority: { type: 'string', enum: TASK_PRIORITIES },
                  projectId: ULID_PARAM,
                  isUrgent: { type: 'boolean' },
                  tagIds: { type: 'array', maxItems: 50, items: ULID_PARAM },
                },
              },
            },
          },
        },
        response: { 200: importResultSchema, 400: errorResponseSchema, 403: errorResponseSchema },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      return importEach(request, request.body.tasks, async (item) => {
        // The same createTask REST and MCP call: asserts, urgent →
        // acknowledgement default, tag links and the reminder reconcile, all
        // in one transaction. An imported urgent task with a due time gets a
        // real alarm, because nothing here is a special case.
        const { tagIds = [], ...fields } = item;
        return createTask(app, {
          workspaceId,
          userId: request.user.id,
          body: { ...fields, tagIds },
        });
      });
    },
  );
}
