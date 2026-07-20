import { newId } from '../lib/ids.js';
import { foldSearchText } from '../lib/fold.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { recordSyncWrite } from '../db/sync.js';
import {
  FOLDER_MAX_DEPTH,
  deleteFolderSubtree,
  depthUnder,
  liveFolder,
  wouldCycle,
} from '../db/folders.js';

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

const folderSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'name', 'revision'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    parentId: { type: ['string', 'null'] },
    name: { type: 'string' },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

export function serializeFolder(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    parentId: row.parent_id ?? null,
    name: row.name,
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * Name uniqueness per level, case/accent-insensitively (the ai_ci collation's
 * comparison — Finder semantics). The unique index cannot cover the root
 * level (NULL parent), so EVERY level is guarded here; the index remains the
 * race backstop for non-root levels.
 */
async function nameTaken(db, workspaceId, parentId, name, { exceptId } = {}) {
  let query = db('folders').where({ workspace_id: workspaceId }).whereNull('deleted_at');
  query = parentId == null ? query.whereNull('parent_id') : query.where({ parent_id: parentId });
  const rows = await query.select('id', 'name');
  const folded = foldSearchText(name);
  return rows.some((row) => row.id !== exceptId && foldSearchText(row.name) === folded);
}

/** Folders (OPH-169, ADR-0014) — the Dosyalar section's Klasörlerim tree. */
export default async function folderRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  async function loadFolder(request, folderId) {
    const row = await app.db('folders').where({ id: folderId }).whereNull('deleted_at').first();
    if (!row) {
      throw coded(app.httpErrors.notFound('Folder not found'), 'FOLDER_NOT_FOUND');
    }
    await app.requireWorkspaceMember(request, row.workspace_id);
    return row;
  }

  /** Validates a (possibly null) parent for create/move; returns nothing. */
  async function assertParentUsable(workspaceId, parentId) {
    if (parentId == null) return;
    const parent = await liveFolder(app.db, workspaceId, parentId);
    if (!parent) {
      throw coded(
        app.httpErrors.badRequest('Parent folder not found in this workspace'),
        'FOLDER_PARENT_NOT_FOUND',
      );
    }
  }

  async function assertDepth(workspaceId, parentId) {
    if ((await depthUnder(app.db, workspaceId, parentId)) > FOLDER_MAX_DEPTH) {
      throw coded(
        app.httpErrors.badRequest(`Folders can nest at most ${FOLDER_MAX_DEPTH} levels deep`),
        'FOLDER_TOO_DEEP',
      );
    }
  }

  async function assertNameFree(workspaceId, parentId, name, exceptId) {
    if (await nameTaken(app.db, workspaceId, parentId, name, { exceptId })) {
      throw coded(
        app.httpErrors.conflict('A folder with this name already exists here'),
        'FOLDER_NAME_TAKEN',
      );
    }
  }

  // ── List: the whole live tree, flat — clients assemble it ────────────────
  app.get(
    '/workspaces/:workspaceId/folders',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: { items: { type: 'array', items: folderSchema } },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const rows = await app
        .db('folders')
        .where({ workspace_id: workspaceId })
        .whereNull('deleted_at')
        .orderBy('name', 'asc');
      return { items: rows.map(serializeFolder) };
    },
  );

  // ── Create ────────────────────────────────────────────────────────────────
  app.post(
    '/workspaces/:workspaceId/folders',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['name'],
          properties: {
            name: { type: 'string', minLength: 1, maxLength: 255 },
            parentId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
          },
        },
        response: { 201: folderSchema, 400: errorResponseSchema, 409: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const name = request.body.name.trim();
      const parentId = request.body.parentId ?? null;
      if (!name) {
        throw coded(app.httpErrors.badRequest('Folder name is required'), 'FOLDER_NAME_REQUIRED');
      }
      await assertParentUsable(workspaceId, parentId);
      await assertDepth(workspaceId, parentId);
      await assertNameFree(workspaceId, parentId, name);

      const id = newId();
      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId,
          entityType: 'folder',
          entityId: id,
          operation: 'create',
        });
        await trx('folders').insert({
          id,
          workspace_id: workspaceId,
          parent_id: parentId,
          name,
          revision,
        });
      });
      const row = await app.db('folders').where({ id }).first();
      return reply.code(201).send(serializeFolder(row));
    },
  );

  // ── Rename / move ─────────────────────────────────────────────────────────
  app.patch(
    '/folders/:folderId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { folderId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: {
            name: { type: 'string', minLength: 1, maxLength: 255 },
            parentId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
          },
        },
        response: {
          200: folderSchema,
          400: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const folder = await loadFolder(request, request.params.folderId);
      const workspaceId = folder.workspace_id;
      const name = request.body.name?.trim() ?? folder.name;
      const moving = 'parentId' in request.body;
      const parentId = moving ? (request.body.parentId ?? null) : folder.parent_id;

      if (moving && parentId !== folder.parent_id) {
        if (
          parentId === folder.id ||
          (await wouldCycle(app.db, workspaceId, folder.id, parentId))
        ) {
          throw coded(
            app.httpErrors.badRequest('A folder cannot move into its own subtree'),
            'FOLDER_CYCLE',
          );
        }
        await assertParentUsable(workspaceId, parentId);
        await assertDepth(workspaceId, parentId);
      }
      if (name !== folder.name || parentId !== folder.parent_id) {
        await assertNameFree(workspaceId, parentId, name, folder.id);
      }

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId,
          entityType: 'folder',
          entityId: folder.id,
          operation: 'update',
        });
        await trx('folders')
          .where({ id: folder.id })
          .update({ name, parent_id: parentId, revision, updated_at: new Date() });
      });
      const fresh = await app.db('folders').where({ id: folder.id }).first();
      return serializeFolder(fresh);
    },
  );

  // ── Recursive delete (counted — the confirm names the blast radius) ──────
  app.delete(
    '/folders/:folderId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { folderId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              deletedFolders: { type: 'integer' },
              deletedFiles: { type: 'integer' },
            },
          },
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const folder = await loadFolder(request, request.params.folderId);
      let counts;
      await app.db.transaction(async (trx) => {
        counts = await deleteFolderSubtree(trx, app, {
          workspaceId: folder.workspace_id,
          folderId: folder.id,
        });
      });
      return { deletedFolders: counts.folders, deletedFiles: counts.files };
    },
  );
}
