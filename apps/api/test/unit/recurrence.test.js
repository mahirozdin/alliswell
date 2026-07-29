import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';

import {
  daysInMonthFor,
  expandOccurrences,
  lastDayOfMonth,
  MAX_OCCURRENCES,
  validateRule,
} from '../../src/lib/recurrence.js';

// ADR-0020 §6: the JS engine and the Dart preview port must agree day for day.
// The fixture lives with the app (apps/app/test/fixtures/recurrence_parity.json)
// and both suites assert it — the ADR-0013 fold arrangement.
const fixture = JSON.parse(
  readFileSync(
    new URL('../../../app/test/fixtures/recurrence_parity.json', import.meta.url),
    'utf8',
  ),
);

describe('lib/recurrence — cross-stack parity fixture (OPH-205, ADR-0020)', () => {
  for (const testCase of fixture.cases) {
    it(testCase.name, () => {
      const { rule, anchor, from, to, max } = testCase;
      expect(expandOccurrences(rule, { anchor, from, to, max })).toEqual(testCase.expected);
    });
  }
});

describe('lib/recurrence — clamping (ADR-0020 §2)', () => {
  it('clamps per value and then deduplicates, so a window never repeats a day', () => {
    // 23…29 in a 28-day February: 29 clamps onto 28, which is already in the set.
    const days = daysInMonthFor(
      { freq: 'monthly', interval: 1, byMonthDay: [23, 24, 25, 26, 27, 28, 29] },
      2026,
      2,
      { year: 2026, month: 2, day: 1 },
    );
    expect(days).toEqual([23, 24, 25, 26, 27, 28]);
  });

  it('reads -1 as the last day in every month length', () => {
    const rule = { freq: 'monthly', interval: 1, byMonthDay: [-1] };
    const anchor = { year: 2028, month: 1, day: 31 };
    expect(daysInMonthFor(rule, 2028, 2, anchor)).toEqual([29]); // leap
    expect(daysInMonthFor(rule, 2026, 2, anchor)).toEqual([28]);
    expect(daysInMonthFor(rule, 2026, 4, anchor)).toEqual([30]);
  });

  it('knows the length of every month', () => {
    expect(lastDayOfMonth(2026, 2)).toBe(28);
    expect(lastDayOfMonth(2028, 2)).toBe(29);
    expect(lastDayOfMonth(2000, 2)).toBe(29); // divisible by 400
    expect(lastDayOfMonth(1900, 2)).toBe(28); // century, not divisible by 400
    expect(lastDayOfMonth(2026, 12)).toBe(31);
  });
});

describe('lib/recurrence — the anchor (ADR-0020, deviation 2)', () => {
  it('never emits an off-pattern anchor', () => {
    // The task is dated the 5th; the rule says "the 2nd Tuesday". The 5th is not
    // an occurrence — RFC 5545 would fold DTSTART in, and that would be a lie.
    const days = expandOccurrences(
      { freq: 'monthly', interval: 1, byWeekday: [{ day: 'TU', ordinal: 2 }] },
      { anchor: '2026-01-05', from: '2026-01-01', to: '2026-02-28' },
    );
    expect(days).toEqual(['2026-01-13', '2026-02-10']);
  });

  it('never emits a day before the anchor, even when the window reaches back', () => {
    const days = expandOccurrences(
      { freq: 'daily', interval: 1 },
      { anchor: '2026-03-10', from: '2026-01-01', to: '2026-03-12' },
    );
    expect(days).toEqual(['2026-03-10', '2026-03-11', '2026-03-12']);
  });
});

describe('lib/recurrence — bounds', () => {
  it('stops at max and keeps the earliest days (the dialog asks for 5)', () => {
    const days = expandOccurrences(
      { freq: 'daily', interval: 1 },
      { anchor: '2026-01-01', from: '2026-01-01', max: 5 },
    );
    expect(days).toEqual(['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04', '2026-01-05']);
  });

  it('terminates on a rule that produces nothing inside the window', () => {
    // No 5th Monday in Jan/Feb 2026 — the walk must exit on the period start,
    // not grind to the iteration guard.
    const days = expandOccurrences(
      { freq: 'monthly', interval: 1, byWeekday: [{ day: 'MO', ordinal: 5 }] },
      { anchor: '2026-01-01', from: '2026-01-01', to: '2026-02-28' },
    );
    expect(days).toEqual([]);
  });

  it('a daily rule over 12 months stays under the materialization ceiling', () => {
    const days = expandOccurrences(
      { freq: 'daily', interval: 1 },
      { anchor: '2028-01-01', from: '2028-01-01', to: '2028-12-31', max: MAX_OCCURRENCES + 1 },
    );
    expect(days).toHaveLength(366); // leap year, the densest the model allows
    expect(days.length).toBeLessThan(MAX_OCCURRENCES);
  });
});

describe('lib/recurrence — validateRule', () => {
  it('accepts the three scenario classes', () => {
    expect(validateRule({ freq: 'monthly', interval: 1, byMonthDay: [31] })).toBeNull();
    expect(
      validateRule({ freq: 'monthly', interval: 1, byWeekday: [{ day: 'TU', ordinal: 2 }] }),
    ).toBeNull();
    expect(
      validateRule({
        freq: 'monthly',
        interval: 1,
        byWeekday: [{ day: 'MO', ordinal: null }],
        byMonthDay: [23, 24, 25, 26, 27, 28, 29],
      }),
    ).toBeNull();
  });

  it('rejects an ordinal weekday outside monthly/yearly (RFC 5545 forbids it)', () => {
    const problem = validateRule({
      freq: 'weekly',
      interval: 1,
      byWeekday: [{ day: 'MO', ordinal: 2 }],
    });
    expect(problem?.code).toBe('TASK_SERIES_RULE_INVALID');
  });

  it('rejects byWeekday on a daily rule (that rule is weekly)', () => {
    expect(
      validateRule({ freq: 'daily', interval: 1, byWeekday: [{ day: 'MO', ordinal: null }] })?.code,
    ).toBe('TASK_SERIES_RULE_INVALID');
  });

  it('rejects out-of-range days, intervals, frequencies and end conditions', () => {
    expect(validateRule({ freq: 'hourly', interval: 1 })).not.toBeNull();
    expect(validateRule({ freq: 'daily', interval: 0 })).not.toBeNull();
    expect(validateRule({ freq: 'monthly', interval: 1, byMonthDay: [32] })).not.toBeNull();
    expect(validateRule({ freq: 'monthly', interval: 1, byMonthDay: [-2] })).not.toBeNull();
    expect(validateRule({ freq: 'monthly', interval: 1, byMonth: [1] })).not.toBeNull();
    expect(
      validateRule({ freq: 'daily', interval: 1, end: { type: 'until', until: '2026-02-30' } }),
    ).not.toBeNull();
    expect(
      validateRule({ freq: 'daily', interval: 1, end: { type: 'count', count: 0 } }),
    ).not.toBeNull();
  });

  it('throws through expandOccurrences rather than returning nonsense', () => {
    expect(() =>
      expandOccurrences({ freq: 'daily', interval: 0 }, { anchor: '2026-01-01' }),
    ).toThrow(/interval/);
    expect(() =>
      expandOccurrences({ freq: 'daily', interval: 1 }, { anchor: 'yesterday' }),
    ).toThrow(/YYYY-MM-DD/);
  });
});
