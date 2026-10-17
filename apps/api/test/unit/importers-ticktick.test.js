import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, expect } from 'vitest';
import { parseImport } from '../../src/lib/importers/index.js';
import { reminderMinutes } from '../../src/lib/importers/ticktick.js';

/** OPH-371 — TickTick backup CSV, on a fixture with the real header and preamble. */
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../fixtures/importers');
const file = (sub, name) => ({ name, content: fs.readFileSync(path.join(dir, sub, name), 'utf8') });
const ctx = {
  tz: 'Europe/Istanbul',
  now: new Date('2026-10-16T09:00:00Z'),
  defaultTaskTime: '23:59',
  locale: 'en',
};
const backup = () => parseImport('ticktick', [file('ticktick', 'backup-2026-10.csv')], ctx);
const byKey = (items, id) => items.find((i) => i.key === `ticktick|task|${id}`);

describe('importers: ticktick', () => {
  it('reads past the BOM and the multi-line preamble; maps a timed task', () => {
    const { items } = backup();
    const report = byKey(items, 't-parent');
    expect(report.title).toBe('Rapor yaz');
    expect(report.priority).toBe('high');
    expect(report.tagNames).toEqual(['iş', 'acil', 'Yapılacak']);
    expect(report.scheduledStartAt.toISOString()).toBe('2030-11-02T07:00:00.000Z');
    expect(report.scheduledEndAt.toISOString()).toBe('2030-11-02T09:00:00.000Z');
    expect(report.dueAt.toISOString()).toBe('2030-11-02T09:00:00.000Z');
    expect(report.remindMinutesBefore).toBe(15);
    expect(report.remindAt.toISOString()).toBe('2030-11-02T08:45:00.000Z');
  });

  it('a child that comes BEFORE its parent still becomes its checklist item', () => {
    const { items, warnings } = backup();
    expect(byKey(items, 't-child')).toBeUndefined();
    expect(byKey(items, 't-parent').checklist).toEqual([
      { title: 'Alt görev önce gelir', isDone: false },
    ]);
    expect(byKey(items, 't-parent').description).toContain('Alt görev önce gelir: alt açıklama');
    // A parent that is not in the file leaves the child standalone, said aloud.
    expect(byKey(items, 't-orphan')).toBeDefined();
    expect(warnings.some((w) => w.code === 'IMPORT_ORPHAN_SUBTASK')).toBe(true);
  });

  it('checklist lines keep their ticks; the rest stays the description', () => {
    const market = byKey(backup().items, 't-check');
    expect(market.checklist).toEqual([
      { title: 'Süt', isDone: false },
      { title: 'Ekmek', isDone: true },
      { title: 'Yumurta', isDone: false },
    ]);
    expect(market.description).toBe('Not satırı');
    // All-day: the Berlin wall day (the 29th), at the default task time.
    expect(market.dueAt.toISOString()).toBe('2023-03-29T21:59:00.000Z');
    expect(market.priority).toBe('medium');
    expect(market.tagNames).toEqual([]); // "Not Sectioned" is no tag
  });

  it('NOTE rows become notes', () => {
    const note = byKey(backup().items, 't-note');
    expect(note).toMatchObject({
      kind: 'note',
      title: 'Fikir defteri',
      markdown: '# Başlık\nmetin',
    });
    expect(note.tagNames).toEqual(['fikir']);
  });

  it('status 1 and 2 are completed with their completion time', () => {
    const { items } = backup();
    expect(byKey(items, 't-done')).toMatchObject({ completed: true, priority: 'low' });
    expect(byKey(items, 't-done').completedAt.toISOString()).toBe('2026-10-01T10:00:00.000Z');
    expect(byKey(items, 't-archived').completed).toBe(true);
  });

  it('two lists with one name in different folders keep the folder', () => {
    const { projects, warnings } = backup();
    expect(projects.map((p) => p.name).sort()).toEqual([
      'Alışveriş (Ev)',
      'Alışveriş (İş)',
      'Notlar',
      'Proje Alpha',
    ]);
    expect(warnings.filter((w) => w.code === 'IMPORT_FOLDER_FLATTENED')).toHaveLength(2);
  });

  it('repeat: a weekly RRULE becomes a series; BYSETPOS stays in the note', () => {
    const { items } = backup();
    const weekly = byKey(items, 't-weekly');
    expect(weekly.recurrence.rule).toEqual({
      freq: 'weekly',
      interval: 1,
      byWeekday: [{ day: 'TU' }],
      end: { type: 'never' },
    });
    expect(weekly.anchorAt.toISOString()).toBe('2030-11-05T07:00:00.000Z');
    expect(weekly.remindMinutesBefore).toBe(60); // TRIGGER:-PT1H
    const setpos = byKey(items, 't-setpos');
    expect(setpos.recurrence).toBeNull();
    expect(setpos.timezone).toBe('America/New_York');
    expect(setpos.description).toContain('BYSETPOS');
  });

  it('floating and empty zones fall back to the profile zone', () => {
    const { items } = backup();
    expect(byKey(items, 't-float').timezone).toBe('Europe/Istanbul');
    expect(byKey(items, 't-float').dueAt.toISOString()).toBe('2030-11-05T07:00:00.000Z');
    expect(byKey(items, 't-notz')).toMatchObject({
      timezone: 'Europe/Istanbul',
      remindMinutesBefore: 0,
    });
  });

  it('a long Turkish title is cut to 500 characters with a warning', () => {
    const { items, warnings } = backup();
    expect([...byKey(items, 't-long').title]).toHaveLength(500);
    expect(warnings.some((w) => w.code === 'IMPORT_TITLE_TRUNCATED')).toBe(true);
  });

  it('odd dates: space-separated, year 0001, an invalid month, date-only', () => {
    const { items, warnings } = parseImport('ticktick', [file('ticktick', 'odd-dates.csv')], ctx);
    expect(byKey(items, 'o-space').dueAt.toISOString()).toBe('2030-02-20T07:00:00.000Z');
    expect(byKey(items, 'o-zero').dueAt).toBeNull();
    expect(byKey(items, 'o-month').dueAt).toBeNull();
    expect(byKey(items, 'o-month').description).toContain('2030-13-01');
    expect(byKey(items, 'o-dateonly').dueAt.toISOString()).toBe('2030-03-01T20:59:00.000Z');
    // Year 0001 is "no date", not an unreadable one.
    expect(warnings.filter((w) => w.code === 'IMPORT_DATE_KEPT_IN_NOTE')).toHaveLength(1);
  });

  it('reminder durations', () => {
    expect(reminderMinutes('-PT15M')).toBe(-15);
    expect(reminderMinutes('TRIGGER:-PT1H')).toBe(-60);
    expect(reminderMinutes('PT0S')).toBe(0);
    expect(reminderMinutes('-P1DT2H')).toBe(-1560);
    expect(reminderMinutes('')).toBeNull();
  });

  it('refuses a Todoist file with the source it detected', () => {
    expect(() => parseImport('ticktick', [file('todoist', 'Inbox [2203306141].csv')], ctx)).toThrow(
      expect.objectContaining({ code: 'IMPORT_SOURCE_MISMATCH', detected: 'todoist' }),
    );
  });
});
