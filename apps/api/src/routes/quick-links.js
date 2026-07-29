import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { recordSyncWrite } from '../db/sync.js';
import { COLOR_PATTERN } from './projects.js';
import {
  QUICK_LINK_KINDS,
  QUICK_LINK_MAX_PER_USER,
  checkCreatable,
  listUserQuickLinks,
  nextSortOrder,
  softDeleteQuickLink,
  validateOrder,
  writeQuickLinkOrder,
} from '../db/quick-links.js';

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

const quickLinkSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'kind', 'title', 'sortOrder', 'revision'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    kind: { type: 'string' },
    targetId: { type: ['string', 'null'] },
    url: { type: ['string', 'null'] },
    title: { type: 'string' },
    emoji: { type: ['string', 'null'] },
    colorRgb: { type: ['string', 'null'] },
    sortOrder: { type: 'integer' },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

/**
 * The wire shape deliberately omits `user_id`: a caller only ever sees their
 * own rows (ADR-0018), so shipping the column would leak nothing useful and
 * would tempt a client into trusting it.
 */
export function serializeQuickLink(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    kind: row.kind,
    targetId: row.target_id ?? null,
    url: row.url ?? null,
    title: row.title,
    emoji: row.emoji ?? null,
    colorRgb: row.color_rgb ?? null,
    sortOrder: Number(row.sort_order ?? 0),
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * Quick links (OPH-197, ADR-0018) — the personal shortcut rail.
 *
 * Status codes read as a family: 400 = malformed field, 404 = not visible to
 * you, 409 = uniqueness clash, 422 = valid but refused by a business rule.
 * 422 is new to this codebase and deliberate: an order payload of 50 well-formed
 * ULIDs passes every schema and is still unprocessable, which 400 misdescribes.
 * Clients branch on `code`, not on status (AGENTS §4).
 */
export default async function quickLinkRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  const CODE_STATUS = {
    QUICK_LINK_INVALID_TARGET: 'badRequest',
    QUICK_LINK_TARGET_NOT_FOUND: 'notFound',
    QUICK_LINK_DUPLICATE: 'conflict',
    QUICK_LINK_LIMIT: 'unprocessableEntity',
    QUICK_LINK_ORDER_INCOMPLETE: 'unprocessableEntity',
  };

  const CODE_MESSAGE = {
    QUICK_LINK_INVALID_TARGET: 'A shortcut needs either a target of its kind or an http(s) url',
    QUICK_LINK_TARGET_NOT_FOUND: 'Target not found in this workspace',
    QUICK_LINK_DUPLICATE: 'This target is already in your quick access',
    QUICK_LINK_LIMIT: `Quick access holds at most ${QUICK_LINK_MAX_PER_USER} shortcuts`,
    QUICK_LINK_ORDER_INCOMPLETE: 'The order must list every one of your shortcuts exactly once',
  };

  /** Turns a rule code from db/quick-links.js into the matching HTTP error. */
  function fail(code) {
    return coded(app.httpErrors[CODE_STATUS[code]](CODE_MESSAGE[code]), code);
  }

  /** Loads one row and proves the caller may touch it. */
  async function loadOwn(request, quickLinkId) {
    const row = await app
      .db('quick_links')
      .where({ id: quickLinkId })
      .whereNull('deleted_at')
      .first();
    if (!row) {
      throw coded(app.httpErrors.notFound('Quick link not found'), 'QUICK_LINK_NOT_FOUND');
    }
    await app.requireWorkspaceMember(request, row.workspace_id);
    if (row.user_id !== request.user.id) {
      // 404, not 403: the status must not confirm that somebody else's
      // shortcut exists. The distinct code is for our own client's logs.
      throw coded(app.httpErrors.notFound('Quick link not found'), 'QUICK_LINK_NOT_YOURS');
    }
    return row;
  }

  // ── List: the caller's own rail, in order ─────────────────────────────────
  app.get(
    '/workspaces/:workspaceId/quick-links',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: { type: 'object', properties: { items: { type: 'array', items: quickLinkSchema } } },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const rows = await listUserQuickLinks(app.db, { workspaceId, userId: request.user.id });
      return { items: rows.map(serializeQuickLink) };
    },
  );

  // ── Create ────────────────────────────────────────────────────────────────
  app.post(
    '/workspaces/:workspaceId/quick-links',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['kind', 'title'],
          properties: {
            kind: { type: 'string', enum: QUICK_LINK_KINDS },
            targetId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
            url: { anyOf: [{ type: 'null' }, { type: 'string', maxLength: 2048 }] },
            title: { type: 'string', minLength: 1, maxLength: 200 },
            emoji: { anyOf: [{ type: 'null' }, { type: 'string', minLength: 1, maxLength: 16 }] },
            colorRgb: { anyOf: [{ type: 'null' }, { type: 'string', pattern: COLOR_PATTERN }] },
          },
        },
        response: {
          201: quickLinkSchema,
          400: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
          422: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const userId = request.user.id;
      const kind = request.body.kind;
      const targetId = request.body.targetId ?? null;
      const url = request.body.url ?? null;

      const error = await checkCreatable(app.db, { workspaceId, userId, kind, targetId, url });
      if (error) throw fail(error);

      const id = newId();
      const sortOrder = await nextSortOrder(app.db, { workspaceId, userId });
      try {
        await app.db.transaction(async (trx) => {
          const revision = await recordSyncWrite(trx, {
            workspaceId,
            entityType: 'quick_link',
            entityId: id,
            operation: 'create',
          });
          await trx('quick_links').insert({
            id,
            workspace_id: workspaceId,
            user_id: userId,
            kind,
            target_id: targetId,
            url,
            title: request.body.title.trim(),
            emoji: request.body.emoji ?? null,
            color_rgb: request.body.colorRgb ?? null,
            sort_order: sortOrder,
            revision,
          });
        });
      } catch (err) {
        // Lost a double-tap race against our own uniqueness index.
        if (err?.code === 'ER_DUP_ENTRY') throw fail('QUICK_LINK_DUPLICATE');
        throw err;
      }
      const row = await app.db('quick_links').where({ id }).first();
      return reply.code(201).send(serializeQuickLink(row));
    },
  );

  // ── Rename / emoji / colour ───────────────────────────────────────────────
  // The target is immutable by design: re-pointing a shortcut is remove + add,
  // and order is never a single-row write (see PUT .../order).
  app.patch(
    '/quick-links/:quickLinkId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { quickLinkId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 200 },
            emoji: { anyOf: [{ type: 'null' }, { type: 'string', minLength: 1, maxLength: 16 }] },
            colorRgb: { anyOf: [{ type: 'null' }, { type: 'string', pattern: COLOR_PATTERN }] },
          },
        },
        response: { 200: quickLinkSchema, 400: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadOwn(request, request.params.quickLinkId);
      const patch = {};
      if (request.body.title !== undefined) patch.title = request.body.title.trim();
      if ('emoji' in request.body) patch.emoji = request.body.emoji ?? null;
      if ('colorRgb' in request.body) patch.color_rgb = request.body.colorRgb ?? null;
      if (Object.keys(patch).length === 0) {
        // Fastify's Ajv STRIPS unknown body keys rather than refusing them, so
        // an attempt to retarget (`{targetId}`) arrives here as an empty patch.
        // Saying so beats burning a revision on a write that changes nothing.
        throw coded(
          app.httpErrors.badRequest('Nothing to update — a target is immutable'),
          'QUICK_LINK_EMPTY_PATCH',
        );
      }

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'quick_link',
          entityId: row.id,
          operation: 'update',
          changedFields: Object.keys(patch),
        });
        await trx('quick_links')
          .where({ id: row.id })
          .update({ ...patch, revision, updated_at: new Date() });
      });
      const fresh = await app.db('quick_links').where({ id: row.id }).first();
      return serializeQuickLink(fresh);
    },
  );

  // ── Remove ────────────────────────────────────────────────────────────────
  app.delete(
    '/quick-links/:quickLinkId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { quickLinkId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadOwn(request, request.params.quickLinkId);
      await app.db.transaction(async (trx) => {
        await softDeleteQuickLink(trx, { workspaceId: row.workspace_id, id: row.id });
      });
      return reply.code(204).send();
    },
  );

  // ── Reorder (the whole list, one transaction) ─────────────────────────────
  app.put(
    '/workspaces/:workspaceId/quick-links/order',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['orderedIds'],
          properties: {
            orderedIds: {
              type: 'array',
              minItems: 1,
              maxItems: QUICK_LINK_MAX_PER_USER,
              items: ULID_PARAM,
            },
          },
        },
        response: {
          200: { type: 'object', properties: { items: { type: 'array', items: quickLinkSchema } } },
          403: errorResponseSchema,
          422: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const userId = request.user.id;
      const { orderedIds } = request.body;

      const error = await validateOrder(app.db, { workspaceId, userId, orderedIds });
      if (error) throw fail(error);

      await app.db.transaction(async (trx) => {
        await writeQuickLinkOrder(trx, { workspaceId, userId, orderedIds });
      });
      const rows = await listUserQuickLinks(app.db, { workspaceId, userId });
      return { items: rows.map(serializeQuickLink) };
    },
  );
}
