/**
 * Recurrence engine (OPH-205, ADR-0020). Pure calendar math: a rule object in,
 * `YYYY-MM-DD` days out. No timezone, no clock, no database — the series'
 * timezone and time-of-day are applied by the caller (src/db/task-series.js)
 * through `zonedWallTimeToUtc`, exactly like every other wall-clock write.
 *
 * This file is the ONLY producer of occurrences. The Dart port
 * (apps/app/lib/src/core/recurrence.dart) exists for the dialog's "next 5"
 * preview and is pinned to this implementation by
 * apps/app/test/fixtures/recurrence_parity.json, which BOTH suites assert —
 * the ADR-0013 fold pattern. Change one side alone and a suite goes red.
 *
 * Two deliberate deviations from RFC 5545, both decided in ADR-0020 §2/§6:
 *
 * 1. **Invalid days clamp backwards** (RFC 7529 `SKIP=BACKWARD` semantics):
 *    the 31st lands on the 30th/29th/28th instead of vanishing. For a task,
 *    "the 31st" means month end. Clamping is per value and the result is a
 *    SET, so a window like 23…29 in a 28-day February collapses to 23…28
 *    instead of emitting the 28th twice.
 * 2. **The anchor is not automatically an occurrence.** RFC 5545 folds DTSTART
 *    into the recurrence set even when it does not match the rule; we emit
 *    matching days only. An off-pattern row inside a series is a lie about the
 *    rule, and the dialog seeds the rule from the task's own date so the
 *    common path matches anyway (the "next 5" preview shows the truth when it
 *    does not).
 */

/** Monday-first, because the rule model has no WKST and this is the ISO order. */
export const WEEKDAYS = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

export const FREQUENCIES = ['daily', 'weekly', 'monthly', 'yearly'];

/** Per-series materialization ceiling (ADR-0020 §4): a guard rail, not a budget. */
export const MAX_OCCURRENCES = 400;

/** Candidate periods we will step through before giving up (≈54 years of days). */
const ITERATION_GUARD = 20000;

const MONTHLY_OR_YEARLY = new Set(['monthly', 'yearly']);

function pad2(n) {
  return String(n).padStart(2, '0');
}

/** `{ year, month, day }` → `YYYY-MM-DD`. */
function toKey({ year, month, day }) {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

/** `YYYY-MM-DD` → `{ year, month, day }`; null for anything else. */
export function parseDay(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > lastDayOfMonth(year, month)) return null;
  return { year, month, day };
}

export function lastDayOfMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** 0 = Monday … 6 = Sunday. UTC only — these are wall dates, not instants. */
function weekdayIndex(year, month, day) {
  return (new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 6) % 7;
}

function addDays({ year, month, day }, delta) {
  const d = new Date(Date.UTC(year, month - 1, day + delta));
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

/** The Monday of the week containing this day. */
function startOfWeek(dayParts) {
  return addDays(dayParts, -weekdayIndex(dayParts.year, dayParts.month, dayParts.day));
}

function compareDays(a, b) {
  if (a.year !== b.year) return a.year - b.year;
  if (a.month !== b.month) return a.month - b.month;
  return a.day - b.day;
}

function invalid(message) {
  return { code: 'TASK_SERIES_RULE_INVALID', message };
}

/**
 * Semantic validation, on top of whatever Ajv already checked about shape.
 * @returns {{code: string, message: string} | null} null when the rule is usable.
 */
export function validateRule(rule) {
  if (!rule || typeof rule !== 'object') return invalid('rule must be an object');
  const { freq, interval, byWeekday, byMonthDay, byMonth, end } = rule;

  if (!FREQUENCIES.includes(freq)) return invalid(`freq must be one of ${FREQUENCIES.join(', ')}`);
  if (!Number.isInteger(interval) || interval < 1 || interval > 366) {
    return invalid('interval must be an integer between 1 and 366');
  }

  if (byWeekday != null) {
    if (!Array.isArray(byWeekday) || byWeekday.length === 0) {
      return invalid('byWeekday must be a non-empty array when present');
    }
    if (freq === 'daily') {
      // "Every weekday" is a weekly rule with five days — one way to say it.
      return invalid('byWeekday is not allowed with freq=daily; use freq=weekly');
    }
    for (const entry of byWeekday) {
      if (!entry || !WEEKDAYS.includes(entry.day)) {
        return invalid(`byWeekday.day must be one of ${WEEKDAYS.join(', ')}`);
      }
      const { ordinal } = entry;
      if (ordinal == null) continue;
      if (!MONTHLY_OR_YEARLY.has(freq)) {
        // RFC 5545: a numeric prefix on BYDAY is only legal for MONTHLY/YEARLY.
        return invalid('byWeekday.ordinal is only allowed with freq=monthly or yearly');
      }
      if (!Number.isInteger(ordinal) || ordinal === 0 || ordinal > 5 || ordinal < -1) {
        return invalid('byWeekday.ordinal must be 1..5 or -1 (last)');
      }
    }
  }

  if (byMonthDay != null) {
    if (!Array.isArray(byMonthDay) || byMonthDay.length === 0) {
      return invalid('byMonthDay must be a non-empty array when present');
    }
    if (!MONTHLY_OR_YEARLY.has(freq)) {
      return invalid('byMonthDay is only allowed with freq=monthly or yearly');
    }
    for (const day of byMonthDay) {
      if (!Number.isInteger(day) || day === 0 || day > 31 || day < -1) {
        return invalid('byMonthDay entries must be 1..31 or -1 (last day)');
      }
    }
  }

  if (byMonth != null) {
    if (!Array.isArray(byMonth) || byMonth.length === 0) {
      return invalid('byMonth must be a non-empty array when present');
    }
    if (freq !== 'yearly') return invalid('byMonth is only allowed with freq=yearly');
    for (const month of byMonth) {
      if (!Number.isInteger(month) || month < 1 || month > 12) {
        return invalid('byMonth entries must be 1..12');
      }
    }
  }

  if (end != null) {
    if (typeof end !== 'object') return invalid('end must be an object');
    if (end.type === 'until') {
      if (!parseDay(end.until)) return invalid('end.until must be a YYYY-MM-DD date');
    } else if (end.type === 'count') {
      if (!Number.isInteger(end.count) || end.count < 1 || end.count > 1000) {
        return invalid('end.count must be an integer between 1 and 1000');
      }
    } else if (end.type !== 'never') {
      return invalid('end.type must be never, until or count');
    }
  }

  return null;
}

/**
 * The day-of-month set a monthly/yearly rule selects in one concrete month.
 * Exported for tests and for the clamp documentation — this is where ADR-0020's
 * "clamp per value, then dedupe" lives.
 */
export function daysInMonthFor(rule, year, month, anchor) {
  const last = lastDayOfMonth(year, month);
  const hasMonthDays = Array.isArray(rule.byMonthDay) && rule.byMonthDay.length > 0;
  const hasWeekdays = Array.isArray(rule.byWeekday) && rule.byWeekday.length > 0;

  // No day selector at all: repeat the anchor's day-of-month, clamped.
  if (!hasMonthDays && !hasWeekdays) {
    return [Math.min(anchor.day, last)];
  }

  let monthDays = null;
  if (hasMonthDays) {
    const set = new Set();
    for (const value of rule.byMonthDay) {
      // -1 is "the last day"; a positive day past the month end clamps BACKWARD
      // onto it (31 → 30/29/28). Duplicates collapse — that is the point of a Set.
      const day = value < 0 ? last + 1 + value : Math.min(value, last);
      if (day >= 1 && day <= last) set.add(day);
    }
    monthDays = set;
  }

  let weekdayDays = null;
  if (hasWeekdays) {
    const set = new Set();
    for (const { day: name, ordinal } of rule.byWeekday) {
      const target = WEEKDAYS.indexOf(name);
      const matches = [];
      for (let day = 1; day <= last; day += 1) {
        if (weekdayIndex(year, month, day) === target) matches.push(day);
      }
      if (ordinal == null) {
        for (const day of matches) set.add(day);
      } else if (ordinal === -1) {
        if (matches.length > 0) set.add(matches[matches.length - 1]);
      } else if (matches.length >= ordinal) {
        // A 5th Tuesday simply does not exist in most months — no clamping here:
        // "the 5th Tuesday" is a real choice about which months count.
        set.add(matches[ordinal - 1]);
      }
    }
    weekdayDays = set;
  }

  let result;
  if (monthDays && weekdayDays) {
    // RFC 5545: with FREQ=MONTHLY, BYDAY *limits* BYMONTHDAY. This intersection
    // is how "the first Monday after the 22nd" is expressed (ADR-0020 §3).
    result = [...monthDays].filter((day) => weekdayDays.has(day));
  } else {
    result = [...(monthDays ?? weekdayDays)];
  }
  return result.sort((a, b) => a - b);
}

function dailyCandidates(rule, anchor, step) {
  return [addDays(anchor, step * rule.interval)];
}

function weeklyCandidates(rule, anchor, step) {
  const weekStart = addDays(startOfWeek(anchor), step * rule.interval * 7);
  const targets =
    Array.isArray(rule.byWeekday) && rule.byWeekday.length > 0
      ? rule.byWeekday.map((entry) => WEEKDAYS.indexOf(entry.day))
      : [weekdayIndex(anchor.year, anchor.month, anchor.day)];
  return [...new Set(targets)].sort((a, b) => a - b).map((offset) => addDays(weekStart, offset));
}

function monthlyCandidates(rule, anchor, step) {
  const index = anchor.year * 12 + (anchor.month - 1) + step * rule.interval;
  const year = Math.floor(index / 12);
  const month = (index % 12) + 1;
  return daysInMonthFor(rule, year, month, anchor).map((day) => ({ year, month, day }));
}

function yearlyCandidates(rule, anchor, step) {
  const year = anchor.year + step * rule.interval;
  const months =
    Array.isArray(rule.byMonth) && rule.byMonth.length > 0
      ? [...new Set(rule.byMonth)].sort((a, b) => a - b)
      : [anchor.month];
  return months.flatMap((month) =>
    daysInMonthFor(rule, year, month, anchor).map((day) => ({ year, month, day })),
  );
}

const CANDIDATES = {
  daily: dailyCandidates,
  weekly: weeklyCandidates,
  monthly: monthlyCandidates,
  yearly: yearlyCandidates,
};

/**
 * The first calendar day a period could possibly touch. Periods only move
 * forward, so once this is past the window the walk is over — without it, a
 * rule that produces nothing for a stretch (there is no 5th Monday in most
 * months) would step all the way to the iteration guard.
 */
const PERIOD_START = {
  daily: (rule, anchor, step) => addDays(anchor, step * rule.interval),
  weekly: (rule, anchor, step) => addDays(startOfWeek(anchor), step * rule.interval * 7),
  monthly: (rule, anchor, step) => {
    const index = anchor.year * 12 + (anchor.month - 1) + step * rule.interval;
    return { year: Math.floor(index / 12), month: (index % 12) + 1, day: 1 };
  },
  yearly: (rule, anchor, step) => ({ year: anchor.year + step * rule.interval, month: 1, day: 1 }),
};

function ruleError(message) {
  return Object.assign(new Error(message), { code: 'TASK_SERIES_RULE_INVALID' });
}

/**
 * Expand a rule into calendar days.
 *
 * Counting always starts at the anchor — `end.count` means "the Nth occurrence
 * of this series", not "the Nth one you can currently see" — so the walk begins
 * there and only the requested window is returned.
 *
 * @param {object} rule                     ADR-0020 rule object.
 * @param {object} options
 * @param {string} options.anchor           `YYYY-MM-DD` — the series seed day.
 * @param {string} [options.from]           inclusive window start (defaults to the anchor).
 * @param {string} [options.to]             inclusive window end; null = bounded by `max`/`end`.
 * @param {number} [options.max]            most days to return (default MAX_OCCURRENCES).
 * @returns {string[]} `YYYY-MM-DD`, ascending, unique.
 */
export function expandOccurrences(rule, { anchor, from, to, max = MAX_OCCURRENCES } = {}) {
  const problem = validateRule(rule);
  if (problem) throw Object.assign(new Error(problem.message), { code: problem.code });

  const anchorDay = parseDay(anchor);
  if (!anchorDay) throw ruleError('anchor must be a YYYY-MM-DD date');

  const fromDay = from ? parseDay(from) : anchorDay;
  if (!fromDay) throw ruleError('from must be a YYYY-MM-DD date');
  const toDay = to ? parseDay(to) : null;
  if (to && !toDay) throw ruleError('to must be a YYYY-MM-DD date');

  const end = rule.end ?? { type: 'never' };
  const untilDay = end.type === 'until' ? parseDay(end.until) : null;
  const limit = end.type === 'count' ? end.count : Infinity;

  const candidatesFor = CANDIDATES[rule.freq];
  const periodStartFor = PERIOD_START[rule.freq];
  const out = [];
  let emitted = 0; // occurrences since the anchor — what end.count counts

  for (let step = 0; step < ITERATION_GUARD; step += 1) {
    if (toDay && compareDays(periodStartFor(rule, anchorDay, step), toDay) > 0) return out;

    for (const candidate of candidatesFor(rule, anchorDay, step).sort(compareDays)) {
      if (compareDays(candidate, anchorDay) < 0) continue; // before the series began
      if (untilDay && compareDays(candidate, untilDay) > 0) return out;
      if (emitted >= limit) return out;
      emitted += 1;

      if (toDay && compareDays(candidate, toDay) > 0) continue;
      if (compareDays(candidate, fromDay) < 0) continue;
      out.push(toKey(candidate));
      if (out.length >= max) return out;
    }
  }

  return out;
}

/**
 * How many days a rule would produce inside a window — used to reject a series
 * before it materializes anything (`TASK_SERIES_TOO_DENSE`).
 */
export function countOccurrences(rule, options) {
  return expandOccurrences(rule, { ...options, max: MAX_OCCURRENCES + 1 }).length;
}
