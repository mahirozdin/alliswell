import { describe, it, expect } from 'vitest';
import { rruleToRule, todoistRecurrence } from '../../src/lib/importers/recurrence.js';
import { validateRule } from '../../src/lib/recurrence.js';

/** OPH-371 — only what our engine represents exactly is converted. */
const w = (...days) => days.map((day) => ({ day }));
const never = { end: { type: 'never' } };

describe('importers: todoistRecurrence', () => {
  const cases = [
    ['every day', { freq: 'daily', interval: 1 }],
    ['daily', { freq: 'daily', interval: 1 }],
    ['every 3 days', { freq: 'daily', interval: 3 }],
    ['every weekday', { freq: 'weekly', interval: 1, byWeekday: w('MO', 'TU', 'WE', 'TH', 'FR') }],
    ['every mon, fri', { freq: 'weekly', interval: 1, byWeekday: w('MO', 'FR') }],
    ['every monday and thursday', { freq: 'weekly', interval: 1, byWeekday: w('MO', 'TH') }],
    ['every other tuesday', { freq: 'weekly', interval: 2, byWeekday: w('TU') }],
    ['every 3 weeks on wed', { freq: 'weekly', interval: 3, byWeekday: w('WE') }],
    ['every 15th', { freq: 'monthly', interval: 1, byMonthDay: [15] }],
    ['every 1st and 15th', { freq: 'monthly', interval: 1, byMonthDay: [1, 15] }],
    ['every month on the 31st', { freq: 'monthly', interval: 1, byMonthDay: [31] }],
    ['every last day', { freq: 'monthly', interval: 1, byMonthDay: [-1] }],
    [
      'every first monday',
      { freq: 'monthly', interval: 1, byWeekday: [{ day: 'MO', ordinal: 1 }] },
    ],
    [
      'every last friday',
      { freq: 'monthly', interval: 1, byWeekday: [{ day: 'FR', ordinal: -1 }] },
    ],
    ['every jan 31', { freq: 'yearly', interval: 1, byMonth: [1], byMonthDay: [31] }],
    ['every 29 feb', { freq: 'yearly', interval: 1, byMonth: [2], byMonthDay: [29] }],
  ];
  for (const [phrase, expected] of cases) {
    it(`"${phrase}"`, () => {
      const got = todoistRecurrence(phrase);
      expect(got.rule).toEqual({ ...expected, ...never });
      expect(validateRule(got.rule)).toBeNull();
      expect(got.time).toBeNull();
    });
  }

  it('reads a trailing time', () => {
    expect(todoistRecurrence('every year on jan 31 at 9:00')).toEqual({
      rule: { freq: 'yearly', interval: 1, byMonth: [1], byMonthDay: [31], ...never },
      time: { hour: 9, minute: 0 },
    });
    expect(todoistRecurrence('every day @ 13:30').time).toEqual({ hour: 13, minute: 30 });
    expect(todoistRecurrence('every mon at 7am').time).toEqual({ hour: 7, minute: 0 });
  });

  it('refuses what it cannot place exactly', () => {
    for (const phrase of [
      'every week',
      'every month @ 13:00',
      'every year',
      'every!',
      'every! 3 days',
      'every day starting jan 1',
      'every day until dec 31',
      'every hour',
      'every 2nd weekday',
      'every 2 hours',
      'her gün',
    ]) {
      expect(todoistRecurrence(phrase), phrase).toBeNull();
    }
    expect(todoistRecurrence('every day', 'tr')).toBeNull();
  });
});

describe('importers: rruleToRule', () => {
  it('maps the parts we model', () => {
    expect(rruleToRule('RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE')).toEqual({
      freq: 'weekly',
      interval: 1,
      byWeekday: w('MO', 'WE'),
      ...never,
    });
    expect(rruleToRule('FREQ=MONTHLY;BYDAY=-1FR')).toEqual({
      freq: 'monthly',
      interval: 1,
      byWeekday: [{ day: 'FR', ordinal: -1 }],
      ...never,
    });
    expect(rruleToRule('RRULE:FREQ=MONTHLY;BYMONTHDAY=31').byMonthDay).toEqual([31]);
    expect(rruleToRule('RRULE:FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29')).toEqual({
      freq: 'yearly',
      interval: 1,
      byMonth: [2],
      byMonthDay: [29],
      ...never,
    });
    expect(rruleToRule('RRULE:FREQ=DAILY;COUNT=10').end).toEqual({ type: 'count', count: 10 });
    expect(rruleToRule('RRULE:FREQ=DAILY;UNTIL=20261231T000000Z').end).toEqual({
      type: 'until',
      until: '2026-12-31',
    });
    // DAILY + BYDAY is "weekly on those days" in our model.
    expect(rruleToRule('RRULE:FREQ=DAILY;BYDAY=MO,TU').freq).toBe('weekly');
  });

  it('refuses parts we do not model', () => {
    expect(rruleToRule('RRULE:FREQ=MONTHLY;BYSETPOS=-1;BYDAY=MO,TU')).toBeNull();
    expect(rruleToRule('RRULE:FREQ=DAILY;INTERVAL=1;TT_SKIP=HOLIDAY')).toBeNull();
    expect(rruleToRule('RRULE:FREQ=HOURLY')).toBeNull();
    expect(rruleToRule('RRULE:FREQ=WEEKLY;BYDAY=1MO')).toBeNull(); // ordinal needs monthly
    expect(rruleToRule('')).toBeNull();
  });
});
