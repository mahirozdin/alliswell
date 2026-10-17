import { describe, it, expect } from 'vitest';
import { parseCsv, MAX_COLUMNS } from '../../src/lib/importers/csv.js';

/** OPH-371 — the record reader both importers stand on. */
describe('importers: parseCsv', () => {
  it('reads quoted commas and "" escapes', () => {
    expect(parseCsv('a,"b, c","say ""hi"""\n')).toEqual([['a', 'b, c', 'say "hi"']]);
  });

  it('accepts CRLF, LF and CR record ends, and a missing final newline', () => {
    expect(parseCsv('a,b\r\nc,d\ne,f\rg,h')).toEqual([
      ['a', 'b'],
      ['c', 'd'],
      ['e', 'f'],
      ['g', 'h'],
    ]);
  });

  it('keeps newlines inside quotes — the TickTick Status preamble is ONE record', () => {
    const text = '"Version: 7.1"\n"Status: \n0 Normal\n1 Completed\n2 Archived"\n"Title"\n';
    const records = parseCsv(text);
    expect(records).toHaveLength(3);
    expect(records[1][0]).toBe('Status: \n0 Normal\n1 Completed\n2 Archived');
  });

  it('strips a BOM and keeps Turkish text byte-exact', () => {
    const records = parseCsv('﻿ad,not\r\n"ğüşıöçİ","Iİıi"\r\n');
    expect(records[0][0]).toBe('ad');
    expect(records[1]).toEqual(['ğüşıöçİ', 'Iİıi']);
  });

  it('keeps a stray quote inside an unquoted field literally', () => {
    expect(parseCsv('5" screen,x\n')).toEqual([['5" screen', 'x']]);
  });

  it('keeps empty fields and an empty quoted last field', () => {
    expect(parseCsv('a,,""\n')).toEqual([['a', '', '']]);
  });

  it('refuses a file past the column cap', () => {
    const wide = Array.from({ length: MAX_COLUMNS + 1 }, () => 'x').join(',');
    expect(() => parseCsv(wide)).toThrow(
      expect.objectContaining({ code: 'IMPORT_FILE_TOO_LARGE' }),
    );
  });

  it('refuses a file past the record cap', () => {
    expect(() => parseCsv('x\n'.repeat(50001))).toThrow(
      expect.objectContaining({ code: 'IMPORT_FILE_TOO_LARGE', statusCode: 413 }),
    );
  });
});
