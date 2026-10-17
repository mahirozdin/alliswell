import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import {
  MAX_OCCURRENCES,
  WEEKDAYS,
  expandOccurrences,
  isCompletionRule,
  lastDayOfMonth,
  nextAfterCompletion,
  parseDay,
  validateRule,
} from '../lib/recurrence.js';
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
  // Optional: when the client omits it the SERVER fills it from the user's own
  // timezone (routes/task-series.js, sync's guard). A client guessing an IANA
  // name from a device offset would write "+03" into a column that means
  // "Europe/Istanbul" — the app has no tz database of its own to ask.
  if (timezone != null && (typeof timezone !== 'string' || timezone.length > 64)) {
    return problem('TASK_SERIES_TEMPLATE_INVALID', 'timezone is invalid');
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
  if (isCompletionSeries(series)) return materializeCompletionHead(trx, { workspaceId, series });

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
    const dueAt = atWallTime(day, anchor, series.timezone);
    await insertOccurrence(trx, {
      workspaceId,
      series,
      day,
      columns: templateColumns(series, template, dueAt),
      tagIds: template.tagIds,
    });
    created.push(day);
  }

  return { created: created.length, days: created };
}

/** `day` at the wall-clock hour/minute of `parts`, on the series' calendar. */
function atWallTime(day, parts, timeZone) {
  const { year, month, day: dayOfMonth } = parseDay(day);
  return zonedWallTimeToUtc(
    { year, month, day: dayOfMonth, hour: parts.hour, minute: parts.minute },
    timeZone,
  );
}

/** The columns a template stamps onto an occurrence due at `dueAt`. */
function templateColumns(series, template, dueAt) {
  return {
    project_id: template.projectId ?? null,
    title: template.title,
    description: template.description ?? null,
    status: 'open',
    priority: template.priority ?? 'none',
    color_rgb: template.colorRgb ?? null,
    due_at: dueAt,
    remind_at:
      template.remindMinutesBefore == null
        ? null
        : new Date(dueAt.getTime() - template.remindMinutesBefore * 60000),
    timezone: series.timezone,
    is_urgent: Boolean(template.isUrgent),
    requires_acknowledgement: Boolean(template.requiresAcknowledgement),
    estimated_minutes: template.estimatedMinutes ?? null,
    created_by: series.created_by ?? null,
    updated_by: series.created_by ?? null,
  };
}

/**
 * Inserts ONE occurrence row with the bookkeeping every task write owes: the
 * revision, its tags, and the alarm reconcile. The calendar materializer and
 * the after-completion spawn (OPH-375) both come through here, so a spawned
 * occurrence is mirrored, pulled and alarmed exactly like a materialized one.
 *
 * @returns {Promise<object>} the inserted row
 */
async function insertOccurrence(trx, { workspaceId, series, day, columns, tagIds }) {
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
    ...columns,
    series_id: series.id,
    occurrence_date: day,
    revision,
  });

  if (Array.isArray(tagIds) && tagIds.length > 0) {
    await trx('task_tags').insert(tagIds.map((tagId) => ({ task_id: id, tag_id: tagId })));
  }

  const fresh = await trx('tasks').where({ id }).first();
  await reconcileTaskReminder(trx, { workspaceId, task: fresh });
  return fresh;
}

// ── After completion (OPH-375, ADR-0056) ─────────────────────────────────────

/** Statuses that are not "the open one" of an after-completion series. */
const FINISHED_STATUSES = ['completed', 'cancelled', 'archived'];

/** True when a series row counts from completions rather than the calendar. */
export function isCompletionSeries(series) {
  return isCompletionRule(parseJsonColumn(series?.rule));
}

/** Whole days from `a` to `b` (`YYYY-MM-DD` each). */
function daysBetween(a, b) {
  const pa = parseDay(a);
  const pb = parseDay(b);
  return Math.round(
    (Date.UTC(pb.year, pb.month - 1, pb.day) - Date.UTC(pa.year, pa.month - 1, pa.day)) / 86400000,
  );
}

/**
 * The slot an after-completion occurrence takes: its own due day when free,
 * otherwise the day after the series' last slot. A daily task completed a day
 * EARLY is due on the day the completed one already holds, and the unique
 * index `(series_id, occurrence_date)` must not turn that into an error —
 * `occurrence_date` is the slot, `due_at` is the truth (ADR-0020).
 */
async function freeSlot(trx, { series, day }) {
  const taken = await trx('tasks').where({ series_id: series.id, occurrence_date: day }).first();
  if (!taken) return day;
  const rows = await trx('tasks').where({ series_id: series.id }).select('occurrence_date');
  const last = rows
    .map((row) => occurrenceDayOf(row.occurrence_date))
    .filter(Boolean)
    .reduce((a, b) => laterDay(a, b), day);
  return addWallDays(last, 1);
}

/**
 * An after-completion series has no window: its first occurrence is the task
 * the user turned Repeat on (adopted) or, without one, a row on the anchor.
 * Once ANY row of the series exists — even a deleted one — this creates
 * nothing, so the daily sweep can never resurrect a head the user removed.
 */
async function materializeCompletionHead(trx, { workspaceId, series }) {
  const any = await trx('tasks').where({ series_id: series.id }).first();
  if (any) return { created: 0, days: [] };
  const rule = parseJsonColumn(series.rule);
  const day = wallDay(series.anchor_at, series.timezone);
  if (expandOccurrences(rule, { anchor: day }).length === 0) return { created: 0, days: [] };
  const template = parseJsonColumn(series.template) ?? {};
  const anchor = wallClockParts(new Date(series.anchor_at), series.timezone);
  await insertOccurrence(trx, {
    workspaceId,
    series,
    day,
    columns: templateColumns(series, template, atWallTime(day, anchor, series.timezone)),
    tagIds: template.tagIds,
  });
  return { created: 1, days: [day] };
}

/**
 * Completing an occurrence of an after-completion series creates the next one
 * (OPH-375, ADR-0056). Called by every door that completes a task — REST PATCH
 * and /complete, MCP, the sync push — inside the completing transaction.
 *
 * - The next day is the completion day on the series' wall clock plus the
 *   interval; late or early, it counts from when the user actually did it.
 * - The time of day is the completed row's own (its `due_at`), applied with
 *   `zonedWallTimeToUtc`, so 09:00 stays 09:00 across a DST change.
 * - "When" keeps its day gap to the due date, and the alarm keeps its offset.
 * - Everything else is COPIED from the completed row (title, notes, project,
 *   priority, colour, urgency, duration, tags): an edit to the open one
 *   carries forward, which is why the app asks no scope question here.
 *
 * Returns null — creating nothing — when the task is not part of a live
 * after-completion series, when this completion already has a successor (a
 * second device, a retried push), when a later occurrence is still open, or
 * when the rule's end has been reached.
 *
 * @returns {Promise<object|null>} the new row, or null
 */
export async function spawnAfterCompletion(trx, { workspaceId, task, userId = null }) {
  if (!task?.series_id || !task.completed_at || task.deleted_at != null) return null;
  const series = await trx('task_series')
    .where({ id: task.series_id, workspace_id: workspaceId })
    .whereNull('deleted_at')
    .first();
  if (!series || !isCompletionSeries(series)) return null;

  const successor = await trx('tasks')
    .where({ spawned_from_task_id: task.id })
    .whereNull('deleted_at')
    .first();
  if (successor) return null;

  // One open occurrence at a time: completing an OLD one while a newer one is
  // still waiting must not fork the series in two.
  const slotDay = occurrenceDayOf(task.occurrence_date);
  let laterOpen = trx('tasks')
    .where({ workspace_id: workspaceId, series_id: series.id })
    .whereNull('deleted_at')
    .whereNotIn('status', FINISHED_STATUSES)
    .whereNot('id', task.id);
  if (slotDay) laterOpen = laterOpen.where('occurrence_date', '>', slotDay);
  if (await laterOpen.first()) return null;

  const rule = parseJsonColumn(series.rule);
  const tz = series.timezone;
  const live = await trx('tasks')
    .where({ series_id: series.id })
    .whereNull('deleted_at')
    .select('id');
  const day = nextAfterCompletion(rule, {
    completedDay: wallDay(task.completed_at, tz),
    emitted: live.length,
  });
  if (!day) return null;

  const template = parseJsonColumn(series.template) ?? {};
  const wall = (instant) => wallClockParts(new Date(instant), tz);
  const ms = (instant) => new Date(instant).getTime();
  let dueAt = null;
  let startAt = null;
  let remindAt = null;
  if (task.due_at) {
    dueAt = atWallTime(day, wall(task.due_at), tz);
    if (task.start_at) {
      const gap = daysBetween(wallDay(task.start_at, tz), wallDay(task.due_at, tz));
      startAt = atWallTime(addWallDays(day, -gap), wall(task.start_at), tz);
    }
    if (task.remind_at) {
      remindAt = new Date(dueAt.getTime() - (ms(task.due_at) - ms(task.remind_at)));
    } else if (template.remindMinutesBefore != null) {
      remindAt = new Date(dueAt.getTime() - template.remindMinutesBefore * 60000);
    }
  } else if (task.start_at) {
    // A "When"-only task moves its day and keeps no deadline it never had.
    startAt = atWallTime(day, wall(task.start_at), tz);
    if (task.remind_at) {
      remindAt = new Date(startAt.getTime() - (ms(task.start_at) - ms(task.remind_at)));
    }
  } else {
    dueAt = atWallTime(day, wall(series.anchor_at), tz);
    if (template.remindMinutesBefore != null) {
      remindAt = new Date(dueAt.getTime() - template.remindMinutesBefore * 60000);
    }
  }

  const tags = await trx('task_tags').where({ task_id: task.id }).select('tag_id');
  const actor = userId ?? task.updated_by ?? series.created_by ?? null;
  return insertOccurrence(trx, {
    workspaceId,
    series,
    day: await freeSlot(trx, { series, day }),
    columns: {
      project_id: task.project_id ?? null,
      title: task.title,
      description: task.description ?? null,
      status: 'open',
      priority: task.priority ?? 'none',
      color_rgb: task.color_rgb ?? null,
      due_at: dueAt,
      start_at: startAt,
      remind_at: remindAt,
      timezone: task.timezone ?? tz,
      is_urgent: Boolean(task.is_urgent),
      requires_acknowledgement: Boolean(task.requires_acknowledgement),
      estimated_minutes: task.estimated_minutes ?? null,
      spawned_from_task_id: task.id,
      created_by: actor,
      updated_by: actor,
    },
    tagIds: [...new Set(tags.map((t) => t.tag_id))],
  });
}

/**
 * Uncompleting withdraws the occurrence that completion created — while it is
 * still unfinished; a successor the user has already completed is history.
 *
 * The tombstone gives up its slot (`occurrence_date = NULL`): MySQL's unique
 * index skips NULLs, so completing again can take the same day without
 * colliding with the withdrawn row.
 *
 * @returns {Promise<number>} rows withdrawn
 */
export async function retractSpawn(trx, { workspaceId, task, userId = null }) {
  const rows = await trx('tasks')
    .where({ workspace_id: workspaceId, spawned_from_task_id: task.id })
    .whereNull('deleted_at')
    .whereNotIn('status', ['completed', 'cancelled'])
    .select();
  for (const row of rows) {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: row.id,
      operation: 'delete',
    });
    await trx('tasks')
      .where({ id: row.id })
      .update({
        deleted_at: new Date(),
        occurrence_date: null,
        revision,
        updated_by: userId ?? row.updated_by ?? null,
        updated_at: new Date(),
      });
    const fresh = await trx('tasks').where({ id: row.id }).first();
    await reconcileTaskReminder(trx, { workspaceId, task: fresh });
  }
  return rows.length;
}

/**
 * The status hook every completing door calls after it wrote the row: a task
 * becoming `completed` may spawn its successor, a task leaving `completed`
 * withdraws it. Tasks outside a series return at once.
 *
 * @returns {Promise<{spawned: object|null, retracted: number}>}
 */
export async function onTaskStatusChange(trx, { workspaceId, before, after, userId = null }) {
  const none = { spawned: null, retracted: 0 };
  if (!after?.series_id || !before) return none;
  if (before.status !== 'completed' && after.status === 'completed') {
    return {
      ...none,
      spawned: await spawnAfterCompletion(trx, { workspaceId, task: after, userId }),
    };
  }
  if (before.status === 'completed' && after.status !== 'completed') {
    return { ...none, retracted: await retractSpawn(trx, { workspaceId, task: after, userId }) };
  }
  return none;
}

/**
 * A rule edit on an after-completion series (or a switch to one) keeps ONE
 * open occurrence: the earliest open one stays as the head, any other open
 * one from today on goes. With none left at all, a head is created on the
 * anchor day or today, whichever is later — unless the rule has ended or the
 * user deleted the head (the series then stays stopped).
 */
async function rebuildCompletionHead(trx, { workspaceId, series, now }) {
  const fromDay = materializationWindow(series, now).from;
  const open = await trx('tasks')
    .where({ workspace_id: workspaceId, series_id: series.id })
    .whereNull('deleted_at')
    .whereNotIn('status', FINISHED_STATUSES)
    .orderBy('occurrence_date', 'asc')
    .select();

  const extras = open
    .slice(1)
    .filter((row) => (occurrenceDayOf(row.occurrence_date) ?? fromDay) >= fromDay);
  const removed = await retireOccurrences(trx, { workspaceId, rows: extras });
  if (open.length > 0) return { removed, created: 0 };

  // A deleted head stopped the series: its tombstone still holds the latest
  // slot, exactly as a deleted calendar occurrence keeps its day. A rule or
  // title edit must not bring it back as a fresh task due today (ADR-0056 §8).
  const latest = await trx('tasks')
    .where({ series_id: series.id })
    .whereNotNull('occurrence_date')
    .orderBy('occurrence_date', 'desc')
    .first();
  if (latest?.deleted_at != null) return { removed, created: 0 };

  const rule = parseJsonColumn(series.rule);
  const live = await trx('tasks')
    .where({ series_id: series.id })
    .whereNull('deleted_at')
    .select('id');
  if (rule.end?.type === 'count' && live.length >= rule.end.count) return { removed, created: 0 };
  if (rule.end?.type === 'until' && fromDay > rule.end.until) return { removed, created: 0 };

  const template = parseJsonColumn(series.template) ?? {};
  const anchor = wallClockParts(new Date(series.anchor_at), series.timezone);
  await insertOccurrence(trx, {
    workspaceId,
    series,
    day: await freeSlot(trx, { series, day: fromDay }),
    columns: templateColumns(series, template, atWallTime(fromDay, anchor, series.timezone)),
    tagIds: template.tagIds,
  });
  return { removed, created: 1 };
}

const SERIES_CODE_STATUS = {
  TASK_SERIES_RULE_INVALID: 'badRequest',
  TASK_SERIES_TEMPLATE_INVALID: 'badRequest',
  TASK_SERIES_TOO_DENSE: 'unprocessableEntity',
};
const SERIES_CODE_MESSAGE = {
  TASK_SERIES_TOO_DENSE: 'This repeat rule would create too many tasks',
};

/** The HTTP error a series refusal becomes, on every door that creates one. */
export function seriesError(app, code, message) {
  const status = SERIES_CODE_STATUS[code] ?? 'badRequest';
  return coded(
    app.httpErrors[status](message ?? SERIES_CODE_MESSAGE[code] ?? 'Invalid series'),
    code,
  );
}

/** Refuses an impossible rule BEFORE any row is written (ADR-0020 §4). */
export function assertMaterializable(app, series, now) {
  try {
    return plannedDays(series, now);
  } catch (err) {
    throw seriesError(app, err.code ?? 'TASK_SERIES_RULE_INVALID', err.message);
  }
}

/**
 * Creates a series, adopts `fromTaskId` when its day is part of the pattern,
 * and materializes the window — ONE transaction (the caller's, when `trx` is
 * given). Extracted from the REST route in OPH-371 so the Todoist/TickTick
 * importer creates a repeating task through the same door.
 *
 * `timezone` is required here: the route fills it from the user's profile.
 *
 * @returns {Promise<{stored: object, created: number, adoptedTaskId: string|null}>}
 */
export async function createTaskSeries(
  app,
  {
    workspaceId,
    userId,
    rule,
    template,
    timezone,
    anchorAt,
    fromTaskId = null,
    trx: outer = null,
    now = new Date(),
  },
) {
  const problem = validateSeriesInput({ rule, template, timezone, anchorAt });
  if (problem) throw seriesError(app, problem.code, problem.message);
  const normalized = normalizeTemplate(template);

  const id = newId();
  const series = {
    id,
    workspace_id: workspaceId,
    rule,
    template: normalized,
    timezone,
    anchor_at: new Date(anchorAt),
    created_by: userId,
  };
  assertMaterializable(app, series, now);

  let created = 0;
  let adoptedTaskId = null;
  let stored;
  const work = async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task_series',
      entityId: id,
      operation: 'create',
    });
    await trx('task_series').insert({
      ...series,
      rule: JSON.stringify(rule),
      template: JSON.stringify(normalized),
      revision,
    });
    stored = await trx('task_series').where({ id }).first();

    if (fromTaskId) {
      adoptedTaskId = await adoptTaskIntoSeries(trx, {
        workspaceId,
        series: stored,
        taskId: fromTaskId,
        now,
      });
    }
    ({ created } = await materializeSeries(trx, { workspaceId, series: stored, now }));
  };
  await (outer ? work(outer) : app.db.transaction(work));
  return { stored, created, adoptedTaskId };
}

/**
 * Replaces a series' rule / template / timezone / anchor and rebuilds its
 * future in one transaction. Extracted from the REST PATCH (OPH-375) so MCP's
 * `set_task_repeat` edits a repeat through the same door the API key does.
 *
 * @returns {Promise<{stored: object, created: number, removed: number}>}
 */
export async function updateTaskSeries(app, { row, body, now = new Date() }) {
  const merged = {
    rule: body.rule ?? parseJsonColumn(row.rule),
    template: body.template ?? parseJsonColumn(row.template) ?? {},
    timezone: body.timezone ?? row.timezone,
    anchorAt: body.anchorAt ?? row.anchor_at,
  };
  const problem = validateSeriesInput(merged);
  if (problem) throw seriesError(app, problem.code, problem.message);
  const template = normalizeTemplate(merged.template);
  const anchorAt = new Date(merged.anchorAt);

  const next = {
    ...row,
    rule: merged.rule,
    template,
    timezone: merged.timezone,
    anchor_at: anchorAt,
  };
  assertMaterializable(app, next, now);

  let result = { created: 0, removed: 0 };
  let stored;
  await app.db.transaction(async (trx) => {
    const revision = await recordSyncWrite(trx, {
      workspaceId: row.workspace_id,
      entityType: 'task_series',
      entityId: row.id,
      operation: 'update',
      changedFields: Object.keys(body),
    });
    await trx('task_series')
      .where({ id: row.id })
      .update({
        rule: JSON.stringify(merged.rule),
        template: JSON.stringify(template),
        timezone: merged.timezone,
        anchor_at: anchorAt,
        revision,
        updated_at: new Date(),
      });
    stored = await trx('task_series').where({ id: row.id }).first();
    result = await rebuildFuture(trx, {
      workspaceId: row.workspace_id,
      series: stored,
      previous: row,
      now,
    });
  });
  return { stored, ...result };
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

  // OPH-375: an after-completion series has no pattern for the day to match —
  // the task the user turned Repeat on IS its first occurrence, whatever day.
  const completion = isCompletionSeries(series);
  const day = wallDay(
    (completion ? (task.due_at ?? task.start_at) : task.due_at) ?? task.created_at,
    series.timezone,
  );
  if (!completion && !plannedDays(series, now).includes(day)) return null;

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

  // Repeat turned on for a task that is already done: that completion counts.
  if (completion && task.status === 'completed' && task.completed_at) {
    const adopted = await trx('tasks').where({ id: task.id }).first();
    await spawnAfterCompletion(trx, { workspaceId, task: adopted });
  }
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

async function writeOccurrence(trx, { workspaceId, row, patch, userId, changedFields = null }) {
  const revision = await recordSyncWrite(trx, {
    workspaceId,
    entityType: 'task',
    entityId: row.id,
    operation: 'update',
    changedFields: changedFields ?? Object.keys(patch),
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
 * Re-points a rule's day selector at `day` (feedback round 13 #6).
 *
 * The owner moved a "13th of every month" task to another date and the rule
 * kept saying the 13th — technically what §25 R8 promised ("days come from the
 * rule"), and wrong in the only way that matters: they had just told us which
 * day they wanted. So a date edit with a scope WIDER than "just this one" now
 * moves the pattern too.
 *
 * Only unambiguous rules follow. A rule that names several days, or the
 * "first Monday after the 22nd" window, has no single day to move — those keep
 * their pattern and only take the new time of day, as before.
 *
 * @returns {object|null} the rewritten rule, or null when it must stay put.
 */
export function ruleFollowingDay(rule, day) {
  const target = parseDay(day);
  if (!target) return null;
  const weekday =
    WEEKDAYS[(new Date(Date.UTC(target.year, target.month - 1, target.day)).getUTCDay() + 6) % 7];
  const monthDays = rule.byMonthDay ?? [];
  const weekdays = rule.byWeekday ?? [];

  if (rule.freq === 'daily') return null; // nothing about a day to follow
  // OPH-375: an after-completion rule names no day; the completion does.
  if (isCompletionRule(rule)) return null;
  if (monthDays.length > 1 || weekdays.length > 1) return null; // ambiguous

  if (rule.freq === 'weekly') {
    if (weekdays.length !== 1 || weekdays[0].ordinal != null) return null;
    return { ...rule, byWeekday: [{ day: weekday, ordinal: null }] };
  }

  // monthly / yearly
  const next = { ...rule };
  if (rule.freq === 'yearly' && Array.isArray(rule.byMonth) && rule.byMonth.length === 1) {
    next.byMonth = [target.month];
  }

  if (monthDays.length === 1) {
    const last = lastDayOfMonth(target.year, target.month);
    // "The last day" stays "the last day" when the user picked one.
    next.byMonthDay = monthDays[0] === -1 && target.day === last ? [-1] : [target.day];
    return next;
  }

  if (weekdays.length === 1 && weekdays[0].ordinal != null) {
    // "The 2nd Tuesday" becomes whichever ordinal weekday the new date is —
    // and "the last one" is preserved when the new date is the last of its kind.
    const nth = Math.ceil(target.day / 7);
    const isLast = target.day + 7 > lastDayOfMonth(target.year, target.month);
    next.byWeekday = [{ day: weekday, ordinal: isLast ? -1 : nth }];
    return next;
  }

  // No selector at all: the anchor decides, and the anchor is moving anyway.
  return monthDays.length === 0 && weekdays.length === 0 ? { ...rule } : null;
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
  const currentRule = parseJsonColumn(series.rule);
  // Round 13 #6: a scoped DATE edit moves the pattern too, when the pattern is
  // unambiguous enough to move. `newDay` is where the user just put this
  // occurrence; `followedRule` is null when the rule has to stay where it is.
  const newDay = patch.dueAt ? wallDay(new Date(patch.dueAt), series.timezone) : null;
  // Only a MOVE follows. Editing the hour of the same day must not churn every
  // future row's id for a pattern that did not change.
  const followedRule = newDay && newDay !== fromDay ? ruleFollowingDay(currentRule, newDay) : null;

  if (scope === 'all') {
    const rows = await movableOccurrences(trx, {
      workspaceId,
      seriesId: series.id,
      excludeId: task.id,
    });
    const completion = isCompletionRule(currentRule);
    for (const row of rows) {
      // OPH-375: an after-completion slot can differ from its due day (an
      // early completion bumps it), so the due day is what keeps its date.
      const day =
        completion && row.due_at
          ? wallDay(row.due_at, series.timezone)
          : occurrenceDayOf(row.occurrence_date);
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
      changedFields: [
        'template',
        ...(time ? ['anchor_at'] : []),
        ...(followedRule ? ['rule'] : []),
      ],
    });
    await trx('task_series')
      .where({ id: series.id })
      .update({
        template: JSON.stringify(normalizeTemplate(template)),
        ...(followedRule ? { rule: JSON.stringify(followedRule) } : {}),
        ...(time
          ? { anchor_at: timeFor(newDay ?? wallDay(series.anchor_at, series.timezone)) }
          : {}),
        revision,
        updated_at: new Date(),
      });

    if (followedRule) {
      // The pattern moved, so the days did too: the edited row takes the new
      // slot (its old one no longer exists in the plan, and leaving it there
      // would let materialization create a duplicate on the new day), every
      // other unfinished future row goes, and the window is rebuilt.
      const slotRevision = await recordSyncWrite(trx, {
        workspaceId,
        entityType: 'task',
        entityId: task.id,
        operation: 'update',
        changedFields: ['occurrence_date'],
      });
      await trx('tasks')
        .where({ id: task.id })
        .update({ occurrence_date: newDay, revision: slotRevision, updated_at: new Date() });
      const stale = await movableOccurrences(trx, {
        workspaceId,
        seriesId: series.id,
        excludeId: task.id,
      });
      await retireOccurrences(trx, { workspaceId, rows: stale });
      const fresh = await trx('task_series').where({ id: series.id }).first();
      await materializeSeries(trx, { workspaceId, series: fresh, now });
    }
    return { scope, touched: rows.length, newSeriesId: null };
  }

  // ── future: split the series in two ───────────────────────────────────────
  const rule = currentRule;
  const previousDay = addWallDays(fromDay, -1);

  // Everything from this day on, except the row the user is editing, leaves the
  // old series; the past and anything finished stay exactly where they are.
  const moving = await movableOccurrences(trx, {
    workspaceId,
    seriesId: series.id,
    fromDay,
    excludeId: task.id,
  });
  await retireOccurrences(trx, { workspaceId, rows: moving });

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
    // The half that starts here follows the date the user just picked.
    rule: JSON.stringify(followedRule ?? rule),
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
    .update({
      series_id: nextSeriesId,
      ...(followedRule ? { occurrence_date: newDay } : {}),
      revision: adoptRevision,
      updated_at: new Date(),
    });

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
 * Tombstones occurrences the SYSTEM retires (a rule edit, a scoped move, a
 * stop) and gives up their slot: `occurrence_date = NULL`, exactly as
 * `retractSpawn` does. Only a user's own delete keeps its day — that tombstone
 * is how "I removed this one" survives the sweep. A rebuild's tombstone that
 * kept its day would read as taken to `materializeSeries`, and every edit whose
 * new days overlap the old ones would leave the series with no future at all
 * (a daily series' title-only edit: removed 366, created 0).
 *
 * @returns {Promise<number>} rows tombstoned
 */
async function retireOccurrences(trx, { workspaceId, rows }) {
  for (const row of rows) {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: row.id,
      operation: 'delete',
    });
    await trx('tasks').where({ id: row.id }).update({
      deleted_at: new Date(),
      occurrence_date: null,
      revision,
      updated_at: new Date(),
    });
  }
  return rows.length;
}

/** Live, unfinished occurrences of a series from `fromDay` on. */
function futureOccurrences(trx, { workspaceId, seriesId, fromDay }) {
  return trx('tasks')
    .where({ workspace_id: workspaceId, series_id: seriesId })
    .whereNull('deleted_at')
    .whereNotIn('status', ['completed', 'cancelled'])
    .where('occurrence_date', '>=', fromDay)
    .select();
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
  const rows = await futureOccurrences(trx, { workspaceId, seriesId, fromDay });
  return retireOccurrences(trx, { workspaceId, rows });
}

/** Template-derived columns a series edit carries onto the rows it keeps. */
const RESTAMPED_COLUMNS = [
  'project_id',
  'title',
  'description',
  'priority',
  'color_rgb',
  'due_at',
  'remind_at',
  'timezone',
  'is_urgent',
  'requires_acknowledgement',
  'estimated_minutes',
];

/** Column equality across the drivers: Date vs Date, 0/1 vs boolean, null vs undefined. */
function sameColumn(a, b) {
  const norm = (v) => {
    if (v == null) return null;
    if (v instanceof Date) return v.getTime();
    if (typeof v === 'boolean') return v ? 1 : 0;
    return v;
  };
  return norm(a) === norm(b);
}

function sameTagSet(a, b) {
  const left = [...new Set(a ?? [])].sort();
  const right = [...new Set(b ?? [])].sort();
  return left.length === right.length && left.every((tag, i) => tag === right[i]);
}

/**
 * Carries a series edit onto the occurrences it keeps. A column moves only
 * where the edit changed it AND the row still holds what the old template
 * stamped there — an occurrence the user edited on its own ("only this one")
 * keeps that edit, the same way it keeps its id, its subtasks and its links.
 */
async function restampOccurrences(trx, { workspaceId, rows, before, after }) {
  if (rows.length === 0) return;
  const oldTemplate = parseJsonColumn(before.template) ?? {};
  const newTemplate = parseJsonColumn(after.template) ?? {};
  const oldClock = wallClockParts(new Date(before.anchor_at), before.timezone);
  const newClock = wallClockParts(new Date(after.anchor_at), after.timezone);

  const tagsChanged = !sameTagSet(oldTemplate.tagIds, newTemplate.tagIds);
  const tagsByTask = new Map();
  if (tagsChanged) {
    const links = await trx('task_tags')
      .whereIn(
        'task_id',
        rows.map((row) => row.id),
      )
      .select('task_id', 'tag_id');
    for (const link of links) {
      if (!tagsByTask.has(link.task_id)) tagsByTask.set(link.task_id, []);
      tagsByTask.get(link.task_id).push(link.tag_id);
    }
  }

  for (const row of rows) {
    const day = occurrenceDayOf(row.occurrence_date);
    const oldColumns = templateColumns(
      before,
      oldTemplate,
      atWallTime(day, oldClock, before.timezone),
    );
    const newColumns = templateColumns(
      after,
      newTemplate,
      atWallTime(day, newClock, after.timezone),
    );
    const patch = {};
    for (const col of RESTAMPED_COLUMNS) {
      if (sameColumn(oldColumns[col], newColumns[col])) continue;
      if (!sameColumn(row[col], oldColumns[col])) continue;
      patch[col] = newColumns[col];
    }
    const retag = tagsChanged && sameTagSet(tagsByTask.get(row.id), oldTemplate.tagIds);
    if (Object.keys(patch).length === 0 && !retag) continue;

    if (retag) {
      await trx('task_tags').where({ task_id: row.id }).delete();
      const tagIds = [...new Set(newTemplate.tagIds ?? [])];
      if (tagIds.length > 0) {
        await trx('task_tags').insert(tagIds.map((tagId) => ({ task_id: row.id, tag_id: tagId })));
      }
    }
    await writeOccurrence(trx, {
      workspaceId,
      row,
      patch,
      changedFields: [...Object.keys(patch), ...(retag ? ['tags'] : [])],
    });
  }
}

/**
 * Rebuilds the future of a series in one pass. Used by every series edit —
 * REST, MCP and the sync `task_series` update (the app's `updateRule`).
 *
 * The future occurrences the new rule still plans KEEP their rows (and so their
 * ids, subtasks, links and per-occurrence edits) and take the edit through
 * `restampOccurrences`; the ones it no longer plans are retired with their slot
 * released; the days still missing are materialized. A title-only edit
 * therefore removes nothing, and daily → weekdays removes only the weekends.
 *
 * `previous` is the series row before the edit; without it the kept rows are
 * left as they are.
 */
export async function rebuildFuture(
  trx,
  { workspaceId, series, previous = null, now = new Date() },
) {
  if (isCompletionSeries(series)) return rebuildCompletionHead(trx, { workspaceId, series, now });
  const fromDay = materializationWindow(series, now).from;
  const planned = new Set(plannedDays(series, now));
  const rows = await futureOccurrences(trx, { workspaceId, seriesId: series.id, fromDay });
  const keep = [];
  const drop = [];
  for (const row of rows)
    (planned.has(occurrenceDayOf(row.occurrence_date)) ? keep : drop).push(row);

  const removed = await retireOccurrences(trx, { workspaceId, rows: drop });
  if (previous)
    await restampOccurrences(trx, { workspaceId, rows: keep, before: previous, after: series });
  const { created } = await materializeSeries(trx, { workspaceId, series, now });
  return { removed, created };
}

/**
 * Soft-deletes a series and its future occurrences in the caller's transaction.
 * Past occurrences keep their `series_id` — they remain part of the history.
 */
/**
 * Stopping an after-completion series (OPH-375): its open occurrence becomes
 * an ordinary task — no series, no slot, no "born from" link, so the Repeat
 * switch reads off and reopening its predecessor cannot withdraw it.
 */
async function detachOpenOccurrences(trx, { workspaceId, seriesId }) {
  const rows = await trx('tasks')
    .where({ workspace_id: workspaceId, series_id: seriesId })
    .whereNull('deleted_at')
    .whereNotIn('status', FINISHED_STATUSES)
    .select('id');
  for (const row of rows) {
    const revision = await recordSyncWrite(trx, {
      workspaceId,
      entityType: 'task',
      entityId: row.id,
      operation: 'update',
      changedFields: ['series_id', 'occurrence_date'],
    });
    await trx('tasks').where({ id: row.id }).update({
      series_id: null,
      occurrence_date: null,
      spawned_from_task_id: null,
      revision,
      updated_at: new Date(),
    });
  }
  return rows.length;
}

export async function softDeleteSeries(
  trx,
  { workspaceId, series, now = new Date(), fromDay: overrideDay = null },
) {
  // `fromDay` lets "this and future" start at the occurrence the user swiped
  // rather than at today — stopping a series from next March must not take
  // February's rows with it (OPH-208).
  const fromDay = overrideDay ?? materializationWindow(series, now).from;
  // OPH-375 (ADR-0056): an after-completion series has no future rows — its
  // one open occurrence IS the task the user is looking at. Stopping the
  // repeat keeps it as an ordinary task; only an explicit `fromDay` (the app
  // deleting that occurrence and stopping in one commit) reaches it.
  const keepHead = isCompletionSeries(series) && overrideDay == null;
  const removed = keepHead
    ? 0
    : await deleteFutureOccurrences(trx, {
        workspaceId,
        seriesId: series.id,
        fromDay,
      });
  if (keepHead) await detachOpenOccurrences(trx, { workspaceId, seriesId: series.id });
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
