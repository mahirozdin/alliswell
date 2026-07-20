/**
 * File attachments — upload lifecycle (Epic 14, OPH-151; ATTACHMENTS.md §2).
 *
 * Bytes never pass through this API. Upload is a 3-step handshake:
 *
 *   1. `POST /workspaces/:id/files` — validate member + target + declared
 *      size, insert a `status='uploading'` row (INVISIBLE to sync — no
 *      revision), answer a presigned PUT URL.
 *   2. The client PUTs the bytes straight to the store.
 *   3. `POST /files/:id/complete` — HeadObject proves the object exists with
 *      exactly the declared byte count → `ready` + sync `create` revision.
 *      Missing object → retryable 409; size lies → object deleted, row gone,
 *      client restarts. Nothing unverified ever becomes visible.
 *
 * `DELETE /files/:id` aborts an upload (hard delete — it never synced) or
 * tombstones a ready file; the object itself is removed by the queued
 * `storage-delete` job (plugins/storage-gc.js) so a store hiccup retries.
 */
import { newId } from '../lib/ids.js';
import { toIso } from '../lib/serialize.js';
import { coded } from '../lib/errors.js';
import { recordSyncWrite } from '../db/sync.js';
import { storageKeyFor, softDeleteReadyFile } from '../db/files.js';

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

// Round 8 (OPH-169, ADR-0014): `workspace` = a standalone file (target_id is
// the workspace id itself) — the global Dosyalar section's Klasörlerim layer.
export const FILE_TARGET_TYPES = ['project', 'task', 'note', 'workspace'];
const TARGET_TABLES = { project: 'projects', task: 'tasks', note: 'notes' };

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

export const fileSchema = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    targetType: { type: 'string', enum: FILE_TARGET_TYPES },
    targetId: { type: 'string' },
    name: { type: 'string' },
    mime: { type: 'string' },
    sizeBytes: { type: 'integer' },
    status: { type: 'string', enum: ['uploading', 'ready'] },
    uploadedBy: { type: ['string', 'null'] },
    folderId: { type: ['string', 'null'] },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

export function serializeFile(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    targetType: row.target_type,
    targetId: row.target_id,
    name: row.name,
    mime: row.mime,
    sizeBytes: Number(row.size_bytes),
    status: row.status,
    uploadedBy: row.uploaded_by ?? null,
    folderId: row.folder_id ?? null,
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/u;

/**
 * Filenames are display data (ATTACHMENTS.md §9): keep the basename only
 * (drop any path a platform picker smuggled in), reject control characters
 * and empty/dot names. Returns the clean name or null.
 */
export function sanitizeFileName(raw) {
  if (typeof raw !== 'string') return null;
  const base = raw.split(/[/\\]/).pop().trim();
  if (!base || base === '.' || base === '..') return null;
  if (base.length > 255 || CONTROL_CHARS.test(base)) return null;
  return base;
}

export default async function fileRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  function requireStorage() {
    if (!app.storage.enabled) {
      throw coded(
        app.httpErrors.serviceUnavailable(
          'File storage is not configured on this server (STORAGE_S3_* env, docs/ATTACHMENTS.md)',
        ),
        'STORAGE_NOT_CONFIGURED',
      );
    }
  }

  async function loadFile(fileId, { includeDeleted = false } = {}) {
    let query = app.db('files').where({ id: fileId });
    if (!includeDeleted) query = query.whereNull('deleted_at');
    const row = await query.first();
    if (!row) throw coded(app.httpErrors.notFound('File not found'), 'FILE_NOT_FOUND');
    return row;
  }

  // ── Step 1: init — metadata row + presigned PUT ───────────────────────────

  app.post(
    '/workspaces/:workspaceId/files',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['targetType', 'targetId', 'name', 'sizeBytes'],
          properties: {
            targetType: { type: 'string', enum: FILE_TARGET_TYPES },
            targetId: ULID_PARAM,
            // Longer than 255 on purpose: pickers may hand over full paths;
            // we sanitize to the basename and enforce 255 on THAT.
            name: { type: 'string', minLength: 1, maxLength: 1024 },
            sizeBytes: { type: 'integer', minimum: 1 },
            mime: { type: 'string', minLength: 1, maxLength: 255 },
            // Only meaningful with targetType 'workspace' (ADR-0014).
            folderId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
          },
        },
        response: {
          201: {
            type: 'object',
            properties: {
              file: fileSchema,
              upload: {
                type: 'object',
                properties: {
                  method: { type: 'string' },
                  url: { type: 'string' },
                  headers: { type: 'object', additionalProperties: { type: 'string' } },
                  expiresAt: { type: 'string' },
                },
              },
            },
          },
          400: errorResponseSchema,
          403: errorResponseSchema,
          413: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      requireStorage();
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const { targetType, targetId, sizeBytes } = request.body;

      const name = sanitizeFileName(request.body.name);
      if (!name) {
        throw coded(app.httpErrors.badRequest('Invalid file name'), 'FILE_NAME_INVALID');
      }
      const mime = request.body.mime ?? 'application/octet-stream';
      if (CONTROL_CHARS.test(mime)) {
        throw coded(app.httpErrors.badRequest('Invalid mime type'), 'FILE_NAME_INVALID');
      }
      if (sizeBytes > app.storage.maxUploadBytes) {
        throw coded(
          app.httpErrors.payloadTooLarge(
            `File exceeds the ${app.storage.maxUploadBytes}-byte upload limit`,
          ),
          'FILE_TOO_LARGE',
        );
      }

      // Folders organize ONLY standalone files (ADR-0014) and must be live
      // folders of this workspace.
      const folderId = request.body.folderId ?? null;
      if (folderId != null) {
        if (targetType !== 'workspace') {
          throw coded(
            app.httpErrors.badRequest('Only workspace files can live in folders'),
            'FILE_FOLDER_NOT_ALLOWED',
          );
        }
        const folder = await app
          .db('folders')
          .where({ id: folderId, workspace_id: workspaceId })
          .whereNull('deleted_at')
          .first('id');
        if (!folder) {
          throw coded(
            app.httpErrors.badRequest('Folder not found in this workspace'),
            'FILE_FOLDER_NOT_FOUND',
          );
        }
      }

      // The target must be a live entity of THIS workspace — attachments never
      // dangle. (No FK on target_id: it is polymorphic — this check is the FK.)
      // A `workspace` target IS the workspace: membership was already
      // enforced, the id just has to match.
      if (targetType === 'workspace') {
        if (targetId !== workspaceId) {
          throw coded(
            app.httpErrors.badRequest('Attachment target not found'),
            'FILE_INVALID_TARGET',
          );
        }
      } else {
        const target = await app
          .db(TARGET_TABLES[targetType])
          .where({ id: targetId, workspace_id: workspaceId })
          .whereNull('deleted_at')
          .first('id');
        if (!target) {
          throw coded(
            app.httpErrors.badRequest('Attachment target not found'),
            'FILE_INVALID_TARGET',
          );
        }
      }

      const id = newId();
      const row = {
        id,
        workspace_id: workspaceId,
        target_type: targetType,
        target_id: targetId,
        uploaded_by: request.user.id,
        name,
        mime,
        size_bytes: sizeBytes,
        storage_key: storageKeyFor(workspaceId, id),
        status: 'uploading',
        folder_id: folderId,
        revision: 0,
      };
      // Deliberately NO recordSyncWrite: an uploading row is invisible to
      // other devices until the bytes are verified (ATTACHMENTS.md §2.1).
      await app.db('files').insert(row);

      const upload = await app.storage.presignPut(row.storage_key, { contentType: mime });
      const fresh = await app.db('files').where({ id }).first();
      return reply.code(201).send({
        file: serializeFile(fresh),
        upload: { method: 'PUT', ...upload },
      });
    },
  );

  // ── Step 3: complete — verify against the store, then publish ─────────────

  app.post(
    '/files/:fileId/complete',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { fileId: ULID_PARAM } },
        response: {
          200: { type: 'object', properties: { file: fileSchema } },
          403: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      requireStorage();
      const row = await loadFile(request.params.fileId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      // Idempotent: a client retrying after a network blip must not error.
      if (row.status === 'ready') return { file: serializeFile(row) };

      const head = await app.storage.head(row.storage_key);
      if (!head) {
        // Nothing uploaded (yet): the client may retry the PUT and complete
        // again — until the 24h sweep reaps the attempt.
        throw coded(
          app.httpErrors.conflict('No uploaded object found for this file'),
          'FILE_UPLOAD_INCOMPLETE',
        );
      }
      if (head.size !== Number(row.size_bytes) || head.size > app.storage.maxUploadBytes) {
        // The bytes lie about the declaration: remove the object, drop the
        // attempt entirely (it never synced), make the client start over.
        await app.storage.remove(row.storage_key);
        await app.db('files').where({ id: row.id, status: 'uploading' }).delete();
        throw coded(
          app.httpErrors.conflict(
            `Uploaded size ${head.size} does not match the declared ${row.size_bytes} bytes`,
          ),
          'FILE_UPLOAD_MISMATCH',
        );
      }

      let fresh;
      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'file',
          entityId: row.id,
          operation: 'create',
        });
        await trx('files')
          .where({ id: row.id })
          .update({ status: 'ready', revision, updated_at: new Date() });
        fresh = await trx('files').where({ id: row.id }).first();
      });
      return { file: serializeFile(fresh) };
    },
  );

  // ── Read surface (OPH-152) ────────────────────────────────────────────────

  app.get(
    '/files/:fileId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { fileId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              file: fileSchema,
              // Minted per request, never stored: null while uploading or
              // when storage is off (metadata still answers honestly).
              downloadUrl: { type: ['string', 'null'] },
              downloadExpiresAt: { type: ['string', 'null'] },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadFile(request.params.fileId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      let downloadUrl = null;
      let downloadExpiresAt = null;
      if (row.status === 'ready' && app.storage.enabled) {
        const signed = await app.storage.presignGet(row.storage_key, {
          filename: row.name,
          contentType: row.mime,
        });
        downloadUrl = signed.url;
        downloadExpiresAt = signed.expiresAt;
      }
      return { file: serializeFile(row), downloadUrl, downloadExpiresAt };
    },
  );

  const fileWithSourceSchema = {
    type: 'object',
    properties: {
      ...fileSchema.properties,
      source: {
        type: 'object',
        properties: {
          type: { type: 'string', enum: FILE_TARGET_TYPES },
          id: { type: 'string' },
          title: { type: 'string' },
        },
      },
    },
  };

  app.get(
    '/workspaces/:workspaceId/files',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            targetType: { type: 'string', enum: FILE_TARGET_TYPES },
            targetId: ULID_PARAM,
            projectId: ULID_PARAM,
            // With targetType=workspace only: filter one folder level; omit
            // for the ROOT level (folderless files) — ADR-0014.
            folderId: ULID_PARAM,
          },
        },
        response: {
          200: {
            type: 'object',
            properties: { files: { type: 'array', items: fileWithSourceSchema } },
          },
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const { targetType, targetId, projectId, folderId } = request.query;
      if (folderId && targetType !== 'workspace') {
        throw coded(
          app.httpErrors.badRequest('folderId only applies to workspace files'),
          'FILE_FOLDER_NOT_ALLOWED',
        );
      }

      // ── One entity's attachments ──
      if (!projectId) {
        if (!targetType || !targetId) {
          throw coded(
            app.httpErrors.badRequest('Pass targetType+targetId, or projectId'),
            'FILE_INVALID_TARGET',
          );
        }
        let query = app
          .db('files')
          .where({ workspace_id: workspaceId, target_type: targetType, target_id: targetId })
          .whereNull('deleted_at');
        // Workspace listing is per folder LEVEL: named folder, or the root
        // (folderless) when omitted — a tree browses one level at a time.
        if (targetType === 'workspace') {
          query = folderId ? query.where({ folder_id: folderId }) : query.whereNull('folder_id');
        }
        const rows = await query.orderBy('created_at', 'desc').select();
        return { files: rows.map(serializeFile) };
      }

      // ── The project "Files" tab aggregate (ATTACHMENTS.md §6): the
      //    project's own files ∪ its live tasks' ∪ its live notes' files,
      //    each row naming its source ──
      const project = await app
        .db('projects')
        .where({ id: projectId, workspace_id: workspaceId })
        .whereNull('deleted_at')
        .first('id', 'name');
      if (!project) {
        throw coded(app.httpErrors.notFound('Project not found'), 'PROJECT_NOT_FOUND');
      }
      const [tasks, notes] = await Promise.all([
        app
          .db('tasks')
          .where({ workspace_id: workspaceId, project_id: projectId })
          .whereNull('deleted_at')
          .select('id', 'title'),
        app
          .db('notes')
          .where({ workspace_id: workspaceId, project_id: projectId })
          .whereNull('deleted_at')
          .select('id', 'title'),
      ]);
      const sources = new Map([[`project:${project.id}`, project.name]]);
      for (const t of tasks) sources.set(`task:${t.id}`, t.title);
      for (const n of notes) sources.set(`note:${n.id}`, n.title);

      const rows = [];
      const collect = async (type, ids) => {
        if (ids.length === 0) return;
        rows.push(
          ...(await app
            .db('files')
            .where({ workspace_id: workspaceId, target_type: type })
            .whereIn('target_id', ids)
            .whereNull('deleted_at')
            .select()),
        );
      };
      await collect('project', [project.id]);
      await collect(
        'task',
        tasks.map((t) => t.id),
      );
      await collect(
        'note',
        notes.map((n) => n.id),
      );
      rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

      return {
        files: rows.map((row) => ({
          ...serializeFile(row),
          source: {
            type: row.target_type,
            id: row.target_id,
            title: sources.get(`${row.target_type}:${row.target_id}`) ?? '',
          },
        })),
      };
    },
  );

  app.get(
    '/workspaces/:workspaceId/files/usage',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              totalBytes: { type: 'integer' },
              fileCount: { type: 'integer' },
            },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      // Summed in JS on purpose: workspaces hold hundreds of files, not
      // millions, and the in-memory test db has no aggregate support.
      const rows = await app
        .db('files')
        .where({ workspace_id: workspaceId, status: 'ready' })
        .whereNull('deleted_at')
        .select('size_bytes');
      return {
        totalBytes: rows.reduce((sum, row) => sum + Number(row.size_bytes), 0),
        fileCount: rows.length,
      };
    },
  );

  // ── Rename (metadata only — the object never moves) ───────────────────────

  app.patch(
    '/files/:fileId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { fileId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['name'],
          properties: { name: { type: 'string', minLength: 1, maxLength: 1024 } },
        },
        response: {
          200: { type: 'object', properties: { file: fileSchema } },
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadFile(request.params.fileId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      if (row.status !== 'ready') {
        throw coded(
          app.httpErrors.conflict('Only completed files can be renamed'),
          'FILE_NOT_READY',
        );
      }
      const name = sanitizeFileName(request.body.name);
      if (!name) {
        throw coded(app.httpErrors.badRequest('Invalid file name'), 'FILE_NAME_INVALID');
      }

      let fresh;
      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'file',
          entityId: row.id,
          operation: 'update',
          changedFields: ['name'],
        });
        await trx('files').where({ id: row.id }).update({ name, revision, updated_at: new Date() });
        fresh = await trx('files').where({ id: row.id }).first();
      });
      return { file: serializeFile(fresh) };
    },
  );

  // ── Abort / delete ────────────────────────────────────────────────────────

  app.delete(
    '/files/:fileId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { fileId: ULID_PARAM } },
        response: {
          204: { type: 'null' },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const row = await loadFile(request.params.fileId, { includeDeleted: true });
      await app.requireWorkspaceMember(request, row.workspace_id);
      if (row.deleted_at != null) return reply.code(204).send(); // idempotent

      if (row.status === 'uploading') {
        // An aborted upload never synced — no tombstone owed, just cleanup.
        await app.db('files').where({ id: row.id }).delete();
        app.storageGc.enqueueRemove(row.storage_key);
        return reply.code(204).send();
      }

      await app.db.transaction(async (trx) => {
        await softDeleteReadyFile(trx, { workspaceId: row.workspace_id, fileId: row.id });
      });
      // After commit only — the queued job must never race a rollback.
      app.storageGc.enqueueRemove(row.storage_key);
      return reply.code(204).send();
    },
  );
}
