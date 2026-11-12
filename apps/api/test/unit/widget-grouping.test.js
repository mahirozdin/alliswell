import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, it, expect } from 'vitest';
import {
  buildWidgetServerDays,
  groupTasksForWidget,
  scopeShowsEvents,
  selectWidgetTasks,
  taskIsOverdueOn,
  taskPlanDay,
  localDayOf,
  widgetDayKey,
} from '../../src/lib/widget-grouping.js';

/**
 * OPH-459 (#50, WIDGETS §3.2) — the JS half of the widget grouping pair. Dart
 * writes the fixture (apps/app/test/features/widgets/widget_core_test.dart,
 * OPH-463, from `readWidgetReplica` + `buildWidgetServerDays`); this suite only
 * reads it. Change one side alone and the other fails (the fold/recurrence/
 * project-match model).
 */

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../app/test/fixtures/widget_grouping_cases.json',
);
const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));

/** A case through the server's path: select, then build the days. */
function runCase(testCase) {
  const now = new Date(testCase.now);
  const { scope, tz } = testCase;
  const inScope = (row) => scope.workspaceIds.includes(row.workspaceId);
  const selected = selectWidgetTasks(testCase.tasks, { scope, now, tz });
  // The calendar of the one workspace, by start — what the route reads.
  const events = scopeShowsEvents(scope) ? (testCase.events ?? []).filter(inScope) : [];
  const days = buildWidgetServerDays(selected, {
    events,
    projects: testCase.projects.filter(inScope),
    now,
    tz,
    private: testCase.private,
  });
  return { selected: selected.map((task) => task.id), days };
}

describe('widget grouping parity fixture', () => {
  it('the fixture is the WIDGETS 3.2 one and has cases', () => {
    expect(fixture.contract).toMatch(/WIDGETS\.md 3\.2/);
    expect(fixture.cases.length).toBeGreaterThanOrEqual(14);
  });

  describe('server grouping matches the shared fixture', () => {
    for (const testCase of fixture.cases) {
      it(testCase.name, () => {
        const result = runCase(testCase);
        expect(result.selected).toEqual(testCase.expected.selected);
        expect(result.days).toEqual(testCase.expected.days);
      });
    }
  });
});

describe('widget grouping semantics beyond the fixture', () => {
  const tz = 'Europe/Istanbul';
  const now = new Date('2026-11-12T07:00:00.000Z'); // 10:00 in Istanbul
  const task = (id, extra = {}) => ({
    id,
    workspaceId: 'W1',
    title: `Task ${id}`,
    status: 'open',
    priority: 'none',
    sortOrder: 0,
    ...extra,
  });

  it('a local day is the tz one, not the UTC one', () => {
    // 22:30 UTC on the 12th is already the 13th in Istanbul.
    const day = localDayOf(new Date('2026-11-12T22:30:00.000Z'), tz);
    expect(widgetDayKey(day)).toBe('2026-11-13');
    expect(widgetDayKey(localDayOf(new Date('2026-11-12T22:30:00.000Z'), 'UTC'))).toBe(
      '2026-11-12',
    );
  });

  it('overdue is the deadline alone; a past "when" files the task today', () => {
    const today = localDayOf(now, tz);
    const late = task('A', { dueAt: '2026-11-11T06:00:00.000Z' });
    const pastWhen = task('B', { startAt: '2026-11-09T21:00:00.000Z' });
    expect(taskIsOverdueOn(late, today, tz)).toBe(true);
    expect(taskIsOverdueOn(pastWhen, today, tz)).toBe(false);
    expect(taskPlanDay(pastWhen, today, tz)).toBe(today);
    // A "when" after the deadline: the deadline's day wins.
    const capped = task('C', {
      dueAt: '2026-11-14T09:00:00.000Z',
      startAt: '2026-11-19T21:00:00.000Z',
    });
    expect(widgetDayKey(taskPlanDay(capped, today, tz))).toBe('2026-11-14');
  });

  it('beyond +30 a task drops; a later day keeps only work finished on it', () => {
    const groups = groupTasksForWidget([task('F', { dueAt: '2026-12-20T09:00:00.000Z' })], {
      now,
      tz,
    });
    expect(groups).toEqual([]);
    const done = task('D', {
      status: 'completed',
      dueAt: '2026-11-12T09:00:00.000Z',
      completedAt: '2026-11-12T08:00:00.000Z',
    });
    const days = buildWidgetServerDays([done], { now, tz, private: false });
    expect(days[0].buckets[0].items[0]).toMatchObject({ id: 'D', done: true });
    expect(days[0].openToday).toBe(0);
    expect(days[1].buckets).toEqual([]);
  });

  it('private is the default: no title key anywhere', () => {
    const days = buildWidgetServerDays([task('P', { dueAt: '2026-11-12T09:00:00.000Z' })], {
      now,
      tz,
      events: [
        {
          id: 'E',
          summary: 'Secret meeting',
          startsAt: '2026-11-12T11:00:00.000Z',
          endsAt: '2026-11-12T12:00:00.000Z',
          allDay: false,
        },
      ],
    });
    expect(JSON.stringify(days)).not.toMatch(/"title"|Secret|Task P/);
  });

  it('days is 1 to 3, day 0 first', () => {
    expect(buildWidgetServerDays([], { now, tz, days: 1 }).map((d) => d.date)).toEqual([
      '2026-11-12',
    ]);
    expect(buildWidgetServerDays([], { now, tz }).map((d) => d.date)).toEqual([
      '2026-11-12',
      '2026-11-13',
      '2026-11-14',
    ]);
  });

  it("mine = assigned to me, or made by me with nobody on it and not a request's work", () => {
    const scope = { workspaceIds: ['W1'], mineFor: 'U1' };
    const rows = [
      task('A1', { assignees: ['U1'] }),
      task('A2', { createdBy: 'U1' }),
      task('A3', { createdBy: 'U1', assignees: ['U2'] }),
      task('A4', { createdBy: 'U1', isRequestWork: true }),
      task('A5', { createdBy: 'U2' }),
    ];
    expect(selectWidgetTasks(rows, { scope, now, tz }).map((t) => t.id)).toEqual(['A2', 'A1']);
    expect(scopeShowsEvents(scope)).toBe(false);
    expect(scopeShowsEvents({ workspaceIds: ['W1'] })).toBe(true);
    expect(scopeShowsEvents({ workspaceIds: ['W1', 'W2'] })).toBe(false);
  });
});
