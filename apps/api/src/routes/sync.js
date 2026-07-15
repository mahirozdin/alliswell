/**
 * Sync protocol endpoints (Epic 06, BLUEPRINT §6):
 *
 * - OPH-051 `GET  /sync/pull`  — incremental changes since a workspace revision:
 *   batched, entity snapshots for create/update, tombstones for delete.
 * - OPH-052 `POST /sync/push`  — offline mutation batches with per-mutation
 *   result statuses and field-level last-write-wins for metadata (§6.5); note
 *   CONTENT is document-level optimistically locked and never auto-merged.
 * - OPH-053 idempotency — every mutation outcome is recorded in
 *   `client_mutations`; a replayed (clientId, clientMutationId) returns the
 *   recorded result without re-applying.
 *
 * Conflict policy in practice: a patch field is in conflict when a FOREIGN
 * writer (any client/user except this clientId — attribution via recorded
 * `result_revision`s) changed the same column after the pusher's
 * `baseRevision`. The newer wall-clock write wins: the client's
 * `localUpdatedAt` vs. the row's server-canonical `updated_at`. Losing fields
 * are discarded individually (`discardedFields`); a mutation that loses every
 * field comes back as `conflict`/`SYNC_STALE_MUTATION`.
 */
import { newId } from '../lib/ids.js';
import { toIso } from '../lib/serialize.js';
import { slugify } from '../lib/slug.js';
import { deltaToPlainText, isValidDelta } from '../lib/delta.js';
import { recordSyncWrite } from '../db/sync.js';
import { reconcileTaskReminder } from '../db/reminders.js';
import { PROJECT_STATUSES, COLOR_PATTERN, serializeProject } from './projects.js';
import { serializeTag } from './tags.js';
import { TASK_STATUSES, TASK_PRIORITIES, serializeTask, serializeChecklistItem } from './tasks.js';
import { serializeNoteSnapshot } from './notes.js';

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };
const ULID_RE = /^[0-9A-HJKMNP-TV-Z]{26}$/;
const COLOR_RE = new RegExp(COLOR_PATTERN);
const MAX_PULL_LIMIT = 500;
const MAX_PUSH_MUTATIONS = 100;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

// ── Patch-field validators (sync mutations skip the REST Ajv schemas, so the
//    same constraints are enforced here, per field, with per-mutation errors) ─

const str =
  (max, min = 1) =>
  (v) =>
    typeof v === 'string' && v.length >= min && v.length <= max;
const strOrNull = (max) => (v) => v === null || (typeof v === 'string' && v.length <= max);
const bool = (v) => typeof v === 'boolean';
const intIn = (min, max) => (v) => Number.isInteger(v) && v >= min && v <= max;
const intOrNull = (min, max) => (v) => v === null || intIn(min, max)(v);
const oneOf = (values) => (v) => values.includes(v);
const isoOrNull = (v) => v === null || (typeof v === 'string' && !Number.isNaN(Date.parse(v)));
const ulid = (v) => typeof v === 'string' && ULID_RE.test(v);
const ulidOrNull = (v) => v === null || ulid(v);
const color = (v) => typeof v === 'string' && COLOR_RE.test(v);
const colorOrNull = (v) => v === null || color(v);
const ulidArray = (v) => Array.isArray(v) && v.length <= 50 && v.every(ulid);

const toDate = (v) => (v == null ? null : new Date(v));

// Field spec: patch key → { col, ok, date? , virtual? , createOnly? }.
// `virtual` fields never land in the row patch directly — the entity handler
// applies them (task tags, note delta) — but they still participate in LWW
// under their REST changed-fields name.

const PROJECT_FIELDS = {
  name: { col: 'name', ok: str(255) },
  description: { col: 'description', ok: strOrNull(65535) },
  colorRgb: { col: 'color_rgb', ok: color },
  icon: { col: 'icon', ok: strOrNull(64) },
  status: { col: 'status', ok: oneOf(PROJECT_STATUSES) },
  startAt: { col: 'start_at', ok: isoOrNull, date: true },
  dueAt: { col: 'due_at', ok: isoOrNull, date: true },
  sortOrder: { col: 'sort_order', ok: intIn(-1000000, 1000000) },
  isFavorite: { col: 'is_favorite', ok: bool },
  readmeNoteId: { col: 'readme_note_id', ok: ulidOrNull },
};

const TAG_FIELDS = {
  name: { col: 'name', ok: str(100) },
  colorRgb: { col: 'color_rgb', ok: color },
  icon: { col: 'icon', ok: strOrNull(64) },
};

const TASK_FIELDS = {
  title: { col: 'title', ok: str(500) },
  description: { col: 'description', ok: strOrNull(65535) },
  projectId: { col: 'project_id', ok: ulidOrNull },
  parentTaskId: { col: 'parent_task_id', ok: ulidOrNull },
  status: { col: 'status', ok: oneOf(TASK_STATUSES) },
  priority: { col: 'priority', ok: oneOf(TASK_PRIORITIES) },
  colorRgb: { col: 'color_rgb', ok: colorOrNull },
  startAt: { col: 'start_at', ok: isoOrNull, date: true },
  dueAt: { col: 'due_at', ok: isoOrNull, date: true },
  scheduledStartAt: { col: 'scheduled_start_at', ok: isoOrNull, date: true },
  scheduledEndAt: { col: 'scheduled_end_at', ok: isoOrNull, date: true },
  remindAt: { col: 'remind_at', ok: isoOrNull, date: true },
  timezone: { col: 'timezone', ok: str(64) },
  isUrgent: { col: 'is_urgent', ok: bool },
  requiresAcknowledgement: { col: 'requires_acknowledgement', ok: bool },
  repeatRule: { col: 'repeat_rule', ok: strOrNull(2000) },
  estimatedMinutes: { col: 'estimated_minutes', ok: intOrNull(0, 60000) },
  actualMinutes: { col: 'actual_minutes', ok: intOrNull(0, 60000) },
  sortOrder: { col: 'sort_order', ok: intIn(-1000000, 1000000) },
  // Replace-set, like `PUT /tasks/:id/tags`; logged as 'tags' (REST parity).
  tagIds: { col: 'tags', ok: ulidArray, virtual: true },
  calendarMirrorEnabled: { col: 'calendar_mirror_enabled', ok: bool },
  // Offline snooze (OPH-062): unlike REST's POST /tasks/:id/snooze this
  // accepts past instants — a queued mutation may arrive after the moment
  // passed, and dropping a user's snooze would be worse. Update-only.
  snoozedUntil: { col: 'snoozed_until', ok: isoOrNull, date: true, updateOnly: true },
};

// Devices may acknowledge an alarm offline (OPH-063). Everything else about
// reminders stays server-managed through task writes.
const REMINDER_FIELDS = {
  status: { col: 'status', ok: oneOf(['acknowledged']), updateOnly: true },
};

const NOTE_FIELDS = {
  title: { col: 'title', ok: str(500) },
  contentDelta: { col: 'content_delta', ok: (v) => v === null || Array.isArray(v), virtual: true },
  contentMarkdown: { col: 'content_markdown', ok: strOrNull(1000000) },
  projectId: { col: 'project_id', ok: ulidOrNull },
  isPinned: { col: 'is_pinned', ok: bool },
  isArchived: { col: 'is_archived', ok: bool },
};

const CHECKLIST_FIELDS = {
  taskId: { col: 'task_id', ok: ulid, createOnly: true },
  title: { col: 'title', ok: str(500) },
  isDone: { col: 'is_done', ok: bool },
  sortOrder: { col: 'sort_order', ok: intIn(-1000000, 1000000) },
};

// Note CONTENT is doc-level locked (§6.5) — these intents never LWW-merge.
const NOTE_CONTENT_INTENTS = new Set(['content_delta', 'content_markdown']);

export function serializeReminder(row) {
  return {
    id: row.id,
    taskId: row.task_id,
    remindAt: toIso(row.remind_at),
    timezone: row.timezone,
    alarmLevel: row.alarm_level,
    requiresAcknowledgement: Boolean(row.requires_acknowledgement),
    repeatRule: row.repeat_rule ?? null,
    status: row.status,
    snoozedUntil: toIso(row.snoozed_until),
    deliveredAt: toIso(row.delivered_at),
    acknowledgedAt: toIso(row.acknowledged_at),
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * The user's own calendar events (OPH-082, ADR-0008) — a read-only cache of
 * someone else's system. No provider ids beyond what the app needs to open the
 * event, and nothing writable: the app renders these, it never edits them.
 */
export function serializeExternalEvent(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    summary: row.summary ?? null,
    location: row.location ?? null,
    startsAt: toIso(row.starts_at),
    endsAt: toIso(row.ends_at),
    isAllDay: Boolean(row.is_all_day),
    isBusy: Boolean(row.is_busy),
    htmlLink: row.html_link ?? null,
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/** mysql2 may hand JSON columns back as strings or parsed values. */
function parseJson(value) {
  if (value == null) return null;
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

export default async function syncRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  // ══ OPH-051 — incremental pull ═════════════════════════════════════════════

  // Batch snapshot loaders, one per sync entity type: id list → Map(id → row).
  const SNAPSHOT_LOADERS = {
    project: async (ids) => ({
      rows: await app.db('projects').whereIn('id', ids).select(),
      serialize: serializeProject,
    }),
    tag: async (ids) => ({
      rows: await app.db('tags').whereIn('id', ids).select(),
      serialize: serializeTag,
    }),
    task: async (ids) => {
      const [rows, tagRows] = await Promise.all([
        app.db('tasks').whereIn('id', ids).select(),
        app.db('task_tags').whereIn('task_id', ids).select(),
      ]);
      const tagsByTask = new Map();
      for (const t of tagRows) {
        if (!tagsByTask.has(t.task_id)) tagsByTask.set(t.task_id, []);
        tagsByTask.get(t.task_id).push(t.tag_id);
      }
      return {
        rows,
        serialize: (row) => ({
          ...serializeTask(row),
          tagIds: (tagsByTask.get(row.id) ?? []).sort(),
        }),
      };
    },
    note: async (ids) => {
      const [rows, linkRows] = await Promise.all([
        app.db('notes').whereIn('id', ids).select(),
        app.db('note_links').whereIn('note_id', ids).orderBy('created_at', 'asc').select(),
      ]);
      const linksByNote = new Map();
      for (const l of linkRows) {
        if (!linksByNote.has(l.note_id)) linksByNote.set(l.note_id, []);
        linksByNote.get(l.note_id).push(l);
      }
      return {
        rows,
        serialize: (row) => serializeNoteSnapshot(row, linksByNote.get(row.id) ?? []),
      };
    },
    checklist_item: async (ids) => ({
      rows: await app.db('checklist_items').whereIn('id', ids).select(),
      serialize: serializeChecklistItem,
    }),
    reminder: async (ids) => ({
      rows: await app.db('reminders').whereIn('id', ids).select(),
      serialize: serializeReminder,
    }),
    // OPH-082 — the user's own calendar events (ADR-0008). Read-only: the app
    // shows them next to tasks; `push` refuses to write them back.
    external_event: async (ids) => ({
      rows: await app.db('calendar_external_events').whereIn('id', ids).select(),
      serialize: serializeExternalEvent,
    }),
  };

  app.get(
    '/sync/pull',
    {
      ...auth,
      schema: {
        querystring: {
          type: 'object',
          additionalProperties: false,
          required: ['workspaceId', 'sinceRevision'],
          properties: {
            workspaceId: ULID_PARAM,
            sinceRevision: { type: 'integer', minimum: 0 },
            limit: { type: 'integer', minimum: 1, maximum: MAX_PULL_LIMIT, default: 200 },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              workspaceId: { type: 'string' },
              fromRevision: { type: 'integer' },
              toRevision: { type: 'integer' },
              hasMore: { type: 'boolean' },
              changes: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    revision: { type: 'integer' },
                    entityType: { type: 'string' },
                    entityId: { type: 'string' },
                    operation: { type: 'string', enum: ['create', 'update', 'delete'] },
                    data: { type: ['object', 'null'], additionalProperties: true },
                  },
                },
              },
            },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId, sinceRevision, limit } = request.query;
      await app.requireWorkspaceMember(request, workspaceId);

      // limit+1 probes hasMore without a COUNT query.
      const raw = await app
        .db('sync_revisions')
        .where({ workspace_id: workspaceId })
        .where('revision', '>', sinceRevision)
        .orderBy('revision', 'asc')
        .limit(limit + 1)
        .select();
      const hasMore = raw.length > limit;
      const window = hasMore ? raw.slice(0, limit) : raw;
      const toRevision = window.length > 0 ? Number(window.at(-1).revision) : sinceRevision;

      // Coalesce to the latest change per entity within the window — replicas
      // upsert snapshots of CURRENT state, so intermediate rows carry nothing.
      const latest = new Map();
      for (const row of window) latest.set(`${row.entity_type}:${row.entity_id}`, row);
      const kept = [...latest.values()].sort((a, b) => Number(a.revision) - Number(b.revision));

      const byType = new Map();
      for (const row of kept) {
        if (!byType.has(row.entity_type)) byType.set(row.entity_type, []);
        byType.get(row.entity_type).push(row.entity_id);
      }

      const snapshots = new Map(); // `${type}:${id}` → serialized data | null
      for (const [type, ids] of byType) {
        const loader = SNAPSHOT_LOADERS[type];
        if (!loader) continue; // unknown/legacy types come through as tombstones
        const { rows, serialize } = await loader(ids);
        for (const row of rows) {
          snapshots.set(`${type}:${row.id}`, row.deleted_at != null ? null : serialize(row));
        }
      }

      const changes = kept.map((row) => {
        const data = snapshots.get(`${row.entity_type}:${row.entity_id}`) ?? null;
        return {
          revision: Number(row.revision),
          entityType: row.entity_type,
          entityId: row.entity_id,
          // A snapshot that is gone (or soft-deleted) is a tombstone, whatever
          // the logged operation was — the delete row may sit past the window.
          operation: data === null ? 'delete' : row.operation,
          data,
        };
      });

      return { workspaceId, fromRevision: sinceRevision, toRevision, hasMore, changes };
    },
  );

  // ══ OPH-052/053 — mutation push with LWW + idempotency ═════════════════════

  const rejected = (errorCode) => ({ status: 'rejected', errorCode });
  const conflict = (errorCode) => ({ status: 'conflict', errorCode });

  /**
   * Builds the row patch + LWW intents from a validated mutation patch.
   * Intents carry the REST changed-fields name and every column the intent
   * owns (derived columns fall together when LWW discards the intent).
   */
  function prepare(entityKey, fields, patch, row) {
    const rowPatch = {};
    const intents = [];
    for (const [key, value] of Object.entries(patch)) {
      const spec = fields[key];
      const intent = { name: spec.col, camel: key, cols: [] };
      if (!spec.virtual) {
        rowPatch[spec.col] = spec.date ? toDate(value) : value;
        intent.cols.push(spec.col);
      }
      if (entityKey === 'tag' && key === 'name') {
        rowPatch.name = value.trim();
        rowPatch.slug = slugify(rowPatch.name, 'tag'); // the slug follows the name
        intent.cols.push('slug');
      }
      if (entityKey === 'task' && key === 'status' && row) {
        // completed_at side effects, matching REST completionPatch.
        if (value === 'completed' && row.status !== 'completed') {
          rowPatch.completed_at = new Date();
          intent.cols.push('completed_at');
        } else if (value !== 'completed' && row.status === 'completed') {
          rowPatch.completed_at = null;
          intent.cols.push('completed_at');
        }
      }
      if (entityKey === 'note' && key === 'contentDelta') {
        rowPatch.content_delta = value === null ? null : JSON.stringify(value);
        rowPatch.plain_text = deltaToPlainText(value);
        intent.cols.push('content_delta', 'plain_text');
      }
      intents.push(intent);
    }
    return { rowPatch, intents };
  }

  /**
   * Fields changed since baseRevision by anyone EXCEPT this client. Own writes
   * are attributed through client_mutations.result_revision, so a client that
   * pushes twice before pulling does not conflict with itself.
   */
  async function foreignChangesSince(ctx, entityType, entityId) {
    const rows = await app
      .db('sync_revisions')
      .where({ workspace_id: ctx.workspaceId, entity_type: entityType, entity_id: entityId })
      .where('revision', '>', ctx.baseRevision)
      .select('revision', 'operation', 'changed_fields');
    if (rows.length === 0) return { all: false, fields: new Set() };

    const own = await app
      .db('client_mutations')
      .where({ client_id: ctx.clientId, workspace_id: ctx.workspaceId })
      .whereIn(
        'result_revision',
        rows.map((r) => Number(r.revision)),
      )
      .select('result_revision');
    const ownRevisions = new Set(own.map((r) => Number(r.result_revision)));

    const fields = new Set();
    for (const r of rows.filter((r) => !ownRevisions.has(Number(r.revision)))) {
      const changed = r.operation === 'update' ? parseJson(r.changed_fields) : null;
      if (!Array.isArray(changed)) return { all: true, fields }; // create/delete → everything
      for (const f of changed) fields.add(f);
    }
    return { all: false, fields };
  }

  async function assertProjectRef(projectId, workspaceId, code) {
    const project = await app
      .db('projects')
      .where({ id: projectId, workspace_id: workspaceId })
      .whereNull('deleted_at')
      .first('id');
    return project ? null : code;
  }

  async function taskGuards(ctx, patch, row) {
    if (patch.projectId) {
      const err = await assertProjectRef(patch.projectId, ctx.workspaceId, 'TASK_INVALID_PROJECT');
      if (err) return err;
    }
    if (patch.parentTaskId) {
      if (row && patch.parentTaskId === row.id) return 'TASK_PARENT_CYCLE';
      const parent = await app
        .db('tasks')
        .where({ id: patch.parentTaskId, workspace_id: ctx.workspaceId })
        .whereNull('deleted_at')
        .first('id', 'parent_task_id');
      if (!parent) return 'TASK_INVALID_PARENT';
      let cursor = parent.parent_task_id;
      for (let depth = 0; cursor && depth < 100; depth += 1) {
        if (row && cursor === row.id) return 'TASK_PARENT_CYCLE';
        const next = await app.db('tasks').where({ id: cursor }).first('parent_task_id');
        cursor = next?.parent_task_id ?? null;
      }
    }
    if (patch.tagIds) {
      const unique = [...new Set(patch.tagIds)];
      const found = await app
        .db('tags')
        .whereIn('id', unique)
        .where({ workspace_id: ctx.workspaceId })
        .whereNull('deleted_at')
        .select('id');
      if (found.length !== unique.length) return 'TASK_INVALID_TAG';
    }
    if (patch.timezone !== undefined) {
      try {
        new Intl.DateTimeFormat('en-US', { timeZone: patch.timezone });
      } catch {
        return 'TASK_INVALID_TIMEZONE';
      }
    }
    // Urgent alarms demand acknowledgement unless the caller opts out (REST parity).
    if (patch.isUrgent === true && patch.requiresAcknowledgement === undefined) {
      patch.requiresAcknowledgement = true;
    }
    // Snoozing a finished task is meaningless (REST snooze parity).
    if (
      patch.snoozedUntil != null &&
      row &&
      (row.status === 'completed' || row.status === 'cancelled')
    ) {
      return 'TASK_INVALID_TRANSITION';
    }
    return null;
  }

  /**
   * Mirrors the REST snooze endpoint's reminder side (OPH-035/OPH-062): a
   * task's snooze silences (or, when cleared, re-arms) its active alarm in
   * the same transaction. Call AFTER reconcileTaskReminder with the fresh row.
   */
  async function applyReminderSnooze(trx, workspaceId, task) {
    const active = await trx('reminders')
      .where({ task_id: task.id })
      .whereNull('deleted_at')
      .whereIn('status', ['scheduled', 'snoozed', 'delivered'])
      .orderBy('created_at', 'desc')
      .first();
    if (!active) return;

    const snoozed = task.snoozed_until != null;
    const patch = snoozed
      ? { status: 'snoozed', snoozed_until: new Date(task.snoozed_until) }
      : { status: 'scheduled', snoozed_until: null };
    if (!snoozed && active.status !== 'snoozed') return; // nothing to clear

    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'reminder',
      entityId: active.id,
      operation: 'update',
      changedFields: ['status', 'snoozed_until'],
    });
    await trx('reminders')
      .where({ id: active.id })
      .update({ ...patch, revision, updated_at: new Date() });
  }

  async function replaceTaskTags(trx, taskId, tagIds) {
    const desired = [...new Set(tagIds)];
    await trx('task_tags').where({ task_id: taskId }).delete();
    if (desired.length > 0) {
      await trx('task_tags').insert(desired.map((tagId) => ({ task_id: taskId, tag_id: tagId })));
    }
  }

  // Per-entity handlers. Each returns an outcome object; `applied` outcomes
  // are produced by `applyWrite`, which also records the client_mutations row
  // inside the SAME transaction as the entity write.
  const ENTITIES = {
    project: {
      table: 'projects',
      fields: PROJECT_FIELDS,
      requiredOnCreate: ['name'],
      deleteRoles: ['owner', 'admin'], // REST parity: destructive, member cannot
      workspaceOf: (row) => row.workspace_id,
      async guard(ctx, patch) {
        if (patch.readmeNoteId) {
          const note = await app
            .db('notes')
            .where({ id: patch.readmeNoteId, workspace_id: ctx.workspaceId })
            .whereNull('deleted_at')
            .first('id');
          if (!note) return 'PROJECT_INVALID_README_NOTE';
        }
        return null;
      },
      insertRow: (ctx, mutation, rowPatch) => ({
        id: mutation.entityId,
        workspace_id: ctx.workspaceId,
        ...rowPatch,
        created_by: ctx.userId,
        updated_by: ctx.userId,
      }),
      updateExtra: (ctx) => ({ updated_by: ctx.userId }),
      deleteExtra: (ctx) => ({ updated_by: ctx.userId }),
    },

    tag: {
      table: 'tags',
      fields: TAG_FIELDS,
      requiredOnCreate: ['name'],
      workspaceOf: (row) => row.workspace_id,
      async guard(ctx, patch, row) {
        if (patch.name !== undefined) {
          const slug = slugify(patch.name.trim(), 'tag');
          if (!row || slug !== row.slug) {
            let query = app.db('tags').where({ workspace_id: ctx.workspaceId, slug });
            if (row) query = query.whereNot('id', row.id);
            if (await query.first('id')) return 'TAG_SLUG_TAKEN';
          }
        }
        return null;
      },
      insertRow: (ctx, mutation, rowPatch) => ({
        id: mutation.entityId,
        workspace_id: ctx.workspaceId,
        ...rowPatch,
      }),
      // Free the (workspace, slug) slot exactly like the REST delete.
      deletePatch: (row) => ({
        slug: `${row.slug}--deleted--${row.id.slice(-8).toLowerCase()}`,
      }),
    },

    task: {
      table: 'tasks',
      fields: TASK_FIELDS,
      requiredOnCreate: ['title'],
      workspaceOf: (row) => row.workspace_id,
      guard: taskGuards,
      beforeUpdate(patch, row) {
        // Archived tasks accept exactly one write: a lone unarchiving status.
        const isUnarchive =
          Object.keys(patch).length === 1 &&
          patch.status !== undefined &&
          patch.status !== 'archived';
        if (row.status === 'archived' && !isUnarchive) return 'TASK_ARCHIVED';
        return null;
      },
      insertRow: (ctx, mutation, rowPatch) => ({
        id: mutation.entityId,
        workspace_id: ctx.workspaceId,
        ...rowPatch,
        created_by: ctx.userId,
        updated_by: ctx.userId,
      }),
      updateExtra: (ctx) => ({ updated_by: ctx.userId }),
      deleteExtra: (ctx) => ({ updated_by: ctx.userId }),
      async afterCreate(trx, ctx, mutation) {
        if (mutation.patch.tagIds?.length > 0) {
          await replaceTaskTags(trx, mutation.entityId, mutation.patch.tagIds);
        }
        const fresh = await trx('tasks').where({ id: mutation.entityId }).first();
        await reconcileTaskReminder(trx, { workspaceId: ctx.workspaceId, task: fresh });
      },
      async afterUpdate(trx, ctx, mutation, row, keptIntents) {
        if (keptIntents.some((i) => i.name === 'tags')) {
          await replaceTaskTags(trx, row.id, mutation.patch.tagIds);
        }
        const fresh = await trx('tasks').where({ id: row.id }).first();
        await reconcileTaskReminder(trx, { workspaceId: ctx.workspaceId, task: fresh });
        if (keptIntents.some((i) => i.name === 'snoozed_until')) {
          await applyReminderSnooze(trx, ctx.workspaceId, fresh);
        }
      },
      // Soft delete cascades through the subtree, one revision per task, and
      // silences reminders — mirrors DELETE /tasks/:id.
      async customDelete(trx, ctx, row) {
        let frontier = [row.id];
        const seen = new Set(frontier);
        let headRevision;
        while (frontier.length > 0) {
          for (const id of frontier) {
            const revision = await recordSyncWrite(trx, {
              workspaceId: ctx.workspaceId,
              entityType: 'task',
              entityId: id,
              operation: 'delete',
            });
            if (id === row.id) headRevision = revision;
            await trx('tasks').where({ id }).update({
              deleted_at: new Date(),
              revision,
              updated_by: ctx.userId,
              updated_at: new Date(),
            });
            const fresh = await trx('tasks').where({ id }).first();
            await reconcileTaskReminder(trx, { workspaceId: ctx.workspaceId, task: fresh });
          }
          const children = await trx('tasks')
            .whereIn('parent_task_id', frontier)
            .whereNull('deleted_at')
            .select('id');
          frontier = children.map((c) => c.id).filter((id) => !seen.has(id));
          for (const id of frontier) seen.add(id);
        }
        return headRevision;
      },
    },

    note: {
      table: 'notes',
      fields: NOTE_FIELDS,
      requiredOnCreate: ['title'],
      contentIntents: NOTE_CONTENT_INTENTS,
      workspaceOf: (row) => row.workspace_id,
      async guard(ctx, patch) {
        if (
          'contentDelta' in patch &&
          patch.contentDelta !== null &&
          !isValidDelta(patch.contentDelta)
        ) {
          return 'NOTE_INVALID_DELTA';
        }
        if (patch.projectId) {
          return assertProjectRef(patch.projectId, ctx.workspaceId, 'NOTE_INVALID_PROJECT');
        }
        return null;
      },
      insertRow: (ctx, mutation, rowPatch) => ({
        id: mutation.entityId,
        workspace_id: ctx.workspaceId,
        ...rowPatch,
        created_by: ctx.userId,
        updated_by: ctx.userId,
      }),
      updateExtra: (ctx) => ({ updated_by: ctx.userId }),
      deleteExtra: (ctx) => ({ updated_by: ctx.userId }),
    },

    // Narrow on purpose (OPH-063): devices may only ACKNOWLEDGE an alarm
    // offline — reminder rows are otherwise server-managed via task writes.
    reminder: {
      table: 'reminders',
      fields: REMINDER_FIELDS,
      operations: ['update'],
      requiredOnCreate: [],
      async ownershipOk(ctx, row) {
        const task = await app
          .db('tasks')
          .where({ id: row.task_id, workspace_id: ctx.workspaceId })
          .first('id');
        return Boolean(task);
      },
      beforeUpdate(patch, row) {
        // A silenced alarm has nothing left to acknowledge.
        if (row.status === 'cancelled' || row.status === 'completed') {
          return 'REMINDER_INVALID_TRANSITION';
        }
        return null;
      },
      updateExtra: () => ({ acknowledged_at: new Date() }),
    },

    checklist_item: {
      table: 'checklist_items',
      fields: CHECKLIST_FIELDS,
      requiredOnCreate: ['taskId', 'title'],
      // Workspace ownership flows through the parent task.
      async resolveParent(ctx, taskId) {
        const task = await app
          .db('tasks')
          .where({ id: taskId, workspace_id: ctx.workspaceId })
          .whereNull('deleted_at')
          .first('id', 'status');
        if (!task) return { error: 'SYNC_ENTITY_NOT_FOUND' };
        if (task.status === 'archived') return { error: 'TASK_ARCHIVED' };
        return { task };
      },
      async guard(ctx, patch, row) {
        const parent = await this.resolveParent(ctx, row ? row.task_id : patch.taskId);
        return parent.error ?? null;
      },
      async ownershipOk(ctx, row) {
        const task = await app
          .db('tasks')
          .where({ id: row.task_id, workspace_id: ctx.workspaceId })
          .first('id');
        return Boolean(task);
      },
      insertRow: (ctx, mutation, rowPatch) => ({
        id: mutation.entityId,
        ...rowPatch,
      }),
    },
  };

  async function findRecorded(ctx, mutation) {
    const row = await app
      .db('client_mutations')
      .where({ client_id: ctx.clientId, client_mutation_id: mutation.clientMutationId })
      .first();
    if (!row) return null;
    return {
      status: row.status,
      revision: row.result_revision == null ? null : Number(row.result_revision),
      errorCode: row.error_code ?? null,
      replayed: true,
    };
  }

  function recordRow(trxOrDb, ctx, mutation, { status, revision, errorCode }) {
    return trxOrDb('client_mutations').insert({
      id: newId(),
      workspace_id: ctx.workspaceId,
      user_id: ctx.userId,
      client_id: ctx.clientId,
      client_mutation_id: mutation.clientMutationId,
      entity_type: String(mutation.entityType).slice(0, 64),
      entity_id: mutation.entityId,
      operation: mutation.operation,
      status,
      result_revision: revision ?? null,
      error_code: errorCode ?? null,
    });
  }

  async function applyCreate(ctx, mutation, entity) {
    if (!ULID_RE.test(mutation.entityId)) return rejected('SYNC_INVALID_ENTITY_ID');
    for (const required of entity.requiredOnCreate) {
      if (mutation.patch[required] === undefined) return rejected('SYNC_INVALID_PATCH');
    }
    const existing = await app.db(entity.table).where({ id: mutation.entityId }).first('id');
    if (existing) return rejected('SYNC_ENTITY_EXISTS');

    const patch = { ...mutation.patch };
    const guardError = await entity.guard?.(ctx, patch, null);
    if (guardError) return rejected(guardError);

    const { rowPatch } = prepare(mutation.entityType, entity.fields, patch, null);
    let revision;
    await app.db.transaction(async (trx) => {
      revision = await recordSyncWrite(trx, {
        workspaceId: ctx.workspaceId,
        entityType: mutation.entityType,
        entityId: mutation.entityId,
        operation: 'create',
      });
      await trx(entity.table).insert({
        ...entity.insertRow(ctx, { ...mutation, patch }, rowPatch),
        revision,
      });
      await entity.afterCreate?.(trx, ctx, { ...mutation, patch });
      await recordRow(trx, ctx, mutation, { status: 'applied', revision });
    });
    return { status: 'applied', revision, recorded: true };
  }

  async function applyUpdate(ctx, mutation, entity) {
    const row = await app.db(entity.table).where({ id: mutation.entityId }).first();
    if (!row) return rejected('SYNC_ENTITY_NOT_FOUND');
    if (entity.workspaceOf && entity.workspaceOf(row) !== ctx.workspaceId) {
      return rejected('SYNC_ENTITY_NOT_FOUND'); // cross-workspace: do not leak
    }
    if (entity.ownershipOk && !(await entity.ownershipOk(ctx, row))) {
      return rejected('SYNC_ENTITY_NOT_FOUND');
    }
    if (row.deleted_at != null) return rejected('SYNC_ENTITY_DELETED');

    const patch = { ...mutation.patch };
    const preError = entity.beforeUpdate?.(patch, row);
    if (preError) return rejected(preError);
    const guardError = await entity.guard?.(ctx, patch, row);
    if (guardError) return rejected(guardError);

    const prepared = prepare(mutation.entityType, entity.fields, patch, row);
    const foreign = await foreignChangesSince(ctx, mutation.entityType, mutation.entityId);
    const overlapping = prepared.intents.filter((i) => foreign.all || foreign.fields.has(i.name));

    const discardedFields = [];
    let keptIntents = prepared.intents;
    if (overlapping.length > 0) {
      // Note content never merges: doc-level optimistic lock (§6.5). The
      // client resolves by pulling and making a conflict copy (OPH-056).
      if (entity.contentIntents && overlapping.some((i) => entity.contentIntents.has(i.name))) {
        return conflict('NOTE_CONTENT_CONFLICT');
      }
      const clientTime = mutation.localUpdatedAt ? Date.parse(mutation.localUpdatedAt) : 0;
      const serverTime = row.updated_at ? new Date(row.updated_at).getTime() : 0;
      if (clientTime <= serverTime) {
        for (const intent of overlapping) {
          discardedFields.push(intent.camel);
          for (const col of intent.cols) delete prepared.rowPatch[col];
        }
        keptIntents = prepared.intents.filter((i) => !overlapping.includes(i));
        if (keptIntents.length === 0) return conflict('SYNC_STALE_MUTATION');
      }
    }

    const changedFields = [
      ...Object.keys(prepared.rowPatch),
      ...keptIntents.filter((i) => i.cols.length === 0).map((i) => i.name),
    ];
    let revision;
    await app.db.transaction(async (trx) => {
      revision = await recordSyncWrite(trx, {
        workspaceId: ctx.workspaceId,
        entityType: mutation.entityType,
        entityId: mutation.entityId,
        operation: 'update',
        changedFields,
      });
      await trx(entity.table)
        .where({ id: row.id })
        .update({
          ...prepared.rowPatch,
          ...(entity.updateExtra ? entity.updateExtra(ctx) : {}),
          revision,
          updated_at: new Date(), // server clock is canonical (§6.5)
        });
      await entity.afterUpdate?.(trx, ctx, { ...mutation, patch }, row, keptIntents);
      await recordRow(trx, ctx, mutation, { status: 'applied', revision });
    });
    return { status: 'applied', revision, discardedFields, recorded: true };
  }

  async function applyDelete(ctx, mutation, entity) {
    const row = await app.db(entity.table).where({ id: mutation.entityId }).first();
    if (!row) return rejected('SYNC_ENTITY_NOT_FOUND');
    if (entity.workspaceOf && entity.workspaceOf(row) !== ctx.workspaceId) {
      return rejected('SYNC_ENTITY_NOT_FOUND');
    }
    if (entity.ownershipOk && !(await entity.ownershipOk(ctx, row))) {
      return rejected('SYNC_ENTITY_NOT_FOUND');
    }
    if (entity.deleteRoles && !entity.deleteRoles.includes(ctx.role)) {
      return rejected('AUTH_WORKSPACE_FORBIDDEN');
    }
    if (row.deleted_at != null) {
      // Idempotent: already gone, nothing to redo — echo the row's revision.
      return { status: 'applied', revision: Number(row.revision) };
    }

    let revision;
    await app.db.transaction(async (trx) => {
      if (entity.customDelete) {
        revision = await entity.customDelete(trx, ctx, row);
      } else {
        revision = await recordSyncWrite(trx, {
          workspaceId: ctx.workspaceId,
          entityType: mutation.entityType,
          entityId: mutation.entityId,
          operation: 'delete',
        });
        await trx(entity.table)
          .where({ id: row.id })
          .update({
            deleted_at: new Date(),
            ...(entity.deletePatch ? entity.deletePatch(row) : {}),
            ...(entity.deleteExtra ? entity.deleteExtra(ctx) : {}),
            revision,
            updated_at: new Date(),
          });
      }
      await recordRow(trx, ctx, mutation, { status: 'applied', revision });
    });
    return { status: 'applied', revision, recorded: true };
  }

  async function computeAndApply(ctx, mutation) {
    const entity = ENTITIES[mutation.entityType];
    if (!entity) return rejected('SYNC_UNSUPPORTED_ENTITY');
    if (entity.operations && !entity.operations.includes(mutation.operation)) {
      return rejected('SYNC_UNSUPPORTED_OPERATION');
    }

    if (mutation.operation !== 'delete') {
      const { patch } = mutation;
      if (typeof patch !== 'object' || patch === null || Array.isArray(patch)) {
        return rejected('SYNC_INVALID_PATCH');
      }
      if (Object.keys(patch).length === 0) return rejected('SYNC_INVALID_PATCH');
      for (const [key, value] of Object.entries(patch)) {
        const spec = entity.fields[key];
        if (
          !spec ||
          (spec.createOnly && mutation.operation !== 'create') ||
          (spec.updateOnly && mutation.operation !== 'update')
        ) {
          return rejected('SYNC_UNKNOWN_FIELD');
        }
        if (!spec.ok(value)) return rejected('SYNC_INVALID_VALUE');
      }
    }

    switch (mutation.operation) {
      case 'create':
        return applyCreate(ctx, mutation, entity);
      case 'update':
        return applyUpdate(ctx, mutation, entity);
      default:
        return applyDelete(ctx, mutation, entity);
    }
  }

  async function processMutation(ctx, mutation) {
    const replayed = await findRecorded(ctx, mutation);
    if (replayed) return { clientMutationId: mutation.clientMutationId, ...replayed };

    let outcome;
    try {
      outcome = await computeAndApply(ctx, mutation);
      if (outcome.recorded !== true) {
        // conflict/rejected/idempotent-delete outcomes get recorded outside an
        // entity transaction (there was no entity write to be atomic with).
        await recordRow(app.db, ctx, mutation, outcome);
      }
    } catch (err) {
      if (err?.code !== 'ER_DUP_ENTRY') throw err;
      // Lost an idempotency race (uq_client_mutation or an entity unique
      // index): trust the recorded result / report the entity conflict.
      const recorded = await findRecorded(ctx, mutation);
      if (recorded) return { clientMutationId: mutation.clientMutationId, ...recorded };
      outcome = rejected(mutation.entityType === 'tag' ? 'TAG_SLUG_TAKEN' : 'SYNC_ENTITY_EXISTS');
      await recordRow(app.db, ctx, mutation, outcome);
    }

    return {
      clientMutationId: mutation.clientMutationId,
      status: outcome.status,
      revision: outcome.revision ?? null,
      errorCode: outcome.errorCode ?? null,
      replayed: false,
      ...(outcome.discardedFields?.length > 0 ? { discardedFields: outcome.discardedFields } : {}),
    };
  }

  app.post(
    '/sync/push',
    {
      ...auth,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['clientId', 'workspaceId', 'baseRevision', 'mutations'],
          properties: {
            clientId: ULID_PARAM,
            workspaceId: ULID_PARAM,
            baseRevision: { type: 'integer', minimum: 0 },
            mutations: {
              type: 'array',
              minItems: 1,
              maxItems: MAX_PUSH_MUTATIONS,
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['clientMutationId', 'entityType', 'entityId', 'operation'],
                properties: {
                  clientMutationId: ULID_PARAM,
                  entityType: { type: 'string', minLength: 1, maxLength: 64 },
                  entityId: ULID_PARAM,
                  operation: { type: 'string', enum: ['create', 'update', 'delete'] },
                  patch: { type: 'object' },
                  localUpdatedAt: { type: 'string', format: 'date-time' },
                },
              },
            },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              workspaceId: { type: 'string' },
              toRevision: { type: 'integer' },
              results: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    clientMutationId: { type: 'string' },
                    status: { type: 'string', enum: ['applied', 'conflict', 'rejected'] },
                    revision: { type: ['integer', 'null'] },
                    errorCode: { type: ['string', 'null'] },
                    replayed: { type: 'boolean' },
                    discardedFields: { type: 'array', items: { type: 'string' } },
                  },
                },
              },
            },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { clientId, workspaceId, baseRevision, mutations } = request.body;
      const member = await app.requireWorkspaceMember(request, workspaceId);
      const ctx = {
        clientId,
        workspaceId,
        baseRevision,
        userId: request.user.id,
        role: member.role,
      };

      // Sequential on purpose: the outbox is ordered (create-before-update),
      // and per-workspace writers serialize on the revision row lock anyway.
      const results = [];
      for (const mutation of mutations) {
        results.push(await processMutation(ctx, mutation));
      }

      const ws = await app.db('workspaces').where({ id: workspaceId }).first('revision');
      return { workspaceId, toRevision: Number(ws.revision), results };
    },
  );
}
