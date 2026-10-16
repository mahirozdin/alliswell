import { isBlankRecord } from './csv.js';
import { isValidTimeZone, parseInstant, toDueAt, wallDayOf } from './dates.js';
import { rruleToRule } from './recurrence.js';
import { composeDescription, importText } from './notes-text.js';
import { fitTitle, fold } from './shared.js';

/**
 * TickTick backup CSV → normalized import plan (OPH-371, ADR-0052).
 *
 * Format: web app › Settings › Backup & Import › Generate backup. Checked on
 * 2026-10-16 against a real 2026-03 backup published as a gist and against
 * Vikunja's TickTick importer fixtures:
 *
 * - optional UTF-8 BOM, then a preamble of quoted records — "Date: …",
 *   "Version: 7.1" and a "Status: \n0 Normal\n1 Completed\n2 Archived" record
 *   that spans several LINES (csv.js reads records for exactly this reason);
 * - then the header, matched BY NAME so a column TickTick adds later is
 *   tolerated: Folder Name, List Name, Title, Kind, Tags, Content,
 *   Is Check list, Start Date, Due Date, Reminder, Repeat, Priority, Status,
 *   Created Time, Completed Time, Order, Timezone, Is All Day, Is Floating,
 *   Column Name, Column Order, View Mode, taskId, parentId;
 * - Kind TEXT | CHECKLIST | NOTE; checklist lines start with ▫ (open) or
 *   ▪ (done), separated by `\r`;
 * - Priority 0 none, 1 low, 3 medium, 5 high; Status 0 open, 1 completed,
 *   2 archived;
 * - all-day dates are the zone's local midnight written in UTC;
 * - Reminder is an ISO-8601 duration (`-PT15M`, sometimes `TRIGGER:-PT15M`);
 * - parentId names another row's taskId — and a child may come BEFORE its
 *   parent, so parents are resolved in a second pass.
 */

const PRIORITY = { 5: 'high', 3: 'medium', 1: 'low', 0: 'none' };
const COLUMNS = [
  'Folder Name',
  'List Name',
  'Title',
  'Kind',
  'Tags',
  'Content',
  'Is Check list',
  'Start Date',
  'Due Date',
  'Reminder',
  'Repeat',
  'Priority',
  'Status',
  'Completed Time',
  'Timezone',
  'Is All Day',
  'Is Floating',
  'Column Name',
  'taskId',
  'parentId',
];

const truthy = (v) => /^(true|y|yes|1)$/i.test(String(v ?? '').trim());

const DURATION = /([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?/;

/** The first ISO-8601 duration in a Reminder cell → signed minutes, or null. */
export function reminderMinutes(value) {
  const text = String(value ?? '').trim();
  if (text === '') return null;
  const m = DURATION.exec(text.replace(/^TRIGGER:/i, ''));
  if (!m || m[0] === 'P' || m[0].replace(/[+-]/, '') === 'P') return null;
  const minutes =
    Number(m[2] ?? 0) * 10080 +
    Number(m[3] ?? 0) * 1440 +
    Number(m[4] ?? 0) * 60 +
    Number(m[5] ?? 0) +
    Math.floor(Number(m[6] ?? 0) / 60);
  return m[1] === '-' && minutes > 0 ? -minutes : minutes;
}

export function parseTicktick(files, ctx) {
  const t = importText(ctx.locale);
  const warnings = [];
  const rows = [];

  for (const { name: fileName, records } of files) {
    const headerAt = records.findIndex((r) => {
      const cells = r.map((c) => c.trim().toLowerCase());
      return (
        cells.includes('folder name') && cells.includes('list name') && cells.includes('title')
      );
    });
    const idx = {};
    records[headerAt].forEach((c, i) => {
      idx[c.trim().toLowerCase()] = i;
    });
    for (let r = headerAt + 1; r < records.length; r += 1) {
      if (isBlankRecord(records[r])) continue;
      const get = {};
      for (const name of COLUMNS) {
        const i = idx[name.toLowerCase()];
        get[name] = i === undefined ? '' : (records[r][i] ?? '');
      }
      rows.push({ file: fileName, row: r + 1, get });
    }
  }

  // Lists that share a name across folders keep the folder in their name.
  const foldersByList = new Map();
  for (const { get } of rows) {
    const list = fold(get['List Name']);
    if (!foldersByList.has(list)) foldersByList.set(list, new Set());
    foldersByList.get(list).add(get['Folder Name'].trim());
  }
  const projects = new Map();
  const flattenedWarned = new Set();

  const items = [];
  const byTaskId = new Map();

  for (const { file, row, get } of rows) {
    const warn = (code, value, title) =>
      warnings.push({ code, file, row, title: title ?? null, value: value ?? null });

    const rawTitle = get.Title.trim();
    if (rawTitle === '') {
      warn('IMPORT_EMPTY_TITLE', null);
      continue;
    }
    const title = fitTitle(rawTitle, (code, v) => warn(code, v));

    // ── Project: the list, flattened out of its folder ──
    const listName = get['List Name'].trim();
    const folder = get['Folder Name'].trim();
    let projectKey = null;
    if (listName !== '' && fold(listName) !== 'inbox') {
      projectKey = `ticktick|project|${fold(folder)}|${fold(listName)}`;
      if (!projects.has(projectKey)) {
        const clash = foldersByList.get(fold(listName)).size > 1;
        const name = clash && folder ? `${listName} (${folder})` : listName;
        projects.set(projectKey, { key: projectKey, name: name.slice(0, 255) });
        if (clash && !flattenedWarned.has(projectKey)) {
          flattenedWarned.add(projectKey);
          warn('IMPORT_FOLDER_FLATTENED', name);
        }
      }
    }

    const rowTz = get.Timezone.trim();
    const tz = !truthy(get['Is Floating']) && isValidTimeZone(rowTz) ? rowTz : ctx.tz;
    const allDay = truthy(get['Is All Day']);
    const status = get.Status.trim();
    const completed = status === '1' || status === '2';
    const tags = get.Tags.split(',')
      .map((s) => s.trim().replace(/^#/, ''))
      .filter(Boolean);
    const column = get['Column Name'].trim();
    if (column !== '' && fold(column) !== 'not sectioned') tags.push(column);

    const content = get.Content.replace(/\r\n?/g, '\n');
    const kind = get.Kind.trim().toUpperCase() || 'TEXT';
    const taskId = get.taskId.trim();
    const key = taskId
      ? `ticktick|task|${taskId}`
      : `ticktick|task|${fold(folder)}|${fold(listName)}|${fold(title)}|row${row}`;

    if (kind === 'NOTE') {
      items.push({
        kind: 'note',
        key,
        projectKey,
        title,
        markdown: content.trim(),
        tagNames: tags,
        completed: false,
        file,
        row,
      });
      continue;
    }

    // ── Body and checklist ──
    const checklist = [];
    const bodyLines = [];
    const isChecklist = kind === 'CHECKLIST' || truthy(get['Is Check list']);
    for (const line of content.split('\n')) {
      const m = /^\s*([▫▪])\s?(.*)$/.exec(line);
      if (isChecklist && m) {
        if (m[2].trim()) {
          checklist.push({ title: fitTitle(m[2], () => {}), isDone: m[1] === '▪' });
        }
      } else {
        bodyLines.push(line);
      }
    }
    const kept = [];

    // ── Dates ──
    const start = parseInstant(get['Start Date'], { tz });
    const due = parseInstant(get['Due Date'], { tz });
    for (const [name, raw, parsed] of [
      ['Start Date', get['Start Date'], start],
      ['Due Date', get['Due Date'], due],
    ]) {
      const text = raw.trim();
      if (text !== '' && !parsed && !/^0001-/.test(text)) {
        warn('IMPORT_DATE_KEPT_IN_NOTE', `${name}: ${text}`, title);
        kept.push(t.dateKept(text));
      }
    }
    let dueAt = null;
    let scheduledStartAt = null;
    let scheduledEndAt = null;
    let dueIsTimed = false;
    const target = due ?? start;
    if (target) {
      const dateOnly = (p) => ({
        kind: 'date',
        day: p.kind === 'date' ? p.day : wallDayOf(p.instant, tz),
      });
      if (allDay || target.kind === 'date') {
        dueAt = toDueAt(dateOnly(target), { tz, defaultTaskTime: ctx.defaultTaskTime });
        if (start && due && dateOnly(start).day !== dateOnly(due).day) {
          warn('IMPORT_MULTIDAY_FLATTENED', `${dateOnly(start).day} → ${dateOnly(due).day}`, title);
        }
      } else {
        dueAt = target.instant;
        dueIsTimed = true;
        if (start?.kind === 'datetime' && due?.kind === 'datetime' && start.instant < due.instant) {
          scheduledStartAt = start.instant;
          scheduledEndAt = due.instant;
        }
      }
    }

    // ── Reminder: only for an open task with a timed due date in the future ──
    let remindAt = null;
    let remindMinutesBefore = null;
    const reminderText = get.Reminder.trim();
    if (reminderText !== '') {
      const minutes = reminderMinutes(reminderText);
      const extra = reminderText.split(',').filter((s) => s.trim()).length > 1;
      if (minutes !== null && minutes <= 0 && dueIsTimed && !completed) {
        remindMinutesBefore = Math.abs(minutes);
        const at = new Date(dueAt.getTime() + minutes * 60000);
        if (at.getTime() > ctx.now.getTime()) remindAt = at;
        if (extra) warn('IMPORT_EXTRA_REMINDERS_DROPPED', reminderText, title);
      } else if (!completed) {
        warn('IMPORT_REMINDER_NOT_CONVERTED', reminderText, title);
        kept.push(t.reminderKept(reminderText));
      }
    }

    // ── Repeat ──
    let recurrence = null;
    let anchorAt = null;
    const repeatText = get.Repeat.trim();
    if (repeatText !== '' && !completed) {
      const rule = rruleToRule(repeatText);
      if (rule && dueAt) {
        recurrence = { rule };
        anchorAt = dueAt;
      } else {
        warn('IMPORT_RECURRENCE_KEPT_IN_NOTE', repeatText, title);
        kept.push(t.repeatKept(repeatText.replace(/^RRULE:/i, '')));
      }
    }

    const item = {
      kind: 'task',
      key,
      projectKey,
      title,
      priority: PRIORITY[get.Priority.trim()] ?? 'none',
      tagNames: tags,
      dueAt,
      scheduledStartAt,
      scheduledEndAt,
      remindAt,
      remindMinutesBefore,
      timezone: tz,
      recurrence,
      anchorAt,
      checklist,
      completed,
      completedAt: completed
        ? (parseInstant(get['Completed Time'], { tz })?.instant ?? null)
        : null,
      estimatedMinutes: null,
      file,
      row,
      _taskId: taskId,
      _parentId: get.parentId.trim(),
      _base: bodyLines.join('\n').trim(),
      _kept: kept,
      _subDetails: [],
    };
    items.push(item);
    if (taskId) byTaskId.set(taskId, item);
  }

  // ── Second pass: children become checklist items of their root parent ──
  const rootOf = (item) => {
    let cursor = item;
    const seen = new Set();
    let depth = 0;
    while (cursor._parentId && byTaskId.has(cursor._parentId) && !seen.has(cursor)) {
      seen.add(cursor);
      cursor = byTaskId.get(cursor._parentId);
      depth += 1;
    }
    return { root: cursor, depth };
  };
  const absorbed = new Set();
  for (const item of items) {
    if (item.kind !== 'task' || !item._parentId) continue;
    if (!byTaskId.has(item._parentId) || byTaskId.get(item._parentId).kind !== 'task') {
      warnings.push({
        code: 'IMPORT_ORPHAN_SUBTASK',
        file: item.file,
        row: item.row,
        title: item.title,
        value: null,
      });
      continue;
    }
    const { root, depth } = rootOf(item);
    if (root === item) continue; // a cycle: leave it standalone
    absorbed.add(item);
    root.checklist.push({ title: item.title, isDone: item.completed });
    for (const c of item.checklist) root.checklist.push(c);
    const w = (code, value) =>
      warnings.push({ code, file: item.file, row: item.row, title: root.title, value });
    if (depth > 1) w('IMPORT_DEEP_SUBTASK_FLATTENED', item.title);
    const details = [];
    if (item._base) details.push(item._base.replace(/\s*\n\s*/g, ' '));
    if (item.dueAt) details.push(`${t.date}: ${item.dueAt.toISOString().slice(0, 16)}Z`);
    if (details.length) {
      root._subDetails.push(`${item.title}: ${details.join(' · ')}`);
      w('IMPORT_SUBTASK_DETAILS_MOVED', item.title);
    }
  }

  const out = [];
  for (const item of items) {
    if (absorbed.has(item)) continue;
    if (item.kind === 'task') {
      item.description = composeDescription({
        base: item._base,
        sections: [{ title: t.subItems, lines: item._subDetails }],
        kept: item._kept,
        source: 'ticktick',
        locale: ctx.locale,
      });
      for (const k of ['_taskId', '_parentId', '_base', '_kept', '_subDetails']) delete item[k];
    }
    out.push(item);
  }
  return { items: out, projects: [...projects.values()], warnings };
}
