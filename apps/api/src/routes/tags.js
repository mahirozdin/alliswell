import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { slugify } from '../lib/slug.js';
import { recordSyncWrite } from '../db/sync.js';
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

function serializeTag(row) {
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

function slugTakenError(app) {
  return coded(
    app.httpErrors.conflict('A tag with this name already exists in the workspace'),
    'TAG_SLUG_TAKEN',
  );
}

export default async function tagRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  async function loadTag(id) {
    const row = await app.db('tags').where({ id }).whereNull('deleted_at').first();
    if (!row) throw coded(app.httpErrors.notFound('Tag not found'), 'TAG_NOT_FOUND');
    return row;
  }

  // The (workspace_id, slug) unique index also covers soft-deleted rows, so a
  // fast pre-check gives the friendly 409 and the index stays authoritative
  // for races (ER_DUP_ENTRY → same 409).
  async function assertSlugFree(workspaceId, slug, excludeId) {
    let query = app.db('tags').where({ workspace_id: workspaceId, slug });
    if (excludeId) query = query.whereNot('id', excludeId);
    if (await query.first('id')) throw slugTakenError(app);
  }

  const wrapSlugRace = (err) => {
    if (err?.code === 'ER_DUP_ENTRY' && err.message.includes('uq_tags_workspace_slug')) {
      throw slugTakenError(app);
    }
    throw err;
  };

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
      const rows = await app
        .db('tags')
        .where({ workspace_id: workspaceId })
        .whereNull('deleted_at')
        .orderBy('name', 'asc')
        .select();
      return { items: rows.map(serializeTag) };
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

      const name = request.body.name.trim();
      const slug = slugify(name, 'tag');
      await assertSlugFree(workspaceId, slug);

      const id = newId();
      try {
        await app.db.transaction(async (trx) => {
          const revision = await recordSyncWrite(trx, {
            workspaceId,
            entityType: 'tag',
            entityId: id,
            operation: 'create',
          });
          await trx('tags').insert({
            id,
            workspace_id: workspaceId,
            name,
            slug,
            ...(request.body.colorRgb ? { color_rgb: request.body.colorRgb } : {}),
            ...('icon' in request.body ? { icon: request.body.icon } : {}),
            revision,
          });
        });
      } catch (err) {
        wrapSlugRace(err);
      }

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
