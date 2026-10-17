import { parseDay } from '../recurrence.js';
import { wallClockParts, zonedWallTimeToUtc } from '../time.js';

/**
 * Dates as the two export formats write them (OPH-371, ADR-0052).
 *
 * Sources, read on 2026-10-16:
 * - TickTick's web backup (Settings › Backup & Import › Generate backup):
 *   `2026-03-26T10:00:00+0000`, sometimes `2026-02-20 10:00:00` with no
 *   offset, and all-day dates written as the zone's local midnight in UTC
 *   (`2023-03-28T22:00:00+0000` with Europe/Berlin is the 29th).
 * - Todoist's CSV (help article 360000748525 and its template): DATE is the
 *   natural-language string the user typed, in DATE_LANG — "today at 11:00",
 *   "Oct 20 2026", or a recurrence ("every Friday"). Recurrences are read by
 *   ./recurrence.js; this file reads the one-off dates.
 *
 * Nothing here guesses beyond what it can prove: an English month form, an
 * ISO form or today/tomorrow/yesterday. Anything else comes back
 * `{ unparsed: true }` and the importer keeps the text in the task's
 * description with a counted warning (DESIGN §28 M2).
 */

const pad2 = (n) => String(n).padStart(2, '0');

export function dayKey({ year, month, day }) {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

export function isValidTimeZone(tz) {
  if (typeof tz !== 'string' || tz === '' || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** `YYYY-MM-DD` for an instant on the zone's wall clock. */
export function wallDayOf(instant, tz) {
  return dayKey(wallClockParts(instant, tz));
}

function addDays(day, delta) {
  const p = parseDay(day);
  const d = new Date(Date.UTC(p.year, p.month - 1, p.day + delta));
  return dayKey({ year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() });
}

/** A real calendar date in a sane range, or null (year 0001 means "no date"). */
function validDay(year, month, day) {
  if (year < 1970 || year > 2200) return null;
  return parseDay(dayKey({ year, month, day })) ? dayKey({ year, month, day }) : null;
}

const ISO =
  /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{2})?)?$/i;

/**
 * An ISO-ish date or date-time.
 *
 * @returns {{kind:'datetime', instant: Date} | {kind:'date', day: string} | null}
 */
export function parseInstant(value, { tz }) {
  if (typeof value !== 'string') return null;
  const m = ISO.exec(value.trim());
  if (!m) return null;
  const [year, month, day] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dayStr = validDay(year, month, day);
  if (!dayStr) return null;
  if (m[4] === undefined) return { kind: 'date', day: dayStr };

  const hour = Number(m[4]);
  const minute = Number(m[5]);
  const second = Number(m[6] ?? 0);
  if (hour > 23 || minute > 59 || second > 59) return null;
  const offset = m[7];
  if (!offset) {
    return {
      kind: 'datetime',
      instant: zonedWallTimeToUtc({ year, month, day, hour, minute }, tz),
    };
  }
  let offsetMinutes = 0;
  if (offset.toUpperCase() !== 'Z') {
    const digits = offset.replace(':', '');
    const sign = digits[0] === '-' ? -1 : 1;
    offsetMinutes = sign * (Number(digits.slice(1, 3)) * 60 + Number(digits.slice(3, 5)));
  }
  const ms = Date.UTC(year, month - 1, day, hour, minute, second) - offsetMinutes * 60000;
  return { kind: 'datetime', instant: new Date(ms) };
}

const MONTHS = {
  jan: 1,
  january: 1,
  feb: 2,
  february: 2,
  mar: 3,
  march: 3,
  apr: 4,
  april: 4,
  may: 5,
  jun: 6,
  june: 6,
  jul: 7,
  july: 7,
  aug: 8,
  august: 8,
  sep: 9,
  sept: 9,
  september: 9,
  oct: 10,
  october: 10,
  nov: 11,
  november: 11,
  dec: 12,
  december: 12,
};

export function monthNumber(word) {
  return MONTHS[String(word).toLowerCase().replace(/\.$/, '')] ?? null;
}

const TIME = /^(?:(?:at|@)\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?$/;

/**
 * "11:00", "at 9", "@ 13:00", "11am", "2:30 pm". A bare number with neither a
 * colon, am/pm nor "at"/"@" is NOT a time — it is too easily a day.
 *
 * @returns {{hour:number, minute:number} | null}
 */
export function parseTimeOfDay(text) {
  const t = text.trim().toLowerCase();
  if (t === '') return null;
  const m = TIME.exec(t);
  if (!m) return null;
  const hasMarker = /^(at|@)/.test(t) || m[2] !== undefined || m[3] !== undefined;
  if (!hasMarker) return null;
  let hour = Number(m[1]);
  const minute = Number(m[2] ?? 0);
  if (minute > 59) return null;
  const meridiem = m[3]?.replaceAll('.', '');
  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    if (meridiem === 'am') hour = hour === 12 ? 0 : hour;
    else hour = hour === 12 ? 12 : hour + 12;
  }
  if (hour > 23) return null;
  return { hour, minute };
}

function withTime(day, time, tz, extra) {
  if (!time) return { kind: 'date', day, ...extra };
  const p = parseDay(day);
  return {
    kind: 'datetime',
    instant: zonedWallTimeToUtc({ ...p, hour: time.hour, minute: time.minute }, tz),
    ...extra,
  };
}

/** Splits "<date words> <time>" where the time part is optional. */
function splitTime(rest) {
  const trimmed = rest.trim().replace(/^,\s*/, '');
  if (trimmed === '') return { ok: true, time: null };
  const time = parseTimeOfDay(trimmed);
  return time ? { ok: true, time } : { ok: false };
}

/**
 * A one-off Todoist DATE.
 *
 * @param {string} value
 * @param {{lang?: string, tz: string, now: Date}} ctx
 * @returns {null | {unparsed: true} | {kind:'date', day:string, relative?:boolean, noYear?:boolean}
 *   | {kind:'datetime', instant:Date, relative?:boolean, noYear?:boolean}}
 */
export function parseTodoistDate(value, { lang = 'en', tz, now }) {
  const text = String(value ?? '')
    .trim()
    .replace(/\s+/g, ' ');
  if (text === '') return null;

  const iso = parseInstant(text, { tz });
  if (iso) return iso;
  // "2026-10-20 at 14:00" / "2026-10-20 2pm".
  const isoHead = /^(\d{4}-\d{2}-\d{2})\s+(.+)$/.exec(text);
  if (isoHead) {
    const d = parseInstant(isoHead[1], { tz });
    const t = splitTime(isoHead[2]);
    if (d && t.ok) return withTime(d.day, t.time, tz, {});
  }

  // Words are English or nothing: a Turkish "yarın" read as English would be
  // a wrong date, which is worse than none.
  if (lang && lang.toLowerCase() !== 'en' && /\p{L}/u.test(text)) return { unparsed: true };

  const lower = text.toLowerCase();
  const today = wallDayOf(now, tz);

  const rel = /^(today|tod|tomorrow|tom|yesterday)\b(.*)$/.exec(lower);
  if (rel) {
    const delta = { today: 0, tod: 0, tomorrow: 1, tom: 1, yesterday: -1 }[rel[1]];
    const t = splitTime(rel[2]);
    if (!t.ok) return { unparsed: true };
    return withTime(addDays(today, delta), t.time, tz, { relative: true });
  }

  // "Oct 20 2026", "October 20, 2026", "Oct 20" + optional time.
  let m = /^([a-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b(.*)$/.exec(lower);
  let month;
  let dayOfMonth;
  let year;
  let rest;
  if (m && monthNumber(m[1])) {
    [month, dayOfMonth, year, rest] = [monthNumber(m[1]), Number(m[2]), m[3], m[4]];
  } else {
    // "20 Oct 2026", "20 October" + optional time.
    m = /^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]+)\.?(?:,?\s+(\d{4}))?\b(.*)$/.exec(lower);
    if (!m || !monthNumber(m[2])) return { unparsed: true };
    [dayOfMonth, month, year, rest] = [Number(m[1]), monthNumber(m[2]), m[3], m[4]];
  }
  const t = splitTime(rest);
  if (!t.ok) return { unparsed: true };

  if (year !== undefined) {
    const day = validDay(Number(year), month, dayOfMonth);
    return day ? withTime(day, t.time, tz, {}) : { unparsed: true };
  }
  // No year: the next time that date comes round, today included.
  const thisYear = Number(today.slice(0, 4));
  for (const candidateYear of [thisYear, thisYear + 1, thisYear + 2, thisYear + 3, thisYear + 4]) {
    const day = validDay(candidateYear, month, dayOfMonth);
    if (day && day >= today) return withTime(day, t.time, tz, { noYear: true });
  }
  return { unparsed: true };
}

/** "HH:MM" → { hour, minute }. */
export function parseClock(hhmm) {
  const m = /^(\d{2}):(\d{2})$/.exec(hhmm ?? '');
  return m ? { hour: Number(m[1]), minute: Number(m[2]) } : { hour: 23, minute: 59 };
}

/**
 * The instant a parsed date becomes as a due date. A date without a time
 * takes the user's default task time — the same rule quick add follows.
 */
export function toDueAt(parsed, { tz, defaultTaskTime }) {
  if (!parsed || parsed.unparsed) return null;
  if (parsed.kind === 'datetime') return parsed.instant;
  const p = parseDay(parsed.day);
  return zonedWallTimeToUtc({ ...p, ...parseClock(defaultTaskTime) }, tz);
}
