import { diffWords } from 'diff';

import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { loadNote, createNote, updateNote, parseDelta } from '../db/notes.js';
import { versionSnapshotOf } from '../db/note-versions.js';
import { serializeNoteSnapshot } from './notes.js';
import { noteRelations } from '../db/notes.js';

/**
 * Note history (OPH-267, ADR-0031): read it, restore from it, diff against it.
 *
 * An ONLINE surface — versions never descend to the replica (ADR-0031 §1), so
 * these routes are the only way to see history and the app says so plainly
 * when the server is unreachable (DESIGN §35 V6).
 *
 * Restore never rewrites history (§7): `replace` applies the old body as a NEW
 * head write, so the state you are leaving is captured too and you can go back
 * again. `copy` makes a new note, which is what people want when they are not
 * yet sure.
 */

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const MAX_PAGE_SIZE = 100;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const versionRowSchema = {
  type: 'object',
  required: ['id', 'origin', 'createdAt'],
  properties: {
    id: { type: 'string' },
    noteId: { type: 'string' },
    noteRevision: { type: 'integer' },
    title: { type: 'string' },
    contentFormat: { type: 'string' },
    origin: { type: 'string' },
    clientId: { type: ['string', 'null'] },
    createdBy: { type: ['string', 'null'] },
    sizeBytes: { type: 'integer' },
    createdAt: { type: 'string' },
  },
};

const versionDetailSchema = {
  ...versionRowSchema,
  properties: {
    ...versionRowSchema.properties,
    contentMarkdown: { type: ['string', 'null'] },
    contentDelta: { type: ['array', 'null'] },
  },
};

/** List metadata: enough to choose a version, never the body. */
function serializeVersionRow(row) {
  const body = row.content_markdown ?? row.content_delta ?? '';
  return {
    id: row.id,
    noteId: row.note_id,
    noteRevision: Number(row.note_revision ?? 0),
    title: row.title,
    contentFormat: row.content_format,
    origin: row.origin,
    // The app compares this with its own client id to say "this device".
    clientId: row.client_id ?? null,
    createdBy: row.created_by ?? null,
    sizeBytes: Buffer.byteLength(String(body), 'utf8'),
    createdAt: toIso(row.created_at),
  };
}

function serializeVersionDetail(row) {
  return {
    ...serializeVersionRow(row),
    contentMarkdown: row.content_markdown ?? null,
    // ADR-0033: never shipped. See `serializeNoteSnapshot` for the reasoning —
    // a version viewer that could show two different bodies for one moment in
    // a note's history would be worse than one that shows the document.
    contentDelta: null,
  };
}

/**
 * The text a diff compares.
 *
 * Every version is markdown after the 2026-08-18 migration (ADR-0033), so the
 * delta branch is a floor, not a path: a diff that silently compared "" would
 * render the whole note as newly added.
 */
function comparableText(snapshot, plainTextFallback = '') {
  if ((snapshot.content_format ?? 'markdown') === 'markdown')
    return snapshot.content_markdown ?? '';
  const delta = parseDelta(snapshot.content_delta);
  if (!delta) return plainTextFallback;
  return delta
    .map((op) => (typeof op.insert === 'string' ? op.insert : ''))
    .join('')
    .trimEnd();
}

export default async function noteVersionRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  /** The note, proven to be this caller's, plus one of its versions. */
  async function loadOwn(request, { versionId } = {}) {
    const note = await loadNote(app, request.params.noteId);
    await app.requireWorkspaceMember(request, note.workspace_id);
    if (!versionId) return { note, version: null };
    const version = await app
      .db('note_versions')
      .where({ id: versionId, note_id: note.id })
      .first();
    if (!version) {
      throw coded(app.httpErrors.notFound('Version not found'), 'NOTE_VERSION_NOT_FOUND');
    }
    return { note, version };
  }

  app.get(
    '/notes/:noteId/versions',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { noteId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: MAX_PAGE_SIZE, default: 50 },
            cursor: ULID_PARAM,
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              items: { type: 'array', items: versionRowSchema },
              nextCursor: { type: ['string', 'null'] },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { note } = await loadOwn(request);
      const q = request.query;
      let query = app
        .db('note_versions')
        .where({ note_id: note.id })
        .orderBy('id', 'desc')
        .limit(q.limit);
      if (q.cursor) query = query.where('id', '<', q.cursor);
      const rows = await query.select();
      return {
        items: rows.map(serializeVersionRow),
        nextCursor: rows.length === q.limit ? rows.at(-1).id : null,
      };
    },
  );

  app.get(
    '/notes/:noteId/versions/:versionId',
    {
      ...auth,
      schema: {
        params: {
          type: 'object',
          properties: { noteId: ULID_PARAM, versionId: ULID_PARAM },
        },
        response: { 200: versionDetailSchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const { version } = await loadOwn(request, { versionId: request.params.versionId });
      return serializeVersionDetail(version);
    },
  );

  // Word-level diff, computed here (ADR-0031 §8): the client only draws it, and
  // two diff engines in two languages would answer one question twice.
  app.get(
    '/notes/:noteId/versions/:versionId/diff',
    {
      ...auth,
      schema: {
        params: {
          type: 'object',
          properties: { noteId: ULID_PARAM, versionId: ULID_PARAM },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              segments: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    type: { type: 'string', enum: ['equal', 'added', 'removed'] },
                    value: { type: 'string' },
                  },
                },
              },
              comparable: { type: 'boolean' },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { note, version } = await loadOwn(request, { versionId: request.params.versionId });
      const before = comparableText(version, version.title);
      const after = comparableText(versionSnapshotOf(note), note.plain_text ?? '');
      const segments = diffWords(before, after).map((part) => ({
        type: part.added ? 'added' : part.removed ? 'removed' : 'equal',
        value: part.value,
      }));
      return {
        segments,
        // Under ADR-0028 a version and its note could be different KINDS of
        // document, and the pair was then compared as flattened text — this
        // flag is what told the reader so, instead of shipping a silently
        // poorer diff. ADR-0033 left one kind, so it is now always true; the
        // field stays because the client renders on it and removing it is a
        // wire-contract change with nothing to gain.
        comparable: (version.content_format ?? 'markdown') === (note.content_format ?? 'markdown'),
      };
    },
  );

  app.post(
    '/notes/:noteId/versions/:versionId/restore',
    {
      ...auth,
      schema: {
        params: {
          type: 'object',
          properties: { noteId: ULID_PARAM, versionId: ULID_PARAM },
        },
        body: {
          type: 'object',
          additionalProperties: false,
          properties: { mode: { type: 'string', enum: ['replace', 'copy'], default: 'replace' } },
        },
        response: {
          200: { type: 'object', additionalProperties: true },
          403: errorResponseSchema,
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { note, version } = await loadOwn(request, { versionId: request.params.versionId });
      const body = {
        title: version.title,
        contentFormat: version.content_format,
        contentMarkdown: version.content_markdown ?? null,
        contentDelta: parseDelta(version.content_delta),
      };

      if (request.body?.mode === 'copy') {
        // A copy leaves the current note completely alone — the "I am not sure
        // yet" answer (Standard Notes' second verb).
        const id = await createNote(app, {
          workspaceId: note.workspace_id,
          userId: request.user.id,
          body: { ...body, projectId: note.project_id ?? null },
          origin: 'restore',
        });
        const fresh = await loadNote(app, id);
        const { links, tagIds } = await noteRelations(app, id);
        return serializeNoteSnapshot(fresh, links, tagIds);
      }

      // Replace: a NEW head write, so the state being left behind is itself
      // captured and this is undoable in turn (ADR-0031 §7).
      await updateNote(app, {
        row: note,
        userId: request.user.id,
        body,
        origin: 'restore',
      });
      const fresh = await loadNote(app, note.id);
      const { links, tagIds } = await noteRelations(app, note.id);
      return serializeNoteSnapshot(fresh, links, tagIds);
    },
  );
}
