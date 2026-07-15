/**
 * The user's OWN calendar events → rows we can show (OPH-082, ADR-0008).
 *
 * Pure, like `desiredEventForTask` (outbound) and `reconcileProviderEvent`
 * (inbound) before it: every rule about what we keep, and why, is decided here
 * and unit-testable without Google or a database. The worker only executes.
 *
 * These are NOT our events. We never write them back, so this file has exactly
 * one job: decide "store this / make sure it isn't stored", and say why.
 */

import { zonedWallTimeToUtc } from './time.js';

/**
 * How much calendar to keep. `timeMin`/`timeMax` cannot be combined with a
 * `syncToken` (Google's events.list contract), so a sync always transfers the
 * whole collection — the window is ours to apply when STORING, or a decade of
 * history would land in MySQL and on every phone.
 */
export const EXTERNAL_EVENT_WINDOW = { backDays: 31, forwardDays: 400 };

const decision = (action, reason, values) => ({ action, reason, ...(values ? { values } : {}) });

/** All-day boundaries are calendar dates: anchor them to the user's timezone. */
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
  // Google's all-day `end.date` is EXCLUSIVE — a one-day event ends at
  // midnight the NEXT day, which is exactly the block a grid should draw.
  return side.date ? midnightIn(side.date, timeZone) : null;
}

/**
 * @param {object} event Google event resource (may be `status: cancelled`)
 * @param {{ timeZone: string, now?: Date, window?: {backDays: number, forwardDays: number} }} ctx
 * @returns {{ action: 'store'|'drop'|'skip', reason: string, values?: object }}
 *   `store` — upsert it. `drop` — make sure it is not stored (it was cancelled,
 *   or it left the window). `skip` — never ours to touch; don't even look.
 */
export function deriveExternalEvent(event, { timeZone, now = new Date(), window } = {}) {
  // Ours. It is already a task — showing it here too would duplicate every
  // mirrored block on the one screen this feature exists for (ADR-0008 §5).
  if (event?.extendedProperties?.private?.alliswell_task_id) {
    return decision('skip', 'ours');
  }
  if (event?.status === 'cancelled') return decision('drop', 'cancelled');

  const start = edge(event?.start, timeZone);
  const end = edge(event?.end, timeZone);
  // A grid needs two instants. Anything else (a malformed event, a recurrence
  // master that slipped through) is not ours to guess at.
  if (!start || !end || end < start) return decision('skip', 'unmappable-times');

  const { backDays, forwardDays } = window ?? EXTERNAL_EVENT_WINDOW;
  const from = now.getTime() - backDays * 86400_000;
  const to = now.getTime() + forwardDays * 86400_000;
  // `drop`, not `skip`: an event that MOVED out of the window must stop being
  // shown, and this pass is the only notification we get about it.
  if (end.getTime() < from || start.getTime() > to) {
    return decision('drop', 'out-of-window');
  }

  const isAllDay = Boolean(event.start?.date);
  return decision('store', 'store', {
    summary: event.summary ? String(event.summary).slice(0, 500) : null,
    location: event.location ? String(event.location).slice(0, 500) : null,
    starts_at: start,
    ends_at: end,
    is_all_day: isAllDay,
    // `transparent` = on the calendar, but not actually busy (§ Google's
    // free/busy semantics). All-day events are transparent by default.
    is_busy: event.transparency !== 'transparent',
    html_link: event.htmlLink ? String(event.htmlLink).slice(0, 1000) : null,
    etag: event.etag ?? null,
    provider_updated_at: event.updated ? new Date(event.updated) : null,
  });
}
