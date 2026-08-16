import { toIso } from '../lib/serialize.js';
import { slugify } from '../lib/slug.js';
import { recordSyncWrite } from '../db/sync.js';
import * as domain from '../db/tags.js';
import { COLOR_PATTERN } from './projects.js';

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

const tagSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'name', 'slug', 'colorRgb', 'revision'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    name: { type: 'string' },
    slug: { type: 'string' },
    colorRgb: { type: 'string' },
    icon: { type: ['string', 'null'] },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

const writableProps = {
  name: { type: 'string', minLength: 1, maxLength: 100 },
  colorRgb: { type: 'string', pattern: COLOR_PATTERN },
  icon: { type: ['string', 'null'], maxLength: 64 },
};

export function serializeTag(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    name: row.name,
    slug: row.slug,
    colorRgb: row.color_rgb,
    icon: row.icon ?? null,
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

export default async function tagRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  // OPH-261: the writes and the slug rules live in `db/tags.js`, so an MCP
  // tool cannot reimplement them and get the race wrong (ADR-0022 §4).
  const loadTag = (id) => domain.loadTag(app, id);
  const assertSlugFree = (workspaceId, slug, excludeId) =>
    domain.assertSlugFree(app, workspaceId, slug, excludeId);
  const wrapSlugRace = (err) => domain.wrapSlugRace(app, err);

  app.get(
    '/workspaces/:workspaceId/tags',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: { type: 'object', properties: { items: { type: 'array', items: tagSchema } } },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      return { items: (await domain.listTags(app, workspaceId)).map(serializeTag) };
    },
  );

  app.post(
    '/workspaces/:workspaceId/tags',
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
        response: { 201: tagSchema, 403: errorResponseSchema, 409: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      const id = await domain.createTag(app, { workspaceId, body: request.body });
      return reply.code(201).send(serializeTag(await loadTag(id)));
    },
  );

  app.get(
    '/tags/:tagId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { tagId: ULID_PARAM } },
        response: { 200: tagSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadTag(request.params.tagId);
      await app.requireWorkspaceMember(request, row.workspace_id);
      return serializeTag(row);
    },
  );

  app.patch(
    '/tags/:tagId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { tagId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: writableProps,
        },
        response: {
          200: tagSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadTag(request.params.tagId);
      await app.requireWorkspaceMember(request, row.workspace_id);

      const patch = {};
      if ('name' in request.body) {
        patch.name = request.body.name.trim();
        patch.slug = slugify(patch.name, 'tag'); // the slug follows the name
        if (patch.slug !== row.slug) await assertSlugFree(row.workspace_id, patch.slug, row.id);
      }
      if ('colorRgb' in request.body) patch.color_rgb = request.body.colorRgb;
      if ('icon' in request.body) patch.icon = request.body.icon;

      try {
        await app.db.transaction(async (trx) => {
          const revision = await recordSyncWrite(trx, {
            workspaceId: row.workspace_id,
            entityType: 'tag',
            entityId: row.id,
            operation: 'update',
            changedFields: Object.keys(patch),
          });
          await trx('tags')
            .where({ id: row.id })
            .update({ ...patch, revision, updated_at: new Date() });
        });
      } catch (err) {
        wrapSlugRace(err);
      }

      return serializeTag(await loadTag(row.id));
    },
  );

  app.delete(
    '/tags/:tagId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { tagId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadTag(request.params.tagId);
      // Tags are lightweight metadata — any member may delete (unlike projects).
      await app.requireWorkspaceMember(request, row.workspace_id);

      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'tag',
          entityId: row.id,
          operation: 'delete',
        });
        await trx('tags')
          .where({ id: row.id })
          .update({
            deleted_at: new Date(),
            // Free the (workspace, slug) slot — the unique index also covers
            // soft-deleted rows, and a recreated tag must be able to reuse it.
            slug: `${row.slug}--deleted--${row.id.slice(-8).toLowerCase()}`,
            revision,
            updated_at: new Date(),
          });
      });

      return reply.code(204).send();
    },
  );
}
