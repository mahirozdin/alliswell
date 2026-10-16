import crypto from 'node:crypto';
import { foldSearchText } from '../fold.js';

/** Helpers every importer shares (OPH-371). */

export const MAX_TITLE = 500;

/** Turkish-aware comparison key for names (projects, sections, titles). */
export function fold(text) {
  return foldSearchText(String(text ?? ''));
}

/** The ledger's `external_key`: sha256 hex of the source's own identity string. */
export function externalKey(raw) {
  return crypto.createHash('sha256').update(raw, 'utf8').digest('hex');
}

/** Trims a title to the column's 500 characters, with a warning when it had to. */
export function fitTitle(title, warn) {
  const clean = title.replace(/\s+/g, ' ').trim();
  if ([...clean].length <= MAX_TITLE) return clean;
  warn('IMPORT_TITLE_TRUNCATED', clean.slice(0, 80));
  return `${[...clean].slice(0, MAX_TITLE - 1).join('')}…`;
}
