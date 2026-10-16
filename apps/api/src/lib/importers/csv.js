import { importError } from './errors.js';

/**
 * A small RFC 4180 reader for the two export formats we import (OPH-371).
 *
 * Why not "split on newlines": TickTick's backup opens with a quoted preamble
 * record that spans several lines (`"Status: \n0 Normal\n1 Completed…"`), and
 * both apps put newlines inside quoted descriptions. A line-based reader cuts
 * those in half and every column after them shifts. So this works on RECORDS.
 *
 * Accepted: quoted fields, `""` escapes, CR, LF and CRLF record ends, newlines
 * inside quotes, a leading UTF-8 BOM, a trailing newline. A stray quote inside
 * an unquoted field is kept literally ("lazy quotes"), because a hand-edited
 * CSV with `5" screen` in it should import, not fail.
 *
 * Caps: 50,000 records and 200 columns. Past them the file is refused with
 * IMPORT_FILE_TOO_LARGE instead of being half read.
 */

export const MAX_RECORDS = 50000;
export const MAX_COLUMNS = 200;

/** @returns {string[][]} */
export function parseCsv(text) {
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  const records = [];
  let record = [];
  let field = '';
  let quoted = false; // inside a quoted field
  let wasQuoted = false; // the current field started with a quote
  let i = 0;
  const n = src.length;

  const endField = () => {
    record.push(field);
    if (record.length > MAX_COLUMNS) {
      throw importError(413, 'IMPORT_FILE_TOO_LARGE', 'This file has too many columns');
    }
    field = '';
    wasQuoted = false;
  };
  const endRecord = () => {
    endField();
    records.push(record);
    if (records.length > MAX_RECORDS) {
      throw importError(413, 'IMPORT_FILE_TOO_LARGE', 'This file has too many rows');
    }
    record = [];
  };

  while (i < n) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"') {
        if (src[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        quoted = false;
        i += 1;
        continue;
      }
      field += ch;
      i += 1;
      continue;
    }
    if (ch === '"') {
      if (field === '' && !wasQuoted) {
        quoted = true;
        wasQuoted = true;
      } else {
        field += ch; // lazy quote
      }
      i += 1;
      continue;
    }
    if (ch === ',') {
      endField();
      i += 1;
      continue;
    }
    if (ch === '\r' || ch === '\n') {
      endRecord();
      i += ch === '\r' && src[i + 1] === '\n' ? 2 : 1;
      continue;
    }
    field += ch;
    i += 1;
  }
  // The last record, unless the file ended on a record break.
  if (field !== '' || record.length > 0 || wasQuoted) endRecord();
  return records;
}

/** A record with nothing in it (blank line, or only empty fields). */
export function isBlankRecord(record) {
  return record.every((cell) => cell.trim() === '');
}
