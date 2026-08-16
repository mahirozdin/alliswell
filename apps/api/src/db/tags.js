import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { slugify } from '../lib/slug.js';
import { recordSyncWrite } from './sync.js';

/**
 * The tag domain (OPH-261) — the same extraction `db/notes.js` documents, for
 * the entity OPH-263's `list_tags` / `create_tag` tools need.
 *
 * The slug rules travel with it: a tag's slug follows its name, and uniqueness
 * is enforced twice on purpose — a fast pre-check for the friendly 409, and the
 * `(workspace_id, slug)` index for the race. Both belong here rather than in a
 * route closure, or an MCP tool would have to reimplement them and would get
 * the race wrong.
 */

export function slugTakenError(app) {
  return coded(
    app.httpErrors.conflict('A tag with this name already exists in the workspace'),
    'TAG_SLUG_TAKEN',
  );
}

export async function loadTag(app, id) {
  const row = await app.db('tags').where({ id }).whereNull('deleted_at').first();
  if (!row) throw coded(app.httpErrors.notFound('Tag not found'), 'TAG_NOT_FOUND');
  return row;
}

/**
 * The unique index also covers soft-deleted rows, so this pre-check gives the
 * friendly 409 while the index stays authoritative for concurrent inserts.
 */
export async function assertSlugFree(app, workspaceId, slug, excludeId) {
  let query = app.db('tags').where({ workspace_id: workspaceId, slug });
  if (excludeId) query = query.whereNot('id', excludeId);
  if (await query.first('id')) throw slugTakenError(app);
}

/** Turns the index's own error into the same 409 the pre-check raises. */
export function wrapSlugRace(app, err) {
  if (err?.code === 'ER_DUP_ENTRY' && err.message.includes('uq_tags_workspace_slug')) {
    throw slugTakenError(app);
  }
  throw err;
}

export async function listTags(app, workspaceId) {
  return app
    .db('tags')
    .where({ workspace_id: workspaceId })
    .whereNull('deleted_at')
    .orderBy('name', 'asc')
    .select();
}

export async function createTag(app, { workspaceId, body }) {
  const name = body.name.trim();
  const slug = slugify(name, 'tag');
  await assertSlugFree(app, workspaceId, slug);

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
        ...(body.colorRgb ? { color_rgb: body.colorRgb } : {}),
        ...('icon' in body ? { icon: body.icon } : {}),
        revision,
      });
    });
  } catch (err) {
    wrapSlugRace(app, err);
  }
  return id;
}
