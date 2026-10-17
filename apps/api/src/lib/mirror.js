import { wallClockParts, zonedWallTimeToUtc } from './time.js';

/**
 * Task → Google event derivation (OPH-072/210, BLUEPRINT §7.1, ADR-0021) —
 * pure, so the mirroring rule is unit-testable without Google or a database.
 *
 * **Round 12 turned the default inside out.** The old rule mirrored a task only
 * when a user had flipped an opt-in switch AND the task had a scheduled block,
 * a due date or an urgent reminder — so an ordinary dated task never reached
 * the calendar at all. The owner's rule replaces it: *every* task is on the
 * calendar, and it is not a setting.
 *
 * Suppression lives in `calendar_mirror_suppressed_at`, NOT in the old
 * `calendar_mirror_enabled` column: that one defaults to `false`, so reusing it
 * as "do not mirror" would suppress every task that already exists. The inbound
 * side stamps the new column when the user deletes our event in Google, and
 * honouring it is the difference between respecting a deletion and re-creating
 * it forever (ADR-0021 §3). No UI writes either column.
 *
 * A completed task KEEPS its block, marked `✓` — a calendar is the best answer
 * to "what did I actually do that week" (ADR-0021 §2). Cancelled, archived and
 * deleted tasks still mirror to nothing: that is work withdrawn, not work done.
 *
 * **OPH-372 (ADR-0053): the block is as long as the task.** A task with an
 * `estimated_minutes` gets a block of that length (capped at one day); one
 * without keeps the 30-minute slot. `start_at` ("when" — the day the task enters
 * Today) does NOT move the block: the anchor stays scheduled → due → created.
 */

/** The block length of a task with no duration. */
export const DEFAULT_SLOT_MINUTES = 30;
/** A block never outgrows the day it sits on. */
export const MAX_BLOCK_MINUTES = 1440;

/**
 * How long a task's block is: its own duration when it has one, else the
 * default slot. Zero, negative or non-integer durations count as "not set".
 *
 * @param {object|null|undefined} task
 * @returns {number} minutes
 */
export function blockMinutes(task) {
  const minutes = task?.estimated_minutes;
  if (!Number.isInteger(minutes) || minutes <= 0) return DEFAULT_SLOT_MINUTES;
  return Math.min(minutes, MAX_BLOCK_MINUTES);
}
/** Statuses that mean the work is withdrawn — the event goes. */
const GONE_STATUSES = new Set(['cancelled', 'archived']);
/** Marks a finished block without hiding what it was. */
const DONE_PREFIX = '✓ ';

/**
 * The block a task occupies, as instants. Exported for the parity fixture the
 * Apple mirror asserts too (ADR-0021 consequences, §17 D1): two mirrors that
 * disagree in front of the user is the thing that rule forbids.
 *
 * @param {object} task
 * @param {string} timeZone  the task's own zone — midnight belongs to a place
 * @returns {{start: Date, end: Date}|null}
 */
export function blockForTask(task, timeZone = task?.timezone ?? 'UTC') {
  if (!task) return null;
  const minutes = blockMinutes(task);

  // 1. A block the user dragged in their calendar wins outright (OPH-192).
  if (task.scheduled_start_at) {
    const start = new Date(task.scheduled_start_at);
    const end =
      task.scheduled_end_at && new Date(task.scheduled_end_at) > start
        ? new Date(task.scheduled_end_at)
        : // No end, or one left behind by a moved start: Google rejects a
          // backwards block outright, so fall back to the task's own length
          // rather than wedge the mirror queue on a 400 it can never retry away.
          new Date(start.getTime() + minutes * 60000);
    return { start, end };
  }

  // 2. Otherwise the task's own time — or, for an undated task, its creation
  //    day at the same hour ("ekleniş tarihi baz alınır", the owner's rule).
  const anchor = task.due_at ?? task.created_at;
  if (!anchor) return null;
  return clampToDay(new Date(anchor), timeZone, minutes);
}

/**
 * A `minutes`-long block starting at `instant` — pulled back so it cannot cross
 * midnight. A 23:59 due time with no duration therefore reads 23:29–23:59: a
 * block that spilled into tomorrow would put the task on a day it is not due.
 * A block longer than what is left of the day starts no earlier than 00:00 of
 * that day (a 24 h duration fills the day, 00:00–23:59).
 */
function clampToDay(instant, timeZone, minutes) {
  const wall = wallClockParts(instant, timeZone);
  const endOfDay = zonedWallTimeToUtc(
    { year: wall.year, month: wall.month, day: wall.day, hour: 23, minute: 59 },
    timeZone,
  );
  const naturalEnd = new Date(instant.getTime() + minutes * 60000);
  if (naturalEnd <= endOfDay) return { start: instant, end: naturalEnd };
  const startOfDay = zonedWallTimeToUtc(
    { year: wall.year, month: wall.month, day: wall.day, hour: 0, minute: 0 },
    timeZone,
  );
  const pulledBack = new Date(endOfDay.getTime() - minutes * 60000);
  return { start: pulledBack < startOfDay ? startOfDay : pulledBack, end: endOfDay };
}

/**
 * The provider-neutral half of the mirror rule (OPH-380, CALDAV.md §6): WHICH
 * block, WHICH title, gone-or-not — decided once, encoded per provider.
 * `desiredEventForTask` turns it into a Google event resource; the CalDAV
 * connector turns it into a VEVENT (`lib/caldav/ical.js`). Two encoders over
 * one decision is what keeps the two mirrors from drifting apart.
 *
 * @param {object} task
 * @returns {{
 *   taskId: string, workspaceId: string, projectId: string|null, revision: number,
 *   title: string, description: string|null, start: Date, end: Date
 * }|null} null = no event wanted
 */
export function desiredBlockForTask(task) {
  if (!task || task.deleted_at != null) return null;
  // The suppression flag (ADR-0021 §3) — set only by the inbound side, when the
  // user removed our event themselves.
  if (task.calendar_mirror_suppressed_at != null) return null;
  if (GONE_STATUSES.has(task.status)) return null;

  const block = blockForTask(task, task.timezone ?? 'UTC');
  if (!block) return null;

  const done = task.status === 'completed';
  return {
    taskId: task.id,
    workspaceId: task.workspace_id,
    projectId: task.project_id ?? null,
    revision: task.revision,
    title: `${done ? DONE_PREFIX : ''}[Task] ${task.title}`,
    description: task.description ? task.description : null,
    start: block.start,
    end: block.end,
  };
}

/** @returns {object|null} Google event resource, or null = no event wanted */
export function desiredEventForTask(task) {
  const block = desiredBlockForTask(task);
  if (!block) return null;
  return {
    summary: block.title,
    ...(block.description ? { description: block.description } : {}),
    start: { dateTime: block.start.toISOString() },
    end: { dateTime: block.end.toISOString() },
    // ADR-0003 mapping keys + §7.1 metadata. The mapping TABLE stays the
    // source of truth; these let foreign events be re-linked (OPH-073).
    extendedProperties: {
      private: {
        alliswell_task_id: block.taskId,
        alliswell_workspace_id: block.workspaceId,
        ...(block.projectId ? { alliswell_project_id: block.projectId } : {}),
        alliswell_source: 'alliswell',
        alliswell_revision: String(block.revision),
      },
    },
  };
}
