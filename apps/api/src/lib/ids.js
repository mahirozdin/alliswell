import { monotonicFactory } from 'ulid';

/**
 * Generates a new entity id. All AllisWell ids are ULIDs stored as CHAR(26).
 *
 * **Monotonic on purpose** (OPH-248). ADR-0004 says ids are "lexicographically
 * sortable by creation time", and lists across the app lean on exactly that —
 * `notes`, `tasks` and `files` all page with `orderBy('id', 'desc')`. Plain
 * `ulid()` only delivers it ACROSS milliseconds: two ids minted in the same
 * millisecond get independent random suffixes, so their relative order is a
 * coin flip.
 *
 * That is not theoretical. It made `notes.test.js`'s "lists newest-first" case
 * fail roughly one run in three — two notes created back to back landed in the
 * same millisecond and came back in either order. A flaky test was the visible
 * symptom; the real defect is that a user creating two notes quickly could see
 * them out of order, and nothing would ever explain why.
 *
 * `monotonicFactory` increments the random component instead of re-rolling it
 * when the timestamp has not moved, which makes the documented property
 * actually true.
 */
const nextId = monotonicFactory();

export function newId() {
  return nextId();
}
