/**
 * The home-screen widget's grouping on the server (OPH-459, #50, WIDGETS
 * §3.2) — the API mirror of the app's `widget_grouping.dart`,
 * `task_when.dart` (ADR-0053) and `buildWidgetServerDays`
 * (`widget_snapshot.dart`). One rule, two runtimes: the shared fixture
 * `apps/app/test/fixtures/widget_grouping_cases.json` is written by the Dart
 * test and asserted case by case by `test/unit/widget-grouping.test.js`.
 * Change one side alone and a test fails.
 *
 * Language-free: bucket keys, raw instants and a `timeStyle` name, never a
 * label — the widget extension words them with the app's own patterns. Every
 * local day is taken in the client's IANA `tz` (lib/time.js wall-clock
 * helpers), never the server's zone.
 *
 * A local day is carried as a day number (days since 1970-01-01 on the wall
 * calendar), so day arithmetic is integer arithmetic and DST cannot shift it.
 */

import { wallClockParts, zonedWallTimeToUtc } from './time.js';

/** Bucket keys, in the order the widget draws them. */
export const WIDGET_BUCKETS = Object.freeze([
  'overdue',
  'noDate',
  'today',
  'thisWeek',
  'thisMonth',
]);

/** How far ahead the widget looks: +30 days inclusive; beyond it a row drops. */
export const WIDGET_HORIZON_DAYS = 30;

/** Rows drawn per bucket; the open rest is counted as `more`. */
export const WIDGET_ROWS_PER_BUCKET = 12;

/** Days a snapshot carries (`days` 1–3). */
export const WIDGET_SNAPSHOT_DAYS = 3;

/** The statuses the planning lists (and so the widget) show. */
export const WIDGET_PLANNING_STATUSES = Object.freeze([
  'open',
  'scheduled',
  'in_progress',
  'waiting',
]);

const DAY_MS = 86_400_000;

/** @param {Date|string|number|null|undefined} value @returns {number|null} */
function toMs(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return Date.parse(value);
}

const iso = (ms) => new Date(ms).toISOString();

/**
 * The local calendar day of an instant in `tz`, as a day number.
 * @param {Date|string|number} instant
 * @param {string} tz
 */
export function localDayOf(instant, tz) {
  const wall = wallClockParts(new Date(toMs(instant)), tz);
  return Math.round(Date.UTC(wall.year, wall.month - 1, wall.day) / DAY_MS);
}

/** A day number as `yyyy-MM-dd`. @param {number} day */
export function widgetDayKey(day) {
  return new Date(day * DAY_MS).toISOString().slice(0, 10);
}

/**
 * The instant a local day begins in `tz` (its first instant), in UTC ms.
 *
 * Usually its 00:00. Where a DST gap skips midnight (America/Santiago in
 * September, for one) 00:00 does not exist and `zonedWallTimeToUtc` resolves
 * it with the new offset, an instant that is still the previous day locally.
 * The day then begins at the transition itself — the old offset applied to
 * 00:00 — which is the first instant whose local date is `day`.
 */
export function startOfLocalDay(day, tz) {
  const date = new Date(day * DAY_MS);
  const wall = {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
  };
  const resolved = zonedWallTimeToUtc(wall, tz).getTime();
  if (localDayOf(resolved, tz) >= day) return resolved;
  // `resolved` sits before the gap, on the old offset: shift by how far its
  // wall clock is behind midnight to land on the transition.
  const behind = wallClockParts(new Date(resolved), tz);
  const behindAsUtc = Date.UTC(
    behind.year,
    behind.month - 1,
    behind.day,
    behind.hour,
    behind.minute,
    behind.second,
  );
  return resolved + (day * DAY_MS - behindAsUtc);
}

/**
 * Overdue is decided by the deadline ALONE (ADR-0053): a past "when" is not a
 * debt, it puts the task on today's list.
 */
export function taskIsOverdueOn(task, today, tz) {
  const due = toMs(task.dueAt);
  return due !== null && localDayOf(due, tz) < today;
}

/**
 * The one filing rule (ADR-0053) for a NOT-overdue task: its "when" day rolled
 * forward to `today` once reached and never later than the deadline's day;
 * without a "when", the deadline's day; with neither, null (No date).
 */
export function taskPlanDay(task, today, tz) {
  const due = toMs(task.dueAt);
  const when = toMs(task.startAt);
  const dueDay = due === null ? null : localDayOf(due, tz);
  if (when === null) return dueDay;
  let day = Math.max(localDayOf(when, tz), today);
  if (dueDay !== null && dueDay < day) day = dueDay;
  return day;
}

/** Every local day an event touches; its end is exclusive (Home's `daysOfEvent`). */
function daysOfEvent(event, tz) {
  const start = toMs(event.startsAt);
  const end = toMs(event.endsAt);
  const last = localDayOf(end > start ? end - 1 : end, tz);
  const days = [];
  for (let day = localDayOf(start, tz); day <= last; day += 1) days.push(day);
  return days;
}

const isCompleted = (task) => task.status === 'completed';

/** A row a bucket still owes: an event, or a task not yet finished. */
const isOpen = (entry) => !(entry.kind === 'task' && isCompleted(entry.task));

/**
 * Groups tasks and the calendar's events into the widget's buckets, the
 * chronological order within each (`groupTasksForWidget`). Pure: pass `now`
 * and `tz`. Only non-empty buckets come back, in {@link WIDGET_BUCKETS} order.
 *
 * Tasks: overdue = due before today; else filed on {@link taskPlanDay}: today,
 * +1…+6 this week, +7…+30 this month, beyond dropped; no date at all = noDate.
 * Events: never overdue or noDate; a finished one drops; a running one is
 * filed under the first day it touches that has not passed.
 *
 * Order: finished tasks last; by instant (a task's due, an event's start; an
 * all-day event or one begun before its day sits at that day's first minute);
 * dateless tasks after dated ones, by `sortOrder`; at the same instant the
 * event first; any other tie keeps the input order.
 *
 * @returns {{bucket: string, entries: Array<{kind: 'task', task: object} | {kind: 'event', event: object, day: number}>}[]}
 */
export function groupTasksForWidget(tasks, { now, tz, events = [] }) {
  const today = localDayOf(now, tz);
  const weekEnd = today + 7;
  const horizon = today + WIDGET_HORIZON_DAYS;
  /** @type {Record<string, object[]>} */
  const byBucket = Object.fromEntries(WIDGET_BUCKETS.map((b) => [b, []]));

  const futureBucketForDay = (day) => {
    if (day === today) return 'today';
    if (day < weekEnd) return 'thisWeek';
    if (day <= horizon) return 'thisMonth';
    return null;
  };

  for (const task of tasks) {
    if (taskIsOverdueOn(task, today, tz)) {
      byBucket.overdue.push({ kind: 'task', task });
      continue;
    }
    const day = taskPlanDay(task, today, tz);
    if (day === null) {
      byBucket.noDate.push({ kind: 'task', task });
      continue;
    }
    const bucket = futureBucketForDay(day);
    if (bucket) byBucket[bucket].push({ kind: 'task', task });
  }

  for (const event of events) {
    const day = daysOfEvent(event, tz).find((d) => d >= today);
    if (day === undefined) continue; // finished: history, not the widget
    const bucket = futureBucketForDay(day);
    if (bucket) byBucket[bucket].push({ kind: 'event', event, day });
  }

  const dayStarts = new Map();
  const dayStart = (day) => {
    if (!dayStarts.has(day)) dayStarts.set(day, startOfLocalDay(day, tz));
    return dayStarts.get(day);
  };
  const at = (entry) => {
    if (entry.kind === 'task') return toMs(entry.task.dueAt);
    const start = toMs(entry.event.startsAt);
    const first = dayStart(entry.day);
    return entry.event.allDay || start < first ? first : start;
  };
  const done = (entry) => entry.kind === 'task' && isCompleted(entry.task);

  const chronologically = (a, b) => {
    if (done(a) !== done(b)) return done(a) ? 1 : -1;
    const da = at(a);
    const db = at(b);
    if (da === null && db === null) {
      const sa = a.kind === 'task' ? (a.task.sortOrder ?? 0) : 0;
      const sb = b.kind === 'task' ? (b.task.sortOrder ?? 0) : 0;
      return sa - sb;
    }
    if (da === null) return 1;
    if (db === null) return -1;
    if (da !== db) return da - db;
    const ea = a.kind === 'event';
    const eb = b.kind === 'event';
    if (ea !== eb) return ea ? -1 : 1;
    return 0;
  };

  return WIDGET_BUCKETS.filter((bucket) => byBucket[bucket].length > 0).map((bucket) => ({
    bucket,
    // Array.prototype.sort is stable: a tie keeps the input order.
    entries: byBucket[bucket].sort(chronologically),
  }));
}

/**
 * The lock screen's "next": the first OPEN task in the order overdue, today,
 * this week, this month, then the dateless ones. Null when nothing is open.
 */
export function nextTaskForWidget(groups) {
  const order = ['overdue', 'today', 'thisWeek', 'thisMonth', 'noDate'];
  for (const bucket of order) {
    const group = groups.find((g) => g.bucket === bucket);
    if (!group) continue;
    for (const entry of group.entries) {
      if (entry.kind === 'task' && !isCompleted(entry.task)) return { task: entry.task, bucket };
    }
  }
  return null;
}

/**
 * A task row's time style (`widgetTaskTimeStyle`): `time` for a Today row due
 * on the view's day, `day` for any other dated task, null for a dateless one.
 */
export function widgetTaskTimeStyle(task, bucket, viewDay, tz) {
  const due = toMs(task.dueAt);
  if (due === null) return null;
  if (bucket === 'today' && localDayOf(due, tz) === viewDay) return 'time';
  return 'day';
}

/**
 * An event row's time style (`widgetEventTimeStyle`); `day` is the day it is
 * filed under. Today: `allDay`, `range`, `start` or `end`; elsewhere `day`
 * for an all-day event, `dayTime` for a timed one.
 */
export function widgetEventTimeStyle(event, day, bucket, tz) {
  if (bucket === 'today') {
    if (event.allDay) return 'allDay';
    const startsToday = localDayOf(event.startsAt, tz) === day;
    const endsToday = localDayOf(event.endsAt, tz) === day;
    if (startsToday && endsToday) return 'range';
    if (startsToday) return 'start';
    return 'end';
  }
  return event.allDay ? 'day' : 'dayTime';
}

/** Whether a scope shows the calendar: one workspace's own, and never in a `mine` scope. */
export function scopeShowsEvents(scope) {
  return !scope.mineFor && scope.workspaceIds.length === 1;
}

/**
 * The widget's task selection over rows already in memory — the app's
 * `watchOpenIn(scope, completedSince: start of today)`: in the scope's
 * workspaces; a planning status, or completed today and not due before
 * today; with `mineFor`, assigned to that user, or created by them with
 * nobody assigned and not a request's work task (`isRequestWork`). Newest id
 * first, the input order the grouping's ties keep.
 *
 * Rows carry `assignees` (user ids). The route may select in SQL instead; this
 * is the rule it must equal.
 */
export function selectWidgetTasks(tasks, { scope, now, tz }) {
  const since = startOfLocalDay(localDayOf(now, tz), tz);
  const me = scope.mineFor ?? null;
  const mine = (task) => {
    const assignees = task.assignees ?? [];
    if (assignees.includes(me)) return true;
    return task.createdBy === me && assignees.length === 0 && !task.isRequestWork;
  };
  const live = (task) => {
    if (WIDGET_PLANNING_STATUSES.includes(task.status)) return true;
    if (task.status !== 'completed') return false;
    const completed = toMs(task.completedAt);
    const due = toMs(task.dueAt);
    return completed !== null && completed >= since && (due === null || due >= since);
  };
  return tasks
    .filter((task) => scope.workspaceIds.includes(task.workspaceId))
    .filter((task) => me === null || mine(task))
    .filter(live)
    .sort((a, b) => (a.id < b.id ? 1 : a.id > b.id ? -1 : 0));
}

/** An event's title: its summary, the app's fallback when it has none. */
const eventTitle = (event) => (event.summary ? event.summary : '(Untitled)');

/**
 * `GET /widget/snapshot`'s `days` (WIDGETS §3.2): for each of `days` local
 * days, the whole list and every non-archived project's view, built by the
 * same grouping, counts, 12-row cap and time rules as the app's
 * `buildWidgetServerDays`.
 *
 * - `tasks`: the selection ({@link selectWidgetTasks}), newest id first.
 * - `events`: the scope's calendar (empty unless {@link scopeShowsEvents}),
 *   by start; they join the whole list only.
 * - `projects`: the scope's projects (`id`, `colorRgb`, `status`), list order.
 * - `private` (default true, fail-closed) leaves every `title` key out.
 *
 * Day 0 is seen from `now`; a later day from its first minute, and keeps only
 * tasks completed on or after it.
 */
export function buildWidgetServerDays(
  tasks,
  {
    events = [],
    projects = [],
    now,
    tz,
    private: hideTitles = true,
    days = WIDGET_SNAPSHOT_DAYS,
    rowsPerBucket = WIDGET_ROWS_PER_BUCKET,
  },
) {
  const nowMs = toMs(now);
  // Events by start (stable: equal starts keep the caller's order).
  const calendar = [...events].sort((a, b) => toMs(a.startsAt) - toMs(b.startsAt));
  const colorById = new Map(projects.map((p) => [p.id, p.colorRgb ?? null]));
  const listable = projects.filter((p) => p.status !== 'archived');
  const colorOf = (task) =>
    task.projectId ? (colorById.get(task.projectId) ?? null) : (task.colorRgb ?? null);

  const list = (listTasks, listEvents, viewMs) => {
    const viewDay = localDayOf(viewMs, tz);
    const groups = groupTasksForWidget(listTasks, { now: viewMs, tz, events: listEvents });

    const item = (entry, bucket) => {
      if (entry.kind === 'task') {
        const { task } = entry;
        const color = colorOf(task);
        const due = toMs(task.dueAt);
        const style = widgetTaskTimeStyle(task, bucket, viewDay, tz);
        return {
          id: task.id,
          done: isCompleted(task),
          priority: task.priority,
          ...(hideTitles ? {} : { title: task.title }),
          ...(color ? { projectColor: color } : {}),
          ...(due !== null ? { dueAt: iso(due) } : {}),
          ...(style ? { timeStyle: style } : {}),
        };
      }
      const { event, day } = entry;
      return {
        id: event.id,
        done: false,
        priority: 'none',
        ...(hideTitles ? {} : { title: eventTitle(event) }),
        kind: 'event',
        day: widgetDayKey(day),
        dueAt: iso(toMs(event.startsAt)),
        endAt: iso(toMs(event.endsAt)),
        allDay: Boolean(event.allDay),
        timeStyle: widgetEventTimeStyle(event, day, bucket, tz),
      };
    };

    let openToday = 0;
    for (const group of groups) {
      if (group.bucket !== 'overdue' && group.bucket !== 'today') continue;
      for (const entry of group.entries) {
        if (entry.kind === 'task' && !isCompleted(entry.task)) openToday += 1;
      }
    }

    const picked = nextTaskForWidget(groups);
    let next;
    if (picked) {
      const due = toMs(picked.task.dueAt);
      const style = widgetTaskTimeStyle(picked.task, picked.bucket, viewDay, tz);
      next = {
        id: picked.task.id,
        ...(hideTitles ? {} : { title: picked.task.title }),
        bucket: picked.bucket,
        ...(due !== null ? { dueAt: iso(due) } : {}),
        ...(style ? { timeStyle: style } : {}),
      };
    }

    return {
      openToday,
      ...(next ? { next } : {}),
      buckets: groups.map((group) => {
        const more = group.entries.slice(rowsPerBucket).filter(isOpen).length;
        return {
          key: group.bucket,
          count: group.entries.filter(isOpen).length,
          ...(more > 0 ? { more } : {}),
          items: group.entries.slice(0, rowsPerBucket).map((entry) => item(entry, group.bucket)),
        };
      }),
    };
  };

  const today = localDayOf(nowMs, tz);
  const out = [];
  for (let d = 0; d < days; d += 1) {
    const viewMs = d === 0 ? nowMs : startOfLocalDay(today + d, tz);
    // A task finished today is today's dimmed row, not a later day's.
    const dayTasks =
      d === 0
        ? tasks
        : tasks.filter((task) => {
            if (!isCompleted(task)) return true;
            const completed = toMs(task.completedAt);
            return completed !== null && completed >= viewMs;
          });
    const views = {};
    for (const project of listable) {
      views[project.id] = list(
        dayTasks.filter((task) => task.projectId === project.id),
        [],
        viewMs,
      );
    }
    out.push({ date: widgetDayKey(today + d), ...list(dayTasks, calendar, viewMs), views });
  }
  return out;
}
