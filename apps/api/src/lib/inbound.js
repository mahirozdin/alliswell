/**
 * Provider event → local decision (OPH-075/076, BLUEPRINT §7.2 steps 9-10).
 *
 * Pure, like `desiredEventForTask` on the outbound side: the entire two-way
 * conflict matrix is decided here, so it is unit-testable without Google or a
 * database. The worker (`queue/calendar-sync-job.js`) only executes.
 *
 * The invariants this file encodes:
 *
 * - **Echo suppression is etag-based.** Every outbound write stores the etag
 *   Google answered with. An event whose etag still matches is our own change
 *   coming back through the sync feed — never a "provider change". This is
 *   what stops mirror ⇄ sync from looping.
 * - **A calendar block means scheduling.** When the user drags our event, we
 *   write `scheduled_start_at`/`scheduled_end_at` — never `due_at`. Moving a
 *   block says "I'll do it then", not "the deadline moved", and §7.1 derives
 *   from `scheduled_*` first, so the event stays where the user dropped it.
 * - **Local state is canonical** (AGENTS.md §6). Where the two disagree and
 *   both moved, §6.5 last-write-wins on the wall clock decides, and the link
 *   keeps a `conflict_status` record of it.
 */

import { desiredEventForTask } from './mirror.js';
import { zonedWallTimeToUtc } from './time.js';

/** The `calendar_event_links.conflict_status` enum (OPH-015 migration). */
export const CONFLICT = {
  NONE: 'none',
  BOTH_CHANGED: 'local_changed_provider_changed',
  PROVIDER_DELETED: 'provider_deleted_local_exists',
  LOCAL_DELETED: 'local_deleted_provider_exists',
  TIME: 'time_conflict',
};

const ms = (value) => (value == null ? 0 : new Date(value).getTime());
const sameInstant = (a, b) => ms(a) === ms(b);

/** All-day boundaries are calendar dates — anchor them to the task's timezone. */
function midnightIn(dateString, timeZone) {
  const [year, month, day] = String(dateString).split('-').map(Number);
  if (!year || !month || !day) return null;
  return zonedWallTimeToUtc({ year, month, day }, timeZone);
}

function edge(side, timeZone) {
  if (!side) return null;
  if (side.dateTime) {
    const at = new Date(side.dateTime);
    return Number.isNaN(at.getTime()) ? null : at;
  }
  // All-day: `end.date` is EXCLUSIVE in Google's model, so a single all-day
  // event maps to a clean 00:00 → 00:00-next-day block.
  return side.date ? midnightIn(side.date, timeZone) : null;
}

/**
 * The task-shaped time window of a provider event, or null when it cannot be
 * one: a recurring series (many instants, one task) or unusable boundaries.
 */
function eventWindow(event, timeZone) {
  if (Array.isArray(event.recurrence) && event.recurrence.length > 0) return null;
  const start = edge(event.start, timeZone);
  const end = edge(event.end, timeZone);
  if (!start || !end || end <= start) return null;
  return { start, end };
}

const outcome = (decision, extra = {}) => ({ decision, ...extra });

/**
 * Decides what one event from the sync feed means for us.
 *
 * @param {{
 *   event: object,          // Google event resource (may be `status: cancelled`)
 *   link: object|null,      // calendar_event_links row for (account, event id)
 *   task: object|null,      // the task it maps to — by link, or by extended property
 *   alreadyLinked?: boolean // that task already has a link on this account
 * }} input
 * @returns {{
 *   decision: 'ignore'|'adopt'|'touch'|'apply'|'push'|'remove-remote'|'stop-mirror'|'flag'|'drop-link',
 *   conflictStatus?: string, // what the link should carry afterwards (absent = leave alone)
 *   taskPatch?: object,      // task columns to write (apply / stop-mirror)
 *   reason: string           // for the log line and the tests
 * }}
 */
export function reconcileProviderEvent({ event, link, task, alreadyLinked = false }) {
  const cancelled = event.status === 'cancelled';

  if (!link) {
    // §7.2 step 9: an app-generated event with no mapping row (a crash between
    // insert and link, a reconnected account) is ADOPTED, never duplicated.
    // Cancelled ones are the debris of our own deletes — the link went first.
    if (cancelled || !task || alreadyLinked) return outcome('ignore', { reason: 'unlinked' });
    if (!desiredEventForTask(task))
      return outcome('ignore', { reason: 'unlinked-task-wants-none' });
    return outcome('adopt', {
      conflictStatus: CONFLICT.NONE,
      reason: 'adopt-by-extended-property',
    });
  }

  const wanted = task ? desiredEventForTask(task) : null;

  if (cancelled) {
    // Our own deletes drop the link row first, so a surviving link means the
    // USER deleted the event. Recreating it would fight them and resurrect it
    // forever; deleting their task would be worse. So: keep the task, stop
    // mirroring it, and leave the flagged link as the record of why.
    if (!wanted) return outcome('drop-link', { reason: 'converged-delete' });
    return outcome('stop-mirror', {
      conflictStatus: CONFLICT.PROVIDER_DELETED,
      taskPatch: { calendar_mirror_enabled: false },
      reason: 'provider-deleted',
    });
  }

  if (link.etag && event.etag && event.etag === link.etag) {
    return outcome('touch', { reason: 'echo' });
  }

  // Past here the etag is foreign: someone else really did write the event.
  if (!wanted) {
    // The task stopped earning an event (completed/archived/deleted/opted out)
    // while the calendar entry lives on and just changed — our delete never
    // landed. Local state is canonical, so the event goes.
    return outcome('remove-remote', {
      conflictStatus: CONFLICT.LOCAL_DELETED,
      reason: 'local-deleted-provider-alive',
    });
  }

  const window = eventWindow(event, task.timezone);
  if (!window) {
    // A repeating series, or boundaries we cannot express as one task block.
    // Don't guess and don't fight: flag it and leave the calendar untouched.
    return outcome('flag', { conflictStatus: CONFLICT.TIME, reason: 'unmappable-times' });
  }

  // Compare against what §7.1 DERIVES, not against the raw columns: an event
  // built from `due_at` sits at a time no column holds, so a cosmetic edit
  // (colour, description) must not be mistaken for a move and pin the task to
  // a schedule it never had.
  const derived = { start: new Date(wanted.start.dateTime), end: new Date(wanted.end.dateTime) };
  if (sameInstant(derived.start, window.start) && sameInstant(derived.end, window.end)) {
    return outcome('touch', {
      conflictStatus: CONFLICT.NONE,
      reason: 'provider-changed-nothing-we-map',
    });
  }

  const taskPatch = { scheduled_start_at: window.start, scheduled_end_at: window.end };
  const localChanged =
    link.last_local_updated_at != null && ms(task.updated_at) > ms(link.last_local_updated_at);

  if (!localChanged) {
    return outcome('apply', { conflictStatus: CONFLICT.NONE, taskPatch, reason: 'provider-only' });
  }

  // Both sides moved since the last reconcile → §6.5 last-write-wins on the
  // wall clock. The loser's change is dropped, so the link keeps the flag: it
  // is the only trace that something was overwritten.
  if (ms(event.updated) > ms(task.updated_at)) {
    return outcome('apply', {
      conflictStatus: CONFLICT.BOTH_CHANGED,
      taskPatch,
      reason: 'both-changed-provider-newer',
    });
  }
  return outcome('push', {
    conflictStatus: CONFLICT.BOTH_CHANGED,
    reason: 'both-changed-local-newer',
  });
}
