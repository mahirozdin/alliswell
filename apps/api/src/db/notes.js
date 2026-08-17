import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import {
  deltaToMarkdown,
  deltaToPlainText,
  embedFileIds,
  isValidDelta,
  markdownToPlainText,
} from '../lib/delta.js';
import { recordSyncWrite } from './sync.js';
import { captureNoteVersion, isContentWrite } from './note-versions.js';
import { mergeMarkdown } from '../lib/note-merge.js';

/**
 * The note domain (OPH-261) — everything a note write does, minus HTTP.
 *
 * ADR-0022 §4 binds this: MCP is a client of the domain layer, never of raw
 * SQL, so `create_note` and REST must be ONE implementation with one set of
 * assertions, one revision bookkeeping and one transaction shape. Until this
 * extraction the logic lived inside the route closures, which left the MCP
 * tools with a choice between duplicating it and reaching past it. `db/tasks.js`
 * set the pattern when the same problem arrived for tasks.
 *
 * What stayed in `routes/notes.js`: Ajv schemas, status codes, and the
 * serializers the sync pull also imports. What moved here: the asserts, the
 * row mapping and the writes. The proof that nothing else changed is that the
 * route suites pass untouched.
 */

/** Loads a live note or throws the route's own 404. */
export async function loadNote(app, id) {
  const row = await app.db('notes').where({ id }).whereNull('deleted_at').first();
  if (!row) throw coded(app.httpErrors.notFound('Note not found'), 'NOTE_NOT_FOUND');
  return row;
}

/** The links and tags a full note snapshot carries. */
export async function noteRelations(app, noteId) {
  const [links, tagRows] = await Promise.all([
    app.db('note_links').where({ note_id: noteId }).orderBy('created_at', 'asc').select(),
    app.db('note_tags').where({ note_id: noteId }).select('tag_id'),
  ]);
  return { links, tagIds: tagRows.map((r) => r.tag_id) };
}

export async function assertProjectUsable(app, projectId, workspaceId) {
  const project = await app
    .db('projects')
    .where({ id: projectId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first('id');
  if (!project) {
    throw coded(
      app.httpErrors.badRequest('projectId does not reference a project in this workspace'),
      'NOTE_INVALID_PROJECT',
    );
  }
}

/**
 * camelCase body → row values.
 *
 * @param {object} app
 * @param {object} body
 * @param {object} [opts]
 * @param {string} [opts.currentFormat] the row's format when the patch does not
 *   set one — the write has to know which field is canonical.
 * @param {string} [opts.currentMarkdown] the row's markdown, for the case where
 *   a note BECOMES markdown-canonical without its body being resent.
 */
export function toRowPatch(app, body, { currentFormat, currentMarkdown } = {}) {
  const row = {};
  if ('title' in body) row.title = body.title;
  if ('contentDelta' in body) {
    if (body.contentDelta !== null && !isValidDelta(body.contentDelta)) {
      throw coded(
        app.httpErrors.badRequest('contentDelta must be an array of Quill insert ops'),
        'NOTE_INVALID_DELTA',
      );
    }
    row.content_delta = body.contentDelta === null ? null : JSON.stringify(body.contentDelta);
    row.plain_text = deltaToPlainText(body.contentDelta);
  }
  if ('contentMarkdown' in body) row.content_markdown = body.contentMarkdown;
  if ('contentFormat' in body) row.content_format = body.contentFormat;
  // OPH-261: the search column follows whichever field is CANONICAL.
  //
  // Before this, `plain_text` was written only in the delta branch above, so a
  // markdown-canonical note (ADR-0028) kept an empty or stale one and was
  // invisible to `?q=`, to FULLTEXT and to the MCP search tools. It existed and
  // could not be found — §22's reachability rule, seen from the search side.
  const format = body.contentFormat ?? currentFormat ?? 'delta';
  if (format === 'markdown') {
    const markdown = 'contentMarkdown' in body ? body.contentMarkdown : currentMarkdown;
    if (markdown !== undefined) row.plain_text = markdownToPlainText(markdown ?? '');
  }
  if ('projectId' in body) row.project_id = body.projectId;
  if ('isPinned' in body) row.is_pinned = body.isPinned;
  if ('isArchived' in body) row.is_archived = body.isArchived;
  return row;
}

/** What a note may be linked to (OPH-041): v1 targets are tasks and projects. */
export const NOTE_LINK_TABLES = { task: 'tasks', project: 'projects' };

export async function assertLinkTarget(app, entityType, entityId, workspaceId) {
  const table = NOTE_LINK_TABLES[entityType];
  const row = await app
    .db(table)
    .where({ id: entityId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first('id');
  if (!row) {
    throw coded(
      app.httpErrors.badRequest(`${entityType} not found in this workspace`),
      'NOTE_INVALID_LINK_TARGET',
    );
  }
}

/** One link row of a note, by id or by what it points at. */
export async function findNoteLink(app, noteId, { id, entityType, entityId }) {
  const where = { note_id: noteId };
  if (id) where.id = id;
  if (entityType) where.linked_entity_type = entityType;
  if (entityId) where.linked_entity_id = entityId;
  return (await app.db('note_links').where(where).first()) ?? null;
}

/**
 * Links a note to a task or project (OPH-041, extracted in OPH-263). The link
 * is a note field as far as sync is concerned: the revision lands on the NOTE,
 * because that is the row a client pulls to learn the link exists.
 */
export async function linkNote(app, { row, userId, entityType, entityId }) {
  await assertLinkTarget(app, entityType, entityId, row.workspace_id);
  if (await findNoteLink(app, row.id, { entityType, entityId })) {
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
      .update({ revision, updated_by: userId, updated_at: new Date() });
  });
}

/** Removes one link row, with the note's revision bump. */
export async function unlinkNote(app, { row, userId, link }) {
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
      .update({ revision, updated_by: userId, updated_at: new Date() });
  });
}

/**
 * Creates a note with its sync revision, in one transaction. Returns the id.
 *
 * `links` (OPH-263) are inserted in the SAME transaction, because a note that
 * arrived without the link the caller asked for would be a different thing
 * than what was requested — the `createNoteFromTask` argument, generalized.
 */
export async function createNote(
  app,
  {
    workspaceId,
    userId,
    body,
    createdFromTaskId = null,
    links = [],
    origin = 'edit',
    clientId = null,
  },
) {
  if (body.projectId) await assertProjectUsable(app, body.projectId, workspaceId);
  for (const link of links) {
    await assertLinkTarget(app, link.entityType, link.entityId, workspaceId);
  }

  const id = newId();
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'note',
      entityId: id,
      operation: 'create',
    });
    await trx('notes').insert({
      id,
      workspace_id: workspaceId,
      ...(createdFromTaskId ? { created_from_task_id: createdFromTaskId } : {}),
      ...toRowPatch(app, body),
      created_by: userId,
      updated_by: userId,
      revision,
    });
    for (const link of links) {
      await trx('note_links').insert({
        id: newId(),
        note_id: id,
        linked_entity_type: link.entityType,
        linked_entity_id: link.entityId,
      });
    }
    // OPH-267: the note's first state is version one — without it there is
    // nothing to restore an over-eager first edit back to.
    const fresh = await trx('notes').where({ id }).first();
    await captureNoteVersion(trx, {
      config: app.config,
      row: fresh,
      origin,
      clientId,
      userId,
    });
  });
  return id;
}

/**
 * Creates a note that belongs to a task: inherits the task's project, records
 * `created_from_task_id`, and links the two — all in ONE transaction.
 *
 * A separate function rather than a flag on [createNote] because the link is
 * not optional decoration here: this is the operation "turn this task into a
 * note", and a note that arrived without its link would be a different thing.
 * OPH-263's `create_note(taskId:)` tool is the second caller.
 */
export async function createNoteFromTask(app, { task, userId, body }) {
  const id = newId();
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: task.workspace_id,
      entityType: 'note',
      entityId: id,
      operation: 'create',
    });
    await trx('notes').insert({
      id,
      workspace_id: task.workspace_id,
      project_id: task.project_id ?? null, // inherited from the task
      created_from_task_id: task.id,
      ...toRowPatch(app, { title: task.title, ...body }),
      created_by: userId,
      updated_by: userId,
      revision,
    });
    await trx('note_links').insert({
      id: newId(),
      note_id: id,
      linked_entity_type: 'task',
      linked_entity_id: task.id,
    });
  });
  return id;
}

/**
 * Applies a patch to a live note row, with revision + changed-field bookkeeping
 * — and, when the write touched content, one version row (OPH-267, ADR-0031).
 *
 * `origin`/`clientId` travel from the caller because they are the only ones who
 * know: REST edit vs API key vs MCP tool vs sync push vs import vs restore.
 * Everything else about history is decided here, once.
 */
export async function updateNote(app, { row, userId, body, origin = 'edit', clientId = null }) {
  if (body.projectId) await assertProjectUsable(app, body.projectId, row.workspace_id);

  const patch = toRowPatch(app, body, {
    currentFormat: row.content_format,
    currentMarkdown: row.content_markdown,
  });
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'note',
      entityId: row.id,
      operation: 'update',
      changedFields: Object.keys(patch),
    });
    await trx('notes')
      .where({ id: row.id })
      .update({ ...patch, revision, updated_by: userId, updated_at: new Date() });
    // A pin, an archive or a project move is not content: those must not burn
    // a version (or the history screen becomes a log of flag toggles).
    if (isContentWrite(patch)) {
      const fresh = await trx('notes').where({ id: row.id }).first();
      await captureNoteVersion(trx, {
        config: app.config,
        row: fresh,
        origin,
        clientId,
        userId,
      });
    }
  });
}

/**
 * Replace-set of a note's tags (OPH-261).
 *
 * Deliberately not part of the note PUSH protocol: a client cannot change tags
 * through sync in v1, and the pull snapshot reads them alongside links.
 */
export async function setNoteTags(app, { row, userId, tagIds }) {
  const desired = [...new Set(tagIds)];
  if (desired.length > 0) {
    const found = await app
      .db('tags')
      .whereIn('id', desired)
      .where({ workspace_id: row.workspace_id })
      .whereNull('deleted_at')
      .select('id');
    if (found.length !== desired.length) {
      throw coded(
        app.httpErrors.badRequest('One or more tags do not exist in this workspace'),
        'NOTE_TAG_NOT_FOUND',
      );
    }
  }

  const current = (await app.db('note_tags').where({ note_id: row.id }).select('tag_id')).map(
    (r) => r.tag_id,
  );
  const toAdd = desired.filter((id) => !current.includes(id));
  const toRemove = current.filter((id) => !desired.includes(id));
  if (toAdd.length === 0 && toRemove.length === 0) return;

  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'note',
      entityId: row.id,
      operation: 'update',
      changedFields: ['tags'],
    });
    if (toRemove.length > 0) {
      await trx('note_tags').where({ note_id: row.id }).whereIn('tag_id', toRemove).delete();
    }
    if (toAdd.length > 0) {
      await trx('note_tags').insert(toAdd.map((tagId) => ({ note_id: row.id, tag_id: tagId })));
    }
    await trx('notes')
      .where({ id: row.id })
      .update({ revision, updated_by: userId, updated_at: new Date() });
  });
}

/**
 * What to do with a content write whose author had an older version of the
 * note (OPH-268, finding #1).
 *
 * The base is compared against the NOTE's own revision — not the workspace
 * pull cursor, which is what made the optimistic lock useless: a socket-driven
 * pull moved the cursor past the other person's write, so the lock saw
 * "nothing foreign happened" and the body was silently overwritten.
 *
 * Merging is only attempted when ALL THREE sides are markdown-canonical
 * (decision #7): a Delta is a JSON op array, and line-merging JSON produces
 * something that is not a document. Anything else takes the conflict path,
 * which loses nothing — the incoming body is stored as a version.
 *
 * @returns {Promise<{outcome:'apply'}|{outcome:'merge', contentMarkdown:string}|
 *   {outcome:'conflict', reason:'BASE_MISSING'|'NOT_MARKDOWN'|'OVERLAP'}>}
 */
export async function threeWayNoteWrite(app, { row, baseRevision, incoming }) {
  const current = Number(row.revision ?? 0);
  // No base (an older client) or an up-to-date base: nothing foreign happened
  // to THIS note, so this is an ordinary write. A protocol that breaks its own
  // old clients is not a protocol.
  if (baseRevision == null || baseRevision >= current) return { outcome: 'apply' };

  const incomingFormat = incoming.contentFormat ?? row.content_format ?? 'delta';
  if (incomingFormat !== 'markdown' || (row.content_format ?? 'delta') !== 'markdown') {
    return { outcome: 'conflict', reason: 'NOT_MARKDOWN' };
  }

  // The base body has to still exist. Retention thins old versions (ADR-0031
  // §6), so a client that was offline for months legitimately finds nothing —
  // an honest conflict, not a guess.
  const base = await app
    .db('note_versions')
    .where({ note_id: row.id, note_revision: baseRevision })
    .orderBy('id', 'desc')
    .first();
  if (!base) return { outcome: 'conflict', reason: 'BASE_MISSING' };
  if ((base.content_format ?? 'delta') !== 'markdown') {
    return { outcome: 'conflict', reason: 'NOT_MARKDOWN' };
  }

  const merged = mergeMarkdown(
    base.content_markdown ?? '',
    row.content_markdown ?? '',
    incoming.contentMarkdown ?? '',
  );
  if (!merged.ok) return { outcome: 'conflict', reason: 'OVERLAP' };
  return { outcome: 'merge', contentMarkdown: merged.text };
}

/**
 * Stores a REFUSED body as a version (OPH-268, decision #8 / V1).
 *
 * Its own transaction on purpose: the write it belongs to is being rejected,
 * and the losing side must survive that rejection — "the overwritten body is
 * in no table" is the bug this epic exists to end. Returns the version id, so
 * the client can be handed a `conflictVersionId` to point its banner at.
 */
export async function storeConflictVersion(app, { row, incoming, userId = null, clientId = null }) {
  let versionId = null;
  await app.db.transaction(async (trx) => {
    const { id } = await captureNoteVersion(trx, {
      config: app.config,
      // The note as the CLIENT believed it to be — that is what is being kept.
      row: {
        ...row,
        title: incoming.title ?? row.title,
        content_markdown: incoming.contentMarkdown ?? row.content_markdown,
        content_delta: incoming.contentDelta ?? row.content_delta,
        content_format: incoming.contentFormat ?? row.content_format,
      },
      origin: 'conflict',
      clientId,
      userId,
    });
    versionId = id;
  });
  return versionId;
}

/** A note's markdown, following its canonical field (OPH-261 Repair 2). */
export async function exportNoteMarkdown(app, row) {
  const delta = parseDelta(row.content_delta);
  // Attachment embeds export with their CURRENT file name as the label
  // (OPH-152) — the alliswell://file/{id} source stays stable either way.
  let embedLabel;
  const fileIds = delta ? embedFileIds(delta) : [];
  if (fileIds.length > 0) {
    const files = await app
      .db('files')
      .whereIn('id', fileIds)
      .whereNull('deleted_at')
      .select('id', 'name');
    const names = new Map(files.map((f) => [`alliswell://file/${f.id}`, f.name]));
    embedLabel = (source) => names.get(source) ?? null;
  }
  // The export follows `content_format`. It used to prefer the delta whenever
  // one existed, so a markdown-canonical note — whose delta is a stale shadow
  // of an earlier life — exported the wrong document.
  if (row.content_format === 'markdown') return row.content_markdown ?? '';
  return delta ? deltaToMarkdown(delta, { embedLabel }) : (row.content_markdown ?? '');
}

/** JSON column that may arrive as a string, depending on the driver. */
export function parseDelta(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch {
      return null;
    }
  }
  return value;
}
