import { describe, it, expect } from 'vitest';
import {
  parseInstant,
  parseTodoistDate,
  toDueAt,
  wallDayOf,
} from '../../src/lib/importers/dates.js';

/** OPH-371 — dates as Todoist and TickTick write them. */
const iso = (p) => p.instant.toISOString();

describe('importers: parseInstant', () => {
  it('reads +0000, Z and +03:00 offsets', () => {
    const tz = 'Europe/Istanbul';
    expect(iso(parseInstant('2026-03-26T10:00:00+0000', { tz }))).toBe('2026-03-26T10:00:00.000Z');
    expect(iso(parseInstant('2026-03-26T10:00:00Z', { tz }))).toBe('2026-03-26T10:00:00.000Z');
    expect(iso(parseInstant('2026-03-26T10:00:00+03:00', { tz }))).toBe('2026-03-26T07:00:00.000Z');
  });

  it('reads a space-separated wall time on the given zone', () => {
    expect(iso(parseInstant('2026-02-20 10:00:00', { tz: 'Europe/Berlin' }))).toBe(
      '2026-02-20T09:00:00.000Z',
    );
    expect(iso(parseInstant('2026-02-20 10:00', { tz: 'Europe/Istanbul' }))).toBe(
      '2026-02-20T07:00:00.000Z',
    );
  });

  it('returns a day for a date-only value', () => {
    expect(parseInstant('2030-03-01', { tz: 'UTC' })).toEqual({ kind: 'date', day: '2030-03-01' });
  });

  it('refuses impossible dates and treats year 0001 as no date', () => {
    expect(parseInstant('2026-02-29', { tz: 'UTC' })).toBeNull();
    expect(parseInstant('2026-13-01T10:00:00+0000', { tz: 'UTC' })).toBeNull();
    expect(parseInstant('2024-02-29', { tz: 'UTC' })).toEqual({ kind: 'date', day: '2024-02-29' });
    expect(parseInstant('0001-01-01T00:00:00+0000', { tz: 'UTC' })).toBeNull();
  });

  it('DST: the gap moves forward, the overlap takes the later instant', () => {
    // LESSONS calendar: Istanbul has no DST, so Berlin proves this.
    const gap = parseInstant('2026-03-29 02:30', { tz: 'Europe/Berlin' });
    expect(wallDayOf(gap.instant, 'Europe/Berlin')).toBe('2026-03-29');
    expect(iso(gap)).toBe('2026-03-29T01:30:00.000Z');
    const overlap = parseInstant('2026-10-25 02:30', { tz: 'Europe/Berlin' });
    expect(iso(overlap)).toBe('2026-10-25T01:30:00.000Z');
  });

  it('TickTick all-day: local midnight written in UTC is the NEXT wall day in Berlin', () => {
    const p = parseInstant('2023-03-28T22:00:00+0000', { tz: 'Europe/Berlin' });
    expect(wallDayOf(p.instant, 'Europe/Berlin')).toBe('2023-03-29');
  });
});

describe('importers: toDueAt', () => {
  it('a date takes the default task time on the zone', () => {
    const tz = 'Europe/Istanbul';
    const day = { kind: 'date', day: '2026-10-20' };
    expect(toDueAt(day, { tz, defaultTaskTime: '23:59' }).toISOString()).toBe(
      '2026-10-20T20:59:00.000Z',
    );
    expect(toDueAt(day, { tz, defaultTaskTime: '09:00' }).toISOString()).toBe(
      '2026-10-20T06:00:00.000Z',
    );
  });
});

describe('importers: parseTodoistDate', () => {
  const ctx = { lang: 'en', tz: 'Europe/Istanbul', now: new Date('2026-10-16T09:00:00Z') };

  it('today / tomorrow are relative to now and flagged', () => {
    const today = parseTodoistDate('today at 11:00', ctx);
    expect(today.relative).toBe(true);
    expect(iso(today)).toBe('2026-10-16T08:00:00.000Z');
    const tomorrow = parseTodoistDate('tomorrow 9am', ctx);
    expect(iso(tomorrow)).toBe('2026-10-17T06:00:00.000Z');
  });

  it('English month forms with and without a time', () => {
    expect(iso(parseTodoistDate('Oct 20 2026 2:30 PM', ctx))).toBe('2026-10-20T11:30:00.000Z');
    expect(iso(parseTodoistDate('20 Oct 2026 14:00', ctx))).toBe('2026-10-20T11:00:00.000Z');
    expect(parseTodoistDate('October 20, 2026', ctx)).toEqual({ kind: 'date', day: '2026-10-20' });
  });

  it('a date without a year rolls forward to its next occurrence', () => {
    expect(parseTodoistDate('Oct 20', ctx)).toEqual({
      kind: 'date',
      day: '2026-10-20',
      noYear: true,
    });
    expect(parseTodoistDate('Oct 1', ctx).day).toBe('2027-10-01');
  });

  it('words in another language, weekdays and bad times are not guessed', () => {
    expect(parseTodoistDate('yarın', { ...ctx, lang: 'tr' })).toEqual({ unparsed: true });
    expect(parseTodoistDate('Friday', ctx)).toEqual({ unparsed: true });
    expect(parseTodoistDate('Oct 20 2026 25:00', ctx)).toEqual({ unparsed: true });
    expect(parseTodoistDate('', ctx)).toBeNull();
  });

  it('an ISO date in a non-English row is still read', () => {
    expect(parseTodoistDate('2026-10-22', { ...ctx, lang: 'tr' })).toEqual({
      kind: 'date',
      day: '2026-10-22',
    });
  });
});
