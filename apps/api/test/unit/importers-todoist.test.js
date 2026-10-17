import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, expect } from 'vitest';
import { externalKey, parseImport } from '../../src/lib/importers/index.js';
import { extractLabels, projectNameFromFile } from '../../src/lib/importers/todoist.js';
import { slugify } from '../../src/lib/slug.js';

/** OPH-371 — Todoist CSV, on fixtures built from the official template's columns. */
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../fixtures/importers');
const file = (sub, name) => ({ name, content: fs.readFileSync(path.join(dir, sub, name), 'utf8') });
const ctx = {
  tz: 'Europe/Istanbul',
  now: new Date('2026-10-16T09:00:00Z'),
  defaultTaskTime: '23:59',
  locale: 'en',
};
const ev = () => file('todoist', 'Ev İşleri [2203306142].csv');
const inbox = () => file('todoist', 'Inbox [2203306141].csv');
const byTitle = (items, title) => items.find((i) => i.title === title);

describe('importers: todoist', () => {
  it('project names come from the file name; the Inbox is no project', () => {
    expect(projectNameFromFile('Ev İşleri [2203306142].csv')).toBe('Ev İşleri');
    expect(projectNameFromFile('backup/Ev İşleri.csv')).toBe('Ev İşleri');
    expect(projectNameFromFile('Inbox [2203306141].csv')).toBeNull();
    const { items, projects } = parseImport('todoist', [inbox(), ev()], ctx);
    expect(projects).toEqual([{ key: 'todoist|project|ev isleri', name: 'Ev İşleri' }]);
    expect(byTitle(items, 'Kitap oku').projectKey).toBeNull();
  });

  it('labels and sections become tags; an email is not a label', () => {
    expect(extractLabels('Ali’ye yaz ali@example.com @iş-yeri @acil.')).toEqual({
      title: 'Ali’ye yaz ali@example.com',
      labels: ['iş-yeri', 'acil'],
    });
    const { items } = parseImport('todoist', [ev()], ctx);
    expect(byTitle(items, 'Bulaşık makinesini boşalt').tagNames).toEqual(['ev', 'acil', 'Mutfak']);
    expect(byTitle(items, 'Çimleri biç').tagNames).toEqual(['Bahçe']);
    // Turkish slugs collapse: İş / is are one tag.
    const slugs = [byTitle(items, 'İş'), byTitle(items, 'is')].map((i) => slugify(i.tagNames[0]));
    expect(new Set(slugs)).toEqual(new Set(['is']));
  });

  it('priority: p1 is the highest', () => {
    const { items } = parseImport('todoist', [ev()], ctx);
    expect(byTitle(items, 'Bulaşık makinesini boşalt').priority).toBe('high');
    expect(byTitle(items, "Ali'ye yaz ali@example.com").priority).toBe('medium');
    expect(byTitle(items, 'Market alışverişi').priority).toBe('low');
    expect(byTitle(items, 'Kitap oku')).toBeUndefined();
    expect(byTitle(items, 'Çimleri biç').priority).toBe('none');
    expect(byTitle(items, 'Tohum al, sulama sistemi kur').priority).toBe('none'); // blank
  });

  it('sub-tasks become a checklist, deeper levels flatten, details move up', () => {
    const { items, warnings } = parseImport('todoist', [ev()], ctx);
    const market = byTitle(items, 'Market alışverişi');
    expect(market.checklist.map((c) => c.title)).toEqual(['Süt', 'Yumurta', 'Serbest gezen']);
    expect(market.description).toContain('Yumurta: organik olsun');
    const codes = warnings.map((w) => w.code);
    expect(codes).toContain('IMPORT_DEEP_SUBTASK_FLATTENED');
    expect(codes).toContain('IMPORT_SUBTASK_DETAILS_MOVED');
    expect(items.some((i) => i.title === 'Süt')).toBe(false);
  });

  it('comments and attachments are appended to the description', () => {
    const { items, warnings } = parseImport('todoist', [ev()], ctx);
    const ali = byTitle(items, "Ali'ye yaz ali@example.com");
    expect(ali.description).toContain('Fiyat teklifi, "acil" değil\nikinci satır');
    expect(ali.description).toContain('- Bunu unutma');
    expect(ali.description).toContain('[fatura.pdf](https://files.todoist.com/x/fatura.pdf)');
    expect(ali.estimatedMinutes).toBe(30);
    expect(ali.dueAt.toISOString()).toBe('2026-10-20T11:00:00.000Z');
    expect(warnings.map((w) => w.code)).toContain('IMPORT_ATTACHMENT_LINKED');
  });

  it('dates, deadlines and recurrences', () => {
    const { items } = parseImport('todoist', [ev(), inbox()], ctx);
    const daily = byTitle(items, 'Bulaşık makinesini boşalt');
    expect(daily.recurrence.rule).toEqual({ freq: 'daily', interval: 1, end: { type: 'never' } });
    expect(daily.anchorAt.toISOString()).toBe('2026-10-16T05:00:00.000Z'); // 08:00 Istanbul
    // DEADLINE without DATE is the due date, at the default task time.
    expect(byTitle(items, 'Market alışverişi').dueAt.toISOString()).toBe(
      '2026-10-25T20:59:00.000Z',
    );
    // DEADLINE beside a DATE is kept in the note.
    expect(items.find((i) => i.title === 'Çimleri biç').description).toContain(
      'Deadline: 2026-10-30',
    );
    const odd = byTitle(items, 'Tekrar eden garip');
    expect(odd.recurrence).toBeNull();
    expect(odd.description).toContain('every 2nd weekday at 9am');
    expect(byTitle(items, 'Tohum al, sulama sistemi kur').description).toContain('"yarın"');
  });

  it('kept-in-note text follows the wizard language', () => {
    const { items } = parseImport('todoist', [ev()], { ...ctx, locale: 'tr' });
    expect(byTitle(items, 'Tekrar eden garip').description).toContain('Todoist içinden aktarıldı');
  });

  it('fingerprints are stable, ignore the date and count duplicates', () => {
    const a = parseImport('todoist', [ev()], ctx).items.map((i) => externalKey(i.key));
    const b = parseImport('todoist', [ev()], ctx).items.map((i) => externalKey(i.key));
    expect(a).toEqual(b);
    const moved = {
      name: ev().name,
      content: ev().content.replace('20 Oct 2026 14:00', '21 Oct 2026 09:00'),
    };
    expect(parseImport('todoist', [moved], ctx).items.map((i) => externalKey(i.key))).toEqual(a);
    const twins = parseImport('todoist', [ev()], ctx).items.filter(
      (i) => i.title === 'Çimleri biç',
    );
    expect(twins).toHaveLength(2);
    expect(twins[0].key).not.toBe(twins[1].key);
  });

  it('the official template shape parses: meta row, blank row, note, section', () => {
    const { items } = parseImport('todoist', [file('todoist', 'template-shape.csv')], ctx);
    expect(items.map((i) => i.title)).toEqual(['Welcome to your project', 'Recurring check-in']);
    expect(items[0].description).toContain('Here is a comment');
    expect(items[0].timezone).toBe('Europe/London');
    expect(items[1].checklist).toEqual([{ title: 'Subtask example', isDone: false }]);
    expect(items[1].recurrence).toBeNull(); // "every month" has no anchor day
  });

  it('refuses a TickTick file with the source it detected', () => {
    expect(() => parseImport('todoist', [file('ticktick', 'backup-2026-10.csv')], ctx)).toThrow(
      expect.objectContaining({ code: 'IMPORT_SOURCE_MISMATCH', detected: 'ticktick' }),
    );
    expect(() => parseImport('todoist', [{ name: 'x.csv', content: 'a,b\n1,2' }], ctx)).toThrow(
      expect.objectContaining({ code: 'IMPORT_FORMAT_UNRECOGNIZED' }),
    );
  });
});
