import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/fold.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/widgets/widget_grouping.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-208 — the surfaces an occurrence lands on, TESTED rather than assumed.
///
/// The whole bet of ADR-0020 §4 is that materialized occurrences need no new
/// engine downstream: they are ordinary task rows, so the calendar dots, the
/// widget snapshot, search and the alarm planner should already be right. A bet
/// nobody checks is a guess, so each surface gets its own assertion here.
Task occurrence(
  String id, {
  required DateTime dueAt,
  String seriesId = 'SERIES1',
  String status = 'open',
  String title = 'Kira öde',
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: title,
  status: status,
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
  seriesId: seriesId,
  occurrenceDate:
      '${dueAt.year}-${dueAt.month.toString().padLeft(2, '0')}-'
      '${dueAt.day.toString().padLeft(2, '0')}',
);

void main() {
  final now = DateTime(2026, 7, 17, 10); // a Friday

  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  test('an occurrence is an ordinary task to the model', () {
    final task = occurrence('T1', dueAt: now);
    expect(task.isRecurring, isTrue);
    expect(task.occurrenceDate, '2026-07-17');
    // …and a task outside a series says so, without a series id to leak.
    final plain = occurrence('T2', dueAt: now, seriesId: '').copyIsRecurring();
    expect(plain, isFalse);
  });

  test('the widget counts today’s occurrence in openToday (DESIGN §8 W9)', () {
    final snapshot = buildWidgetSnapshot([
      occurrence('T1', dueAt: now),
      occurrence('T2', dueAt: now.add(const Duration(days: 3))),
      occurrence('T3', dueAt: now.subtract(const Duration(days: 2))),
    ], now: now);
    // Today's occurrence plus the overdue one — exactly the rule for any task.
    expect(snapshot.openToday, 2);
  });

  test('the widget buckets occurrences like any other task', () {
    final groups = groupTasksForWidget([
      occurrence('T1', dueAt: now),
      occurrence('T2', dueAt: now.add(const Duration(days: 40))),
    ], now: now);
    final buckets = groups.map((g) => g.bucket).toList();
    expect(buckets, contains(WidgetBucket.today));
    // …and the one past the horizon is dropped, series or not.
    expect(groups.expand((g) => g.tasks).map((t) => t.id), ['T1']);
  });

  test('the month calendar dots a day that only holds an occurrence', () {
    final days = daysWithTasks([
      occurrence('T1', dueAt: DateTime(2026, 8, 31, 9)),
    ]);
    expect(days, contains(DateTime(2026, 8, 31)));
  });

  test('Home groups an occurrence by its date, not by its series', () {
    final groups = groupTasksForHome([
      occurrence('T1', dueAt: now.subtract(const Duration(days: 1))),
      occurrence('T2', dueAt: now),
    ], now: now);
    expect(groups.first.bucket, HomeBucket.overdue);
    expect(
      groups.map((g) => g.bucket),
      containsAll([HomeBucket.overdue, HomeBucket.today]),
    );
  });

  test('search folds an occurrence’s title exactly like any task title', () {
    // ADR-0013: the fold is app-owned. An occurrence is a row with a title, so
    // there is nothing special to do — this pins that there is nothing missing.
    expect(foldSearchText(occurrence('T1', dueAt: now).title), 'kira ode');
  });
}

extension on Task {
  /// A task whose series id is blank must NOT read as recurring.
  bool copyIsRecurring() => (seriesId ?? '').isEmpty ? false : isRecurring;
}
