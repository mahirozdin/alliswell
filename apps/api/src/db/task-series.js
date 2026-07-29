import { newId } from '../lib/ids.js';
import { expandOccurrences, MAX_OCCURRENCES, parseDay, validateRule } from '../lib/recurrence.js';
import { wallClockParts, zonedWallTimeToUtc } from '../lib/time.js';
import { reconcileTaskReminder } from './reminders.js';
import { recordSyncWrite } from './sync.js';

/**
 * Task series rules and materialization (OPH-205, ADR-0020, BLUEPRINT §12.17).
 * One implementation serves the REST routes AND the sync-push handlers, like
 * db/quick-links.js and db/folders.js.
 *
 * The engine (lib/recurrence.js) answers "which days"; this file answers "which
 * rows": it turns days into ordinary `tasks` records, inside the caller's
 * transaction, with the usual revision bookkeeping and reminder reconciliation
 * every other task write does. Nothing downstream learns what a series is.
 *
 * Writers take a `trx`; read helpers take `db` (either `app.db` or a trx).
 */

/** Rolling window: today → +12 months (ADR-0020 §4, the owner's own rule). */
export const SERIES_HORIZON_DAYS = 365;

/** Task fields a series stamps onto every occurrence it creates. */
const TEMPLATE_FIELDS = [
  'title',
  'description',
  'projectId',
  'priority',
  'colorRgb',
  'isUrgent',
  'requiresAcknowledgement',
  'estimatedMinutes',
  'remindMinutesBefore',
  'tagIds',
];

const PRIORITIES = ['none', 'low', 'medium', 'high', 'urgent'];

/** MySQL hands JSON columns back parsed; the in-memory test db hands back what it got. */
export function parseJsonColumn(value) {
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

function problem(code, message) {
  return { code, message };
}

/**
 * Semantic validation for a whole series payload — rule plus template. Pure,
 * because the sync push bypasses Ajv entirely (db/quick-links.js precedent).
 *
 * @returns {{code: string, message: string} | null}
 */
export function validateSeriesInput({ rule, template, timezone, anchorAt }) {
  const ruleProblem = validateRule(rule);
  if (ruleProblem) return ruleProblem;

  if (!template || typeof template !== 'object') {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'template must be an object');
  }
  if (typeof template.title !== 'string' || template.title.trim() === '') {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'template.title is required');
  }
  if (template.title.length > 500) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'template.title is too long');
  }
  if (template.priority != null && !PRIORITIES.includes(template.priority)) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'template.priority is invalid');
  }
  if (template.tagIds != null && !Array.isArray(template.tagIds)) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'template.tagIds must be an array');
  }
  if (
    template.remindMinutesBefore != null &&
    (!Number.isInteger(template.remindMinutesBefore) ||
      template.remindMinutesBefore < 0 ||
      template.remindMinutesBefore > 43200)
  ) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'template.remindMinutesBefore is out of range');
  }
  if (typeof timezone !== 'string' || timezone.length === 0 || timezone.length > 64) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'timezone is required');
  }
  if (Number.isNaN(new Date(anchorAt).getTime())) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'anchorAt must be a valid instant');
  }
  return null;
}

/** Keeps only the fields a template may carry, so unknown keys cannot ride in. */
export function normalizeTemplate(template) {
  const out = {};
  for (const field of TEMPLATE_FIELDS) {
    if (template[field] !== undefined) out[field] = template[field];
  }
  if (Array.isArray(out.tagIds)) out.tagIds = [...new Set(out.tagIds)];
  return out;
}

/** `YYYY-MM-DD` for an instant, read on the given timezone's wall clock. */
export function wallDay(instant, timeZone) {
  const parts = wallClockParts(new Date(instant), timeZone);
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

function addWallDays(day, delta) {
  const { year, month, day: d } = parseDay(day);
  const next = new Date(Date.UTC(year, month - 1, d + delta));
  return [
    next.getUTCFullYear(),
    String(next.getUTCMonth() + 1).padStart(2, '0'),
    String(next.getUTCDate()).padStart(2, '0'),
  ].join('-');
}

function laterDay(a, b) {
  return a > b ? a : b; // ISO dates compare correctly as strings
}

/** Live series row in this workspace, or undefined. */
export function liveSeries(db, { workspaceId, id }) {
  return db('task_series').where({ id, workspace_id: workspaceId }).whereNull('deleted_at').first();
}

/** Every live series in a workspace — what the sweep walks. */
export function listLiveSeries(db, { workspaceId }) {
  return db('task_series')
    .where({ workspace_id: workspaceId })
    .whereNull('deleted_at')
    .orderBy('id', 'asc')
    .select();
}

/**
 * The window a series materializes into right now: from today (or the anchor,
 * whichever is later — history is never back-filled) to today + 12 months.
 */
export function materializationWindow(series, now = new Date()) {
  const today = wallDay(now, series.timezone);
  const anchorDay = wallDay(series.anchor_at, series.timezone);
  return { from: laterDay(today, anchorDay), to: addWallDays(today, SERIES_HORIZON_DAYS) };
}

/**
 * Days a rule would produce in its current window, refusing anything past the
 * ceiling. The model cannot exceed 366 by construction (daily/interval 1 over a
 * leap year), so this fires only for rules that should never have been built.
 */
export function plannedDays(series, now = new Date()) {
  const rule = parseJsonColumn(series.rule);
  const { from, to } = materializationWindow(series, now);
  const days = expandOccurrences(rule, {
    anchor: wallDay(series.anchor_at, series.timezone),
    from,
    to,
    max: MAX_OCCURRENCES + 1,
  });
  if (days.length > MAX_OCCURRENCES) {
    throw Object.assign(new Error('this rule would create too many tasks'), {
      code: 'TASK_SERIES_TOO_DENSE',
    });
  }
  return days;
}

/**
 * Creates the occurrences a series is missing inside its current window.
 *
 * Idempotent by `(series_id, occurrence_date)`: a second run over the same
 * window inserts nothing, which is what lets the sweep run on every replica and
 * lets a rule edit re-enter this function safely.
 *
 * Occurrences already deleted by the user stay deleted — their row still holds
 * the slot, so "I removed this one" survives the next sweep.
 *
 * @returns {Promise<{created: number, days: string[]}>}
 */
export async function materializeSeries(trx, { workspaceId, series, now = new Date() }) {
  const days = plannedDays(series, now);
  if (days.length === 0) return { created: 0, days: [] };

  const existing = await trx('tasks')
    .where({ series_id: series.id })
    .whereIn('occurrence_date', days)
    .select('occurrence_date');
  const taken = new Set(existing.map((row) => occurrenceDayOf(row.occurrence_date)));

  const template = parseJsonColumn(series.template) ?? {};
  const anchor = wallClockParts(new Date(series.anchor_at), series.timezone);
  const created = [];

  for (const day of days) {
    if (taken.has(day)) continue;
    const { year, month, day: dayOfMonth } = parseDay(day);
    const dueAt = zonedWallTimeToUtc(
      { year, month, day: dayOfMonth, hour: anchor.hour, minute: anchor.minute },
      series.timezone,
    );
    const remindAt =
      template.remindMinutesBefore == null
        ? null
        : new Date(dueAt.getTime() - template.remindMinutesBefore * 60000);

    const id = newId();
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: id,
      operation: 'create',
    });
    await trx('tasks').insert({
      id,
      workspace_id: workspaceId,
      project_id: template.projectId ?? null,
      title: template.title,
      description: template.description ?? null,
      status: 'open',
      priority: template.priority ?? 'none',
      color_rgb: template.colorRgb ?? null,
      due_at: dueAt,
      remind_at: remindAt,
      timezone: series.timezone,
      is_urgent: Boolean(template.isUrgent),
      requires_acknowledgement: Boolean(template.requiresAcknowledgement),
      estimated_minutes: template.estimatedMinutes ?? null,
      series_id: series.id,
      occurrence_date: day,
      created_by: series.created_by ?? null,
      updated_by: series.created_by ?? null,
      revision,
    });

    if (Array.isArray(template.tagIds) && template.tagIds.length > 0) {
      await trx('task_tags').insert(
        template.tagIds.map((tagId) => ({ task_id: id, tag_id: tagId })),
      );
    }

    const fresh = await trx('tasks').where({ id }).first();
    await reconcileTaskReminder(trx, { workspaceId, task: fresh });
    created.push(day);
  }

  return { created: created.length, days: created };
}

/**
 * Turns the task the user flipped the Repeat switch on INTO the series'
 * occurrence for its own day — when that day is part of the pattern.
 *
 * Without this the materializer would create a second row beside it and the
 * user would watch their task duplicate itself the moment they asked it to
 * repeat. When the day is NOT part of the pattern the task is left alone: the
 * rule is the truth (ADR-0020's second deviation), and the dialog's preview
 * showed the real dates before the user confirmed.
 *
 * @returns {Promise<string|null>} the adopted task id, or null
 */
export async function adoptTaskIntoSeries(trx, { workspaceId, series, taskId, now = new Date() }) {
  const task = await trx('tasks')
    .where({ id: taskId, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first();
  if (!task || task.series_id != null) return null;

  const day = wallDay(task.due_at ?? task.created_at, series.timezone);
  if (!plannedDays(series, now).includes(day)) return null;

  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task',
    entityId: task.id,
    operation: 'update',
    changedFields: ['series_id', 'occurrence_date'],
  });
  await trx('tasks')
    .where({ id: task.id })
    .update({ series_id: series.id, occurrence_date: day, revision, updated_at: new Date() });
  return task.id;
}

// ── Editing scope: this / this and future / all (OPH-206) ───────────────────

export const SERIES_SCOPES = ['this', 'future', 'all'];

/**
 * Task fields a scoped edit carries to the other occurrences. Dates are absent
 * on purpose: each occurrence owns its own day, and what a scoped date edit
 * really means is "move the time of day" — handled separately below. Status and
 * completion never propagate; a sibling's history is not this edit's business.
 */
const PROPAGATED_FIELDS = {
  title: 'title',
  description: 'description',
  projectId: 'project_id',
  priority: 'priority',
  colorRgb: 'color_rgb',
  isUrgent: 'is_urgent',
  requiresAcknowledgement: 'requires_acknowledgement',
  estimatedMinutes: 'estimated_minutes',
};

/** The column patch + the template patch a scoped edit implies. */
function scopedPatches(patch) {
  const row = {};
  const template = {};
  for (const [camel, col] of Object.entries(PROPAGATED_FIELDS)) {
    if (patch[camel] === undefined) continue;
    row[col] = patch[camel];
    template[camel] = patch[camel];
  }
  return { row, template };
}

/** Live, unfinished occurrences of a series — the rows an edit may still move. */
function movableOccurrences(trx, { workspaceId, seriesId, fromDay = null, excludeId = null }) {
  let query = trx('tasks')
    .where({ workspace_id: workspaceId, series_id: seriesId })
    .whereNull('deleted_at')
    .whereNotIn('status', ['completed', 'cancelled']);
  if (fromDay) query = query.where('occurrence_date', '>=', fromDay);
  if (excludeId) query = query.whereNot('id', excludeId);
  return query.select();
}

async function writeOccurrence(trx, { workspaceId, row, patch, userId }) {
  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task',
    entityId: row.id,
    operation: 'update',
    changedFields: Object.keys(patch),
  });
  await trx('tasks')
    .where({ id: row.id })
    .update({
      ...patch,
      revision,
      updated_by: userId ?? row.updated_by ?? null,
      updated_at: new Date(),
    });
  const fresh = await trx('tasks').where({ id: row.id }).first();
  await reconcileTaskReminder(trx, { workspaceId, task: fresh });
}

/**
 * Propagates a task edit to the rest of its series (OPH-206, DESIGN §25 R8).
 *
 * The caller has already written the row the user edited; this decides what the
 * OTHER occurrences do about it.
 *
 * - `this` (and any task without a series): nothing. The row keeps its
 *   `series_id` — it is still that occurrence, and the slot it holds is what
 *   stops the next sweep from recreating the day underneath it. (The backlog
 *   called for detaching the row instead; that frees the slot and the sliding
 *   window promptly materializes a duplicate beside it. The link stays.)
 * - `future`: the series SPLITS. The old one gets an `until` at the previous
 *   day, a new series is born carrying the edit, and the edited row is adopted
 *   into it — so the task the user is looking at keeps its id instead of being
 *   replaced by a fresh row with the same title.
 * - `all`: the template changes and every live occurrence follows, past ones
 *   included (it is the same task, renamed) — but never their status or
 *   completion, which is history.
 *
 * A `dueAt` in the patch propagates as a TIME OF DAY only: the days keep coming
 * from the rule, while "make it 14:00 from now on" moves the series anchor and
 * every affected row's hour.
 *
 * @returns {Promise<{scope: string, touched: number, newSeriesId: string|null}>}
 */
export async function propagateSeriesScope(
  trx,
  { workspaceId, task, patch, scope, now = new Date(), userId = null },
) {
  const none = { scope: scope ?? 'this', touched: 0, newSeriesId: null };
  if (!task?.series_id || !scope || scope === 'this') return none;
  if (!SERIES_SCOPES.includes(scope)) return none;

  const series = await trx('task_series')
    .where({ id: task.series_id, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first();
  if (!series) return none;

  const { row: rowPatch, template: templatePatch } = scopedPatches(patch);
  const time = patch.dueAt ? wallClockParts(new Date(patch.dueAt), series.timezone) : null;
  if (Object.keys(rowPatch).length === 0 && !time) return { ...none, scope };

  const timeFor = (day) => {
    const { year, month, day: dayOfMonth } = parseDay(day);
    return zonedWallTimeToUtc(
      { year, month, day: dayOfMonth, hour: time.hour, minute: time.minute },
      series.timezone,
    );
  };

  const template = { ...(parseJsonColumn(series.template) ?? {}), ...templatePatch };
  const fromDay = occurrenceDayOf(task.occurrence_date);

  if (scope === 'all') {
    const rows = await movableOccurrences(trx, {
      workspaceId,
      seriesId: series.id,
      excludeId: task.id,
    });
    for (const row of rows) {
      const day = occurrenceDayOf(row.occurrence_date);
      await writeOccurrence(trx, {
        workspaceId,
        row,
        patch: { ...rowPatch, ...(time ? { due_at: timeFor(day) } : {}) },
        userId,
      });
    }
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task_series',
      entityId: series.id,
      operation: 'update',
      changedFields: time ? ['template', 'anchor_at'] : ['template'],
    });
    await trx('task_series')
      .where({ id: series.id })
      .update({
        template: JSON.stringify(normalizeTemplate(template)),
        ...(time ? { anchor_at: timeFor(wallDay(series.anchor_at, series.timezone)) } : {}),
        revision,
        updated_at: new Date(),
      });
    return { scope, touched: rows.length, newSeriesId: null };
  }

  // ── future: split the series in two ───────────────────────────────────────
  const rule = parseJsonColumn(series.rule);
  const previousDay = addWallDays(fromDay, -1);

  // Everything from this day on, except the row the user is editing, leaves the
  // old series; the past and anything finished stay exactly where they are.
  const moving = await movableOccurrences(trx, {
    workspaceId,
    seriesId: series.id,
    fromDay,
    excludeId: task.id,
  });
  for (const row of moving) {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: row.id,
      operation: 'delete',
    });
    await trx('tasks')
      .where({ id: row.id })
      .update({ deleted_at: new Date(), revision, updated_at: new Date() });
  }

  const oldRevision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task_series',
    entityId: series.id,
    operation: 'update',
    changedFields: ['rule'],
  });
  await trx('task_series')
    .where({ id: series.id })
    .update({
      rule: JSON.stringify({ ...rule, end: { type: 'until', until: previousDay } }),
      revision: oldRevision,
      updated_at: new Date(),
    });

  const nextSeriesId = newId();
  const anchorAt = time ? timeFor(fromDay) : (task.due_at ?? series.anchor_at);
  const newRevision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task_series',
    entityId: nextSeriesId,
    operation: 'create',
  });
  await trx('task_series').insert({
    id: nextSeriesId,
    workspace_id: workspaceId,
    rule: JSON.stringify(rule),
    template: JSON.stringify(normalizeTemplate(template)),
    timezone: series.timezone,
    anchor_at: anchorAt,
    created_by: userId ?? series.created_by ?? null,
    revision: newRevision,
  });
  const fresh = await trx('task_series').where({ id: nextSeriesId }).first();

  // The edited row joins the new series in place, keeping its id and its day.
  const adoptRevision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task',
    entityId: task.id,
    operation: 'update',
    changedFields: ['series_id'],
  });
  await trx('tasks')
    .where({ id: task.id })
    .update({ series_id: nextSeriesId, revision: adoptRevision, updated_at: new Date() });

  const { created } = await materializeSeries(trx, { workspaceId, series: fresh, now });
  return { scope, touched: moving.length + created, newSeriesId: nextSeriesId };
}

/**
 * MySQL hands a DATE column back as a Date (parsed as UTC — the connection sets
 * `timezone: 'Z'`), the in-memory test db keeps the string it was given. Both
 * become `YYYY-MM-DD`.
 */
export function occurrenceDayOf(value) {
  if (value == null) return null;
  if (typeof value === 'string') return value.slice(0, 10);
  return [
    value.getUTCFullYear(),
    String(value.getUTCMonth() + 1).padStart(2, '0'),
    String(value.getUTCDate()).padStart(2, '0'),
  ].join('-');
}

/**
 * Tombstones a series' FUTURE occurrences — everything from `fromDay` onward
 * that is not already finished. The past and anything completed stay: a
 * finished task is a historical fact (DESIGN §20 C4), and a rule change may not
 * rewrite what the user actually did.
 *
 * @returns {Promise<number>} rows tombstoned
 */
export async function deleteFutureOccurrences(trx, { workspaceId, seriesId, fromDay }) {
  const rows = await trx('tasks')
    .where({ workspace_id: workspaceId, series_id: seriesId })
    .whereNull('deleted_at')
    .whereNotIn('status', ['completed', 'cancelled'])
    .where('occurrence_date', '>=', fromDay)
    .select('id');

  for (const row of rows) {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: row.id,
      operation: 'delete',
    });
    await trx('tasks')
      .where({ id: row.id })
      .update({ deleted_at: new Date(), revision, updated_at: new Date() });
  }
  return rows.length;
}

/**
 * Rebuilds the future of a series in one pass: drop what is planned but not
 * yet done, then materialize the new rule. Used by "edit all" and by any rule
 * change (OPH-206 owns the scope question itself).
 */
export async function rebuildFuture(trx, { workspaceId, series, now = new Date() }) {
  const fromDay = materializationWindow(series, now).from;
  const removed = await deleteFutureOccurrences(trx, {
    workspaceId,
    seriesId: series.id,
    fromDay,
  });
  const { created } = await materializeSeries(trx, { workspaceId, series, now });
  return { removed, created };
}

/**
 * Soft-deletes a series and its future occurrences in the caller's transaction.
 * Past occurrences keep their `series_id` — they remain part of the history.
 */
export async function softDeleteSeries(trx, { workspaceId, series, now = new Date() }) {
  const fromDay = materializationWindow(series, now).from;
  const removed = await deleteFutureOccurrences(trx, {
    workspaceId,
    seriesId: series.id,
    fromDay,
  });
  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task_series',
    entityId: series.id,
    operation: 'delete',
  });
  await trx('task_series')
    .where({ id: series.id })
    .update({ deleted_at: new Date(), revision, updated_at: new Date() });
  return { revision, removed };
}
