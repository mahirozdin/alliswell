import { isBlankRecord, parseCsv } from './csv.js';
import { importError } from './errors.js';
import { parseTodoist } from './todoist.js';
import { parseTicktick } from './ticktick.js';

/**
 * Importers for other apps' exports (OPH-371, ADR-0052).
 *
 * Pure: files in, a normalized plan out — no database, no clock of its own
 * (`ctx.now` is passed in), no network. src/db/app-import.js turns the plan
 * into rows through the domain layer.
 *
 * The normalized item every parser returns:
 *
 *   { key, kind: 'task'|'note', projectKey, title, description, priority,
 *     tagNames[], dueAt, scheduledStartAt, scheduledEndAt, remindAt,
 *     remindMinutesBefore, timezone, recurrence: {rule}|null, anchorAt,
 *     checklist[{title,isDone}], completed, completedAt, estimatedMinutes,
 *     markdown (notes), file, row }
 *
 * plus `projects` ({key, name}) and `warnings` ({code, file, row, title, value}).
 *
 * Apple Reminders is deliberately absent: it has no export file to read.
 */

/** The sources a caller may name. The Ajv enum and the ledger's `source` column follow it. */
export const IMPORT_SOURCES = ['todoist', 'ticktick'];

export { MAX_TITLE, fold, externalKey, fitTitle } from './shared.js';

function headerCells(record) {
  return record.map((c) => c.trim().toLowerCase());
}

/** Which app wrote this file, judged by its header. */
export function detectFormat(records) {
  for (const record of records.slice(0, 40)) {
    if (isBlankRecord(record)) continue;
    const cells = headerCells(record);
    if (cells.includes('type') && cells.includes('content')) return 'todoist';
    if (cells.includes('folder name') && cells.includes('list name') && cells.includes('title')) {
      return 'ticktick';
    }
  }
  return null;
}

/**
 * Parses every file of one import.
 *
 * @param {'todoist'|'ticktick'} source
 * @param {{name: string, content: string}[]} files
 * @param {{tz: string, now: Date, defaultTaskTime: string, locale: string}} ctx
 */
export function parseImport(source, files, ctx) {
  const parsedFiles = [];
  const warnings = [];
  const seen = new Set();
  for (const file of files) {
    const records = parseCsv(file.content);
    const format = detectFormat(records);
    seen.add(format);
    if (format === source) {
      parsedFiles.push({ name: file.name, records });
    } else {
      warnings.push({ code: 'IMPORT_FILE_SKIPPED', file: file.name, row: null, value: format });
    }
  }
  if (parsedFiles.length === 0) {
    const other = [...seen].find((f) => f && f !== source);
    if (other) {
      throw importError(
        422,
        'IMPORT_SOURCE_MISMATCH',
        `These files look like a ${other === 'ticktick' ? 'TickTick' : 'Todoist'} export`,
        { detected: other },
      );
    }
    throw importError(422, 'IMPORT_FORMAT_UNRECOGNIZED', 'This file is not a recognized export');
  }

  const result =
    source === 'todoist' ? parseTodoist(parsedFiles, ctx) : parseTicktick(parsedFiles, ctx);
  return { ...result, warnings: [...warnings, ...result.warnings] };
}
