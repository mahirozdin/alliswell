import { isBlankRecord } from './csv.js';
import { isValidTimeZone, parseTodoistDate, toDueAt, wallDayOf, parseClock } from './dates.js';
import { zonedWallTimeToUtc } from '../time.js';
import { parseDay } from '../recurrence.js';
import { todoistRecurrence } from './recurrence.js';
import { composeDescription, importText } from './notes-text.js';
import { fitTitle, fold } from './shared.js';

/**
 * Todoist CSV → normalized import plan (OPH-371, ADR-0052).
 *
 * Format, from Todoist's help article 360000748525 ("Format a CSV file to
 * import into Todoist") and its official template, read on 2026-10-16:
 *
 *   TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,
 *   TIMEZONE,DURATION,DURATION_UNIT,DEADLINE,DEADLINE_LANG
 *
 * - TYPE is `task`, `section` or `note` (a comment on the task above it);
 *   a `meta` row (view_style) may come first.
 * - Labels live inside CONTENT as `@label`.
 * - PRIORITY 1 is p1, the HIGHEST; 4 is p4, the lowest.
 * - INDENT 1 is a top-level task, 2 a sub-task, 3 a sub-sub-task.
 * - DATE is the phrase the user typed, in DATE_LANG ("every Friday",
 *   "Oct 20 2026 14:00"). Exports drop a recurrence's "starting …" part.
 * - Exports carry NO task ids and NO completed tasks. A backup (Settings ›
 *   Backups) is a ZIP with one CSV per project; the app unzips it and sends
 *   each CSV as its own file, named after the project ("Name.csv" or
 *   "Name [id].csv").
 *
 * Because there are no ids, a task's identity is a fingerprint of where it
 * lives and what it is called — deliberately WITHOUT its date, so a re-export
 * after rescheduling still recognises it (ADR-0052).
 */

const PRIORITY = { 1: 'high', 2: 'medium', 3: 'low', 4: 'none' };

const LABEL = /(^|\s)@([\p{L}\p{N}_\-.]+)/gu;

/** "Ev İşleri [2203306142].csv" → "Ev İşleri"; null for the Inbox. */
export function projectNameFromFile(fileName) {
  const base = String(fileName)
    .split(/[\\/]/)
    .pop()
    .replace(/\.csv$/i, '')
    .replace(/\s*\[\d+\]\s*$/, '')
    .trim();
  if (base === '' || fold(base) === 'inbox' || fold(base) === 'gelen kutusu') return null;
  return base;
}

/** Pulls `@labels` out of a CONTENT cell. Emails (ali@example.com) stay text. */
export function extractLabels(content) {
  const labels = [];
  const title = content.replace(LABEL, (_m, lead, label) => {
    const clean = label.replace(/[.\-_]+$/, '');
    if (clean) labels.push(clean);
    return lead;
  });
  return { title: title.replace(/\s+/g, ' ').trim(), labels };
}

/** `[[file {"file_name": …, "file_url": …}]]` → a markdown link. */
function commentText(raw, warn) {
  return raw.replace(/\[\[file\s+(\{.*?\})\]\]/gs, (whole, json) => {
    try {
      const file = JSON.parse(json);
      warn('IMPORT_ATTACHMENT_LINKED', file.file_name ?? '');
      return `[${file.file_name ?? 'file'}](${file.file_url ?? ''})`;
    } catch {
      return whole;
    }
  });
}

function columnIndex(header) {
  const idx = {};
  header.forEach((cell, i) => {
    idx[cell.trim().toUpperCase()] = i;
  });
  return idx;
}

/** A recurrence's first anchor: today, at its own time or the default task time. */
function recurrenceAnchor({ time }, { tz, now, defaultTaskTime }) {
  const day = parseDay(wallDayOf(now, tz));
  const clock = time ?? parseClock(defaultTaskTime);
  return zonedWallTimeToUtc({ ...day, hour: clock.hour, minute: clock.minute }, tz);
}

export function parseTodoist(files, ctx) {
  const t = importText(ctx.locale);
  const items = [];
  const projects = new Map();
  const warnings = [];
  const occurrences = new Map();

  for (const { name: fileName, records } of files) {
    const projectName = projectNameFromFile(fileName);
    const projectKey = projectName ? `todoist|project|${fold(projectName)}` : null;
    if (projectKey && !projects.has(projectKey)) {
      projects.set(projectKey, { key: projectKey, name: projectName.slice(0, 255) });
    }

    const headerAt = records.findIndex((r) => {
      const cells = r.map((c) => c.trim().toUpperCase());
      return cells.includes('TYPE') && cells.includes('CONTENT');
    });
    const col = columnIndex(records[headerAt]);
    const cell = (record, name) => (col[name] === undefined ? '' : (record[col[name]] ?? ''));

    let section = null;
    let top = null; // the current top-level task (sub-tasks attach to it)

    for (let r = headerAt + 1; r < records.length; r += 1) {
      const record = records[r];
      const row = r + 1;
      if (isBlankRecord(record)) continue;
      const type = cell(record, 'TYPE').trim().toLowerCase();
      const content = cell(record, 'CONTENT');
      const warn = (code, value, title) =>
        warnings.push({ code, file: fileName, row, title: title ?? null, value: value ?? null });

      if (type === 'meta' || type === '') continue;
      if (type === 'section') {
        section = content.trim() || null;
        top = null;
        continue;
      }
      if (type === 'note') {
        if (!top) {
          warn('IMPORT_COMMENT_WITHOUT_TASK', content.slice(0, 80));
          continue;
        }
        const text = commentText(content, (code, v) => warn(code, v, top.title)).trim();
        if (text) top._comments.push(text.replace(/\s*\n\s*/g, ' '));
        continue;
      }
      if (type !== 'task') {
        warn('IMPORT_ROW_SKIPPED', type);
        continue;
      }

      const { title: rawTitle, labels } = extractLabels(content);
      const description = cell(record, 'DESCRIPTION').replace(/\r\n?/g, '\n').trim();
      const indent = Number.parseInt(cell(record, 'INDENT'), 10) || 1;
      const rowTz = cell(record, 'TIMEZONE').trim();
      const tz = isValidTimeZone(rowTz) ? rowTz : ctx.tz;
      const lang = cell(record, 'DATE_LANG').trim() || 'en';
      const dateText = cell(record, 'DATE').trim();
      const deadlineText = cell(record, 'DEADLINE').trim();

      if (rawTitle === '' && labels.length === 0) {
        warn('IMPORT_EMPTY_TITLE', null);
        continue;
      }
      const titleSource = rawTitle === '' ? content.trim() : rawTitle;

      // ── A sub-task: a checklist item on the top-level task (owner's rule) ──
      if (indent > 1 && top) {
        const title = fitTitle(titleSource, (code, v) => warn(code, v, top.title));
        if (indent > 2) warn('IMPORT_DEEP_SUBTASK_FLATTENED', title, top.title);
        top.checklist.push({ title, isDone: false });
        const details = [];
        if (description) details.push(description.replace(/\s*\n\s*/g, ' '));
        if (dateText) details.push(`${t.date}: ${dateText}`);
        if (labels.length) details.push(labels.map((l) => `@${l}`).join(' '));
        if (details.length) {
          top._subDetails.push(`${title}: ${details.join(' · ')}`);
          warn('IMPORT_SUBTASK_DETAILS_MOVED', title, top.title);
        }
        continue;
      }
      if (indent > 1) warn('IMPORT_ORPHAN_SUBTASK', titleSource.slice(0, 80));

      const title = fitTitle(titleSource, (code, v) => warn(code, v));
      const item = {
        kind: 'task',
        projectKey,
        title,
        priority: PRIORITY[cell(record, 'PRIORITY').trim()] ?? 'none',
        tagNames: [...labels, ...(section ? [section] : [])],
        dueAt: null,
        scheduledStartAt: null,
        scheduledEndAt: null,
        remindAt: null,
        remindMinutesBefore: null,
        timezone: tz,
        recurrence: null,
        anchorAt: null,
        checklist: [],
        completed: false,
        completedAt: null,
        estimatedMinutes: null,
        file: fileName,
        row,
        _base: description,
        _kept: [],
        _comments: [],
        _subDetails: [],
      };

      // Due date, or a recurrence.
      const dateCtx = { lang, tz, now: ctx.now };
      if (dateText) {
        if (/^(every|each|daily|weekly|monthly|yearly)\b|every\s*!/i.test(dateText)) {
          const rec = todoistRecurrence(dateText, lang);
          if (rec) {
            item.recurrence = { rule: rec.rule };
            item.anchorAt = recurrenceAnchor(rec, { ...ctx, tz });
          } else {
            item._kept.push(t.repeatKept(dateText));
            warn('IMPORT_RECURRENCE_KEPT_IN_NOTE', dateText, title);
          }
        } else {
          const parsed = parseTodoistDate(dateText, dateCtx);
          if (parsed?.unparsed) {
            item._kept.push(t.dateKept(dateText));
            warn('IMPORT_DATE_KEPT_IN_NOTE', dateText, title);
          } else if (parsed) {
            item.dueAt = toDueAt(parsed, { tz, defaultTaskTime: ctx.defaultTaskTime });
            if (parsed.relative) warn('IMPORT_RELATIVE_DATE', dateText, title);
            if (parsed.noYear) warn('IMPORT_DATE_YEAR_GUESSED', dateText, title);
          }
        }
      }
      if (deadlineText) {
        const parsed = parseTodoistDate(deadlineText, {
          ...dateCtx,
          lang: cell(record, 'DEADLINE_LANG').trim() || 'en',
        });
        if (!item.dueAt && !item.recurrence && parsed && !parsed.unparsed) {
          item.dueAt = toDueAt(parsed, { tz, defaultTaskTime: ctx.defaultTaskTime });
        } else {
          item._kept.push(t.deadline(deadlineText));
          warn('IMPORT_DEADLINE_KEPT_IN_NOTE', deadlineText, title);
        }
      }

      const duration = Number.parseInt(cell(record, 'DURATION'), 10);
      if (Number.isInteger(duration) && duration > 0) {
        const unit = cell(record, 'DURATION_UNIT').trim().toLowerCase();
        const minutes = unit.startsWith('day') ? duration * 1440 : duration;
        item.estimatedMinutes = Math.min(minutes, 100000);
      }

      // Identity: project + section + title + how many times that exact
      // triple appeared before. No date — see the header.
      const base = `todoist|task|${fold(projectName ?? '')}|${fold(section ?? '')}|${fold(title)}`;
      const n = occurrences.get(base) ?? 0;
      occurrences.set(base, n + 1);
      item.key = `${base}|${n}`;

      items.push(item);
      top = item;
    }
  }

  for (const item of items) {
    item.description = composeDescription({
      base: item._base,
      sections: [
        { title: t.subItems, lines: item._subDetails },
        { title: t.comments, lines: item._comments },
      ],
      kept: item._kept,
      source: 'todoist',
      locale: ctx.locale,
    });
    delete item._base;
    delete item._kept;
    delete item._comments;
    delete item._subDetails;
  }

  return { items, projects: [...projects.values()], warnings };
}
