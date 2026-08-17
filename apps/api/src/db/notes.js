import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { deltaToMarkdown, isValidDelta, markdownToPlainText } from '../lib/delta.js';
import { recordSyncWrite } from './sync.js';
import { transactionWithRetry } from './tx.js';
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
 * Drops the `# <title>` line a pre-ADR-0033 client prefixed onto the markdown
 * it derived from a Delta (`note_document.dart` `bodyFor`).
 *
 * The title lives in its own column; leaving the heading in the body would
 * make every migrated note render its title twice. Only ever applied to a
 * write that declares itself Delta-canonical — a markdown-canonical note never
 * had the prefix added, so a user who genuinely typed `# My title` as their
 * first line keeps it.
 */
function stripTitleHeading(markdown, title) {
  if (typeof markdown !== 'string' || typeof title !== 'string' || title.trim() === '') {
    return markdown;
  }
  const [first, ...rest] = markdown.split('\n');
  if (first.trim() !== `# ${title.trim()}`) return markdown;
  while (rest.length > 0 && rest[0].trim() === '') rest.shift();
  return rest.join('\n');
}

/**
 * The markdown a write means, whatever shape it arrived in (ADR-0033).
 *
 * Markdown is now a note's ONLY canonical content, but a Delta may still
 * ARRIVE: the web client updates the moment we deploy, while the phone in
 * someone's pocket keeps running the previous release for weeks. That client
 * sends all three of `contentDelta`, `contentMarkdown` and `contentFormat` on
 * every save, so nothing is lost by taking the markdown and dropping the
 * delta — a protocol that breaks its own old clients is not a protocol.
 *
 * For a Delta-canonical write the markdown is re-derived here rather than
 * trusted: our converter and the client's are mirrors, but ours is the one
 * that stays maintained, and deriving avoids the title-heading heuristic
 * entirely. (No embed labels: resolving `alliswell://file/{id}` to file names
 * would put a query in the write path, and the label is decoration — the URI,
 * which is what the renderer resolves, survives either way.)
 *
 * @returns {string|null} null when the body carries no content at all.
 */
export function noteMarkdownFrom(body, { currentFormat, currentMarkdown, title } = {}) {
  const hasMarkdown = 'contentMarkdown' in body;
  const hasDelta = 'contentDelta' in body;
  if (!hasMarkdown && !hasDelta) return null;

  // A body that carries ONLY a delta is a Delta write whatever it says about
  // itself: `contentFormat` is optional on the wire, and a patch that omits it
  // while sending ops would otherwise be read as "markdown, and the markdown is
  // missing" — which silently empties the note.
  const declared = body.contentFormat ?? (hasMarkdown ? (currentFormat ?? 'markdown') : 'delta');
  if (declared === 'markdown') {
    return (hasMarkdown ? body.contentMarkdown : currentMarkdown) ?? '';
  }
  if (hasDelta && Array.isArray(body.contentDelta)) return deltaToMarkdown(body.contentDelta);
  return stripTitleHeading((hasMarkdown ? body.contentMarkdown : currentMarkdown) ?? '', title);
}

/**
 * camelCase body → row values.
 *
 * @param {object} app
 * @param {object} body
 * @param {object} [opts]
 * @param {string} [opts.currentFormat] the row's format when the patch does not
 *   set one — the write has to know what shape the body it did not resend is in.
 * @param {string} [opts.currentMarkdown] the row's markdown, for the case where
 *   only the format is being restated.
 * @param {string} [opts.currentTitle] the row's title, for [stripTitleHeading].
 */
export function toRowPatch(app, body, { currentFormat, currentMarkdown, currentTitle } = {}) {
  const row = {};
  if ('title' in body) row.title = body.title;
  if ('contentDelta' in body && body.contentDelta !== null && !isValidDelta(body.contentDelta)) {
    throw coded(
      app.httpErrors.badRequest('contentDelta must be an array of Quill insert ops'),
      'NOTE_INVALID_DELTA',
    );
  }

  // ADR-0033: every content write lands as markdown, and `content_delta` is
  // never written again. The column keeps its old rows — a lossless escape
  // hatch — but nothing adds to them.
  const markdown = noteMarkdownFrom(body, {
    currentFormat,
    currentMarkdown,
    title: body.title ?? currentTitle,
  });
  if (markdown !== null) {
    row.content_markdown = markdown;
    row.content_format = 'markdown';
    // OPH-261: the search column follows the canonical field. Before that it
    // was written only when a delta arrived, so a markdown note carried an
    // empty one and could not be found — §22's reachability rule, seen from
    // the search side. With one canonical field there is one derivation.
    row.plain_text = markdownToPlainText(markdown);
  } else if ('contentFormat' in body) {
    row.content_format = 'markdown';
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

  await transactionWithRetry(app.db, async (trx) => {
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
  await transactionWithRetry(app.db, async (trx) => {
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
  await transactionWithRetry(app.db, async (trx) => {
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
  await transactionWithRetry(app.db, async (trx) => {
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
    currentTitle: row.title,
  });
  await transactionWithRetry(app.db, async (trx) => {
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

  await transactionWithRetry(app.db, async (trx) => {
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
 * ## ADR-0033 removed this path's biggest hole
 *
 * Merging used to be attempted only when ALL THREE sides were
 * markdown-canonical (ADR-0031 decision #7) — a Delta is a JSON op array, and
 * line-merging JSON produces something that is not a document. Since notes had
 * two canonical forms, the common case refused to merge and every conflict
 * between two Delta notes fell through to the banner. Now there is one form:
 * the row is markdown, its versions are markdown, and a Delta arriving from a
 * client that predates the change is CONVERTED on the way in rather than
 * refused. `NOT_MARKDOWN` is gone because it can no longer happen.
 *
 * @returns {Promise<{outcome:'apply'}|{outcome:'merge', contentMarkdown:string}|
 *   {outcome:'conflict', reason:'BASE_MISSING'|'OVERLAP'}>}
 */
export async function threeWayNoteWrite(app, { row, baseRevision, incoming }) {
  const current = Number(row.revision ?? 0);
  // No base (an older client) or an up-to-date base: nothing foreign happened
  // to THIS note, so this is an ordinary write. A protocol that breaks its own
  // old clients is not a protocol.
  if (baseRevision == null || baseRevision >= current) return { outcome: 'apply' };

  const theirs = noteMarkdownFrom(incoming, {
    currentFormat: row.content_format,
    currentMarkdown: row.content_markdown,
    title: incoming.title ?? row.title,
  });
  // A write that carries no body at all (a pin, a project move) has nothing to
  // merge and nothing to lose.
  if (theirs === null) return { outcome: 'apply' };

  // The base body has to still exist. Retention thins old versions (ADR-0031
  // §6), so a client that was offline for months legitimately finds nothing —
  // an honest conflict, not a guess.
  const base = await app
    .db('note_versions')
    .where({ note_id: row.id, note_revision: baseRevision })
    .orderBy('id', 'desc')
    .first();
  if (!base) return { outcome: 'conflict', reason: 'BASE_MISSING' };

  const merged = mergeMarkdown(versionMarkdown(base), row.content_markdown ?? '', theirs);
  if (!merged.ok) return { outcome: 'conflict', reason: 'OVERLAP' };
  return { outcome: 'merge', contentMarkdown: merged.text };
}

/**
 * A stored version's markdown. The 2026-08-18 migration converted every
 * pre-existing version row, so the delta fallback should never fire — it is
 * here because a merge base that silently reads as empty would produce a
 * "merge" that quietly deleted the other side's paragraphs.
 */
function versionMarkdown(version) {
  if ((version.content_format ?? 'markdown') === 'markdown') return version.content_markdown ?? '';
  const delta = parseDelta(version.content_delta);
  return delta ? deltaToMarkdown(delta) : (version.content_markdown ?? '');
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
  const title = incoming.title ?? row.title;
  // Stored the way every other version is stored (ADR-0033): as markdown. A
  // Delta from an older client is converted rather than kept, so "Restore this
  // version" a month from now hands back a document the app can still open.
  const markdown =
    noteMarkdownFrom(incoming, {
      currentFormat: row.content_format,
      currentMarkdown: row.content_markdown,
      title,
    }) ??
    row.content_markdown ??
    '';

  let versionId = null;
  await transactionWithRetry(app.db, async (trx) => {
    const { id } = await captureNoteVersion(trx, {
      config: app.config,
      // The note as the CLIENT believed it to be — that is what is being kept.
      row: { ...row, title, content_markdown: markdown, content_format: 'markdown' },
      origin: 'conflict',
      clientId,
      userId,
    });
    versionId = id;
  });
  return versionId;
}

/**
 * A note as a standalone `.md` file (OPH-045, revised by ADR-0033).
 *
 * The body no longer needs a format branch — there is one canonical field. What
 * it does need is its TITLE: that lives in its own column precisely so the
 * stored body never repeats it, which means an exported file would otherwise
 * arrive untitled. The heading is added here, at the edge, and never stored.
 *
 * Embed labels are no longer rewritten to the files' current names (OPH-152
 * did that for Delta, whose embeds had no label a person could have written).
 * In markdown the label is part of the document: `![my diagram](…)` is the
 * author's words, and an export that replaced them with `diagram-final-2.png`
 * would be editing the note on its way out.
 */
export async function exportNoteMarkdown(app, row) {
  const body = row.content_markdown ?? '';
  const title = (row.title ?? '').trim();
  if (title === '') return body;
  return body === '' ? `# ${title}\n` : `# ${title}\n\n${body}`;
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
