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

export const FILE_TARGET_TYPES = ['project', 'task', 'note'];
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

      // The target must be a live entity of THIS workspace — attachments never
      // dangle. (No FK on target_id: it is polymorphic — this check is the FK.)
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
