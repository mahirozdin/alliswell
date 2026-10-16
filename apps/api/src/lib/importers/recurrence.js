import { validateRule } from '../recurrence.js';
import { monthNumber, parseTimeOfDay } from './dates.js';

/**
 * Recurrences from other apps → our rule model (OPH-371, ADR-0052, ADR-0020).
 *
 * Two inputs:
 * - Todoist's DATE column holds the English phrase the user typed ("every
 *   other tuesday at 9am"). Todoist's own exports drop the "starting …" part,
 *   so a phrase without its own anchor day ("every month") cannot be placed
 *   and is not guessed.
 * - TickTick's Repeat column holds an RFC 5545 RRULE.
 *
 * Only what our engine represents EXACTLY is converted. Everything else
 * returns null and the importer keeps the original text in the description
 * with a warning — a repeat that silently fires on the wrong days is worse
 * than one the user sets again. Every rule produced here passes
 * lib/recurrence.js `validateRule`, or null is returned.
 */

const DAY_WORDS = {
  mo: 'MO',
  mon: 'MO',
  monday: 'MO',
  tu: 'TU',
  tue: 'TU',
  tues: 'TU',
  tuesday: 'TU',
  we: 'WE',
  wed: 'WE',
  wednesday: 'WE',
  th: 'TH',
  thu: 'TH',
  thur: 'TH',
  thurs: 'TH',
  thursday: 'TH',
  fr: 'FR',
  fri: 'FR',
  friday: 'FR',
  sa: 'SA',
  sat: 'SA',
  saturday: 'SA',
  su: 'SU',
  sun: 'SU',
  sunday: 'SU',
};
const WEEKDAY_ORDER = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

const ORDINALS = {
  first: 1,
  '1st': 1,
  second: 2,
  '2nd': 2,
  third: 3,
  '3rd': 3,
  fourth: 4,
  '4th': 4,
  fifth: 5,
  '5th': 5,
  last: -1,
};

function checked(rule) {
  return validateRule(rule) ? null : rule;
}

function sortDays(days) {
  return [...new Set(days)].sort((a, b) => WEEKDAY_ORDER.indexOf(a) - WEEKDAY_ORDER.indexOf(b));
}

/** "mon, wed and fri" → ['MO','WE','FR'] or null when any word is not a day. */
function dayList(text) {
  const words = text
    .split(/\s*,\s*|\s+and\s+|\s+/)
    .map((w) => w.trim())
    .filter(Boolean);
  if (words.length === 0) return null;
  const days = [];
  for (const word of words) {
    const day = DAY_WORDS[word.replace(/s$/, '')] ?? DAY_WORDS[word];
    if (!day) return null;
    days.push(day);
  }
  return sortDays(days);
}

/** "1st and 15th", "15", "1st, 15th" → [1, 15] or null. */
function monthDayList(text) {
  const words = text
    .split(/\s*,\s*|\s+and\s+/)
    .map((w) => w.trim())
    .filter(Boolean);
  if (words.length === 0) return null;
  const days = [];
  for (const word of words) {
    const m = /^(\d{1,2})(st|nd|rd|th)?$/.exec(word);
    if (!m) return null;
    const n = Number(m[1]);
    if (n < 1 || n > 31) return null;
    days.push(n);
  }
  return [...new Set(days)].sort((a, b) => a - b);
}

/** Splits a trailing " at 9am" / " @ 13:00" / " 14:00" off a phrase. */
function splitTrailingTime(text) {
  const m =
    /^(.*?)\s+((?:at|@)\s*[\d:]+\s*(?:am|pm|a\.m\.|p\.m\.)?|\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2})$/.exec(
      text,
    );
  if (!m) return { body: text, time: null };
  const time = parseTimeOfDay(m[2]);
  return time ? { body: m[1].trim(), time } : { body: text, time: null };
}

/**
 * A Todoist recurrence phrase → `{ rule, time }`, or null when it is not one we
 * can represent exactly. English only.
 */
export function todoistRecurrence(value, lang = 'en') {
  if (lang && lang.toLowerCase() !== 'en') return null;
  const text = String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
  if (text === '') return null;
  // "every!" repeats from completion; "starting/until/for N times" carry an
  // anchor or an end the export no longer has in full; hours are below a day.
  if (
    /every\s*!|\bev!|\bafter\b|\bstarting\b|\bfrom\b|\buntil\b|\bending\b|\bfor \d+|\bhours?\b|\bminutes?\b|\bmins?\b/.test(
      text,
    )
  ) {
    return null;
  }

  const { body, time } = splitTrailingTime(text);
  let phrase = body;
  if (phrase === 'daily') phrase = 'every day';
  if (phrase === 'weekly' || phrase === 'monthly' || phrase === 'yearly') return null;
  const m = /^(?:every|each) (.+)$/.exec(phrase);
  if (!m) return null;
  const rest = m[1];
  const done = (rule) => {
    const ok = checked({ ...rule, end: { type: 'never' } });
    return ok ? { rule: ok, time } : null;
  };

  // every day / every 3 days / every other day
  if (rest === 'day') return done({ freq: 'daily', interval: 1 });
  if (rest === 'other day') return done({ freq: 'daily', interval: 2 });
  let x = /^(\d{1,3}) days?$/.exec(rest);
  if (x) return done({ freq: 'daily', interval: Number(x[1]) });

  // every weekday / workday
  if (rest === 'weekday' || rest === 'workday' || rest === 'work day') {
    return done({
      freq: 'weekly',
      interval: 1,
      byWeekday: ['MO', 'TU', 'WE', 'TH', 'FR'].map((day) => ({ day })),
    });
  }

  // every other tuesday / every 2 weeks on mon, fri / every week on monday
  x = /^other (.+)$/.exec(rest);
  if (x) {
    const days = dayList(x[1]);
    if (days) return done({ freq: 'weekly', interval: 2, byWeekday: days.map((day) => ({ day })) });
    return null;
  }
  x = /^(?:(\d{1,3}) weeks?|week) on (.+)$/.exec(rest);
  if (x) {
    const days = dayList(x[2]);
    if (!days) return null;
    return done({
      freq: 'weekly',
      interval: x[1] ? Number(x[1]) : 1,
      byWeekday: days.map((day) => ({ day })),
    });
  }

  // every first monday / every last friday (of the month)
  x =
    /^(first|second|third|fourth|fifth|last|1st|2nd|3rd|4th|5th) ([a-z]+)(?: of (?:the|every) month)?$/.exec(
      rest,
    );
  if (x && x[2] !== 'day' && DAY_WORDS[x[2]]) {
    return done({
      freq: 'monthly',
      interval: 1,
      byWeekday: [{ day: DAY_WORDS[x[2]], ordinal: ORDINALS[x[1]] }],
    });
  }

  // every last day (of the month)
  if (/^(?:month on the )?last day(?: of (?:the|every) month)?$/.test(rest)) {
    return done({ freq: 'monthly', interval: 1, byMonthDay: [-1] });
  }

  // every 15th / every 1st and 15th / every month on the 15th
  x = /^(?:month on (?:the )?)?(.+?)(?: of (?:the|every) month)?$/.exec(rest);
  if (x) {
    const days = monthDayList(x[1].replace(/^the /, ''));
    if (days) return done({ freq: 'monthly', interval: 1, byMonthDay: days });
  }

  // every jan 31 / every 31 jan / every year on jan 31
  x = /^(?:year on )?([a-z]+)\.? (\d{1,2})(?:st|nd|rd|th)?$/.exec(rest);
  if (x && monthNumber(x[1])) {
    return done({
      freq: 'yearly',
      interval: 1,
      byMonth: [monthNumber(x[1])],
      byMonthDay: [Number(x[2])],
    });
  }
  x = /^(?:year on )?(\d{1,2})(?:st|nd|rd|th)? ([a-z]+)\.?$/.exec(rest);
  if (x && monthNumber(x[2])) {
    return done({
      freq: 'yearly',
      interval: 1,
      byMonth: [monthNumber(x[2])],
      byMonthDay: [Number(x[1])],
    });
  }

  // every monday / every mon, fri
  const days = dayList(rest);
  if (days) return done({ freq: 'weekly', interval: 1, byWeekday: days.map((day) => ({ day })) });

  return null;
}

const RRULE_KEYS = new Set([
  'FREQ',
  'INTERVAL',
  'BYDAY',
  'BYMONTHDAY',
  'BYMONTH',
  'COUNT',
  'UNTIL',
  'WKST',
]);

/**
 * An RFC 5545 RRULE (TickTick's Repeat column) → our rule, or null.
 * Takes the first RRULE line; any part we do not model (BYSETPOS, BYHOUR,
 * TickTick's own TT_* parts…) makes the whole rule unrepresentable.
 */
export function rruleToRule(value) {
  const lines = String(value ?? '')
    .split(/[\r\n]+/)
    .map((l) => l.trim())
    .filter(Boolean);
  const line = lines.find((l) => /^RRULE:/i.test(l)) ?? lines.find((l) => /FREQ=/i.test(l));
  if (!line) return null;
  const body = line.replace(/^RRULE:/i, '');
  const parts = {};
  for (const part of body.split(';')) {
    if (part.trim() === '') continue;
    const [k, v] = part.split('=');
    const key = k.trim().toUpperCase();
    if (!RRULE_KEYS.has(key) || v === undefined) return null;
    parts[key] = v.trim().toUpperCase();
  }
  const freq = { DAILY: 'daily', WEEKLY: 'weekly', MONTHLY: 'monthly', YEARLY: 'yearly' }[
    parts.FREQ
  ];
  if (!freq) return null;
  if (parts.WKST && parts.WKST !== 'MO' && parts.WKST !== 'SU') return null;
  const rule = { freq, interval: parts.INTERVAL ? Number(parts.INTERVAL) : 1 };

  if (parts.BYDAY) {
    const entries = [];
    for (const token of parts.BYDAY.split(',')) {
      const m = /^([+-]?\d)?(MO|TU|WE|TH|FR|SA|SU)$/.exec(token.trim());
      if (!m) return null;
      entries.push(m[1] ? { day: m[2], ordinal: Number(m[1]) } : { day: m[2] });
    }
    // "Every weekday" is weekly in our model (lib/recurrence.js says so).
    if (rule.freq === 'daily') {
      if (rule.interval !== 1 || entries.some((e) => e.ordinal != null)) return null;
      rule.freq = 'weekly';
    }
    rule.byWeekday = entries;
  }
  if (parts.BYMONTHDAY) {
    rule.byMonthDay = parts.BYMONTHDAY.split(',').map(Number);
  }
  if (parts.BYMONTH) {
    rule.byMonth = parts.BYMONTH.split(',').map(Number);
  }
  if (parts.COUNT && parts.UNTIL) return null;
  if (parts.COUNT) {
    rule.end = { type: 'count', count: Number(parts.COUNT) };
  } else if (parts.UNTIL) {
    const m = /^(\d{4})(\d{2})(\d{2})(T\d{6}Z?)?$/.exec(parts.UNTIL);
    if (!m) return null;
    rule.end = { type: 'until', until: `${m[1]}-${m[2]}-${m[3]}` };
  } else {
    rule.end = { type: 'never' };
  }
  return checked(rule);
}
