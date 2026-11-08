import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/home/board_series.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../projects/fake_api.dart';
import '../tasks/tasks_flow_test.dart' show signedInAppWith, isoAt;

/// OPH-394 — Home and the Board say what is true: a header counts what is
/// still owed (E-06), a subtask is not a row of its own (E-07), a series is
/// one card on the Board (E-25).
Task task(
  String id, {
  DateTime? due,
  bool done = false,
  String? parent,
  String? series,
  String? slot,
  String status = 'open',
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: id,
  status: done ? 'completed' : status,
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: due,
  parentTaskId: parent,
  seriesId: series,
  occurrenceDate: slot,
);

List<String> titles(HomeGroup group) => [
  for (final item in group.items) (item as TaskItem).task.title,
];

void main() {
  final now = DateTime(2026, 11, 7, 12);

  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('E-06 — Home counters', () {
    test('a header does not count finished work', () {
      final groups = groupTasksForHome([
        task('Open A'),
        task('Open B'),
        task('Done A', done: true),
        task('Done B', done: true),
      ], now: now);
      final noDate = groups.single;
      expect(noDate.bucket, HomeBucket.noDate);
      expect(noDate.items, hasLength(4), reason: 'done work stays visible');
      expect(noDate.count, 2);
    });

    test('a deadline that passed this morning is Overdue, not Today', () {
      final groups = groupTasksForHome([
        task('Morning', due: DateTime(2026, 11, 7, 7, 47)),
        task('Evening', due: DateTime(2026, 11, 7, 18)),
        task('Yesterday', due: DateTime(2026, 11, 6, 9)),
      ], now: now);
      final overdue = groups.firstWhere((g) => g.bucket == HomeBucket.overdue);
      final today = groups.firstWhere((g) => g.bucket == HomeBucket.today);
      expect(titles(overdue), ['Yesterday', 'Morning']);
      expect(overdue.count, 2);
      expect(titles(today), ['Evening']);
    });

    test('work finished this morning stays in Today, uncounted', () {
      final groups = groupTasksForHome([
        task('Done', due: DateTime(2026, 11, 7, 7), done: true),
        task('Evening', due: DateTime(2026, 11, 7, 18)),
      ], now: now);
      expect(groups.map((g) => g.bucket), [HomeBucket.today]);
      expect(groups.single.count, 1);
    });
  });

  group('E-07 — subtasks', () {
    test('a subtask whose parent is listed is not a Home row', () {
      final groups = groupTasksForHome([
        task('Parent'),
        task('Child', parent: 'Parent'),
        task('Done child', parent: 'Parent', done: true),
      ], now: now);
      expect(titles(groups.single), ['Parent']);
      expect(groups.single.count, 1);
    });

    test('an orphan subtask stays, so its work is never lost', () {
      final groups = groupTasksForHome([
        task('Child', parent: 'Elsewhere'),
      ], now: now);
      expect(titles(groups.single), ['Child']);
    });

    test('a subtask due today stays when its parent is beyond the horizon '
        '(E35 G-A review r1)', () {
      // The parent is on the list but Home drops it (45 days out): hiding
      // the child under a parent that is not shown would lose today's work.
      final groups = groupTasksForHome([
        task('Parent', due: DateTime(2026, 12, 22, 9)),
        task('Child', parent: 'Parent', due: DateTime(2026, 11, 7, 18)),
      ], now: now);
      expect(groups.map((g) => g.bucket), [HomeBucket.today]);
      expect(titles(groups.single), ['Child']);
    });

    test('a subtask stays hidden under a parent that is itself tucked under '
        'a shown grandparent', () {
      final groups = groupTasksForHome([
        task('Grandparent'),
        task('Parent', parent: 'Grandparent', due: DateTime(2026, 12, 22, 9)),
        task('Child', parent: 'Parent', due: DateTime(2026, 11, 7, 18)),
      ], now: now);
      expect(titles(groups.single), ['Grandparent']);
    });
  });

  group('E-25 — a series on the Board', () {
    test('only the next open occurrence, with the rest as +N', () {
      final entries = foldBoardSeries('open', [
        // Newest first, the way the column lists them.
        task('Rent Jan', series: 'S1', slot: '2027-01-01'),
        task('Plain'),
        task('Rent Dec', series: 'S1', slot: '2026-12-01'),
        task('Rent Nov', series: 'S1', slot: '2026-11-01'),
      ]);
      expect([for (final e in entries) e.task.id], ['Plain', 'Rent Nov']);
      expect(entries.last.moreOccurrences, 2);
      expect(entries.first.moreOccurrences, 0);
    });

    test('finished occurrences are history and all stay', () {
      final entries = foldBoardSeries('completed', [
        task('Rent Oct', series: 'S1', slot: '2026-10-01', done: true),
        task('Rent Sep', series: 'S1', slot: '2026-09-01', done: true),
      ]);
      expect(entries, hasLength(2));
    });
  });

  group('in the app', () {
    final today = DateTime(now.year, now.month, now.day);

    testWidgets('a subtask is listed in its parent\'s detail, not on Home', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FakeApi();
      final parent = api.seedTask(title: 'Plan the offsite');
      api.seedTask(
        title: 'Book the room',
        parentTaskId: parent['id'] as String,
        status: 'completed',
        completedAt: DateTime.now().toUtc().toIso8601String(),
      );
      api.seedTask(
        title: 'Send the invites',
        parentTaskId: parent['id'] as String,
      );
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();

      expect(find.text('Plan the offsite'), findsOneWidget);
      expect(find.text('Book the room'), findsNothing);
      expect(find.text('Send the invites'), findsNothing);
      // OPH-401: the header's count is its own text.
      expect(
        find.descendant(
          of: find.byKey(const Key('home-section-noDate')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Plan the offsite'));
      await tester.pumpAndSettle();

      final section = find.byKey(const Key('task-subtasks'));
      await tester.dragUntilVisible(
        section,
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: section, matching: find.text('Subtasks')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: section, matching: find.text('Book the room')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: section, matching: find.text('Send the invites')),
        findsOneWidget,
      );
    });

    testWidgets('a task without subtasks shows no Subtasks card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FakeApi()..seedTask(title: 'Alone');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alone'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-subtasks')), findsNothing);
    });

    testWidgets('the Board shows a series once, with +N and an honest count', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeApi();
      for (final months in [2, 1, 0]) {
        final due = DateTime(today.year, today.month + months, today.day, 23);
        api.seedTask(
          title: 'Invoice Acme',
          dueAt: isoAt(due),
          seriesId: 'SERIES1',
          occurrenceDate:
              '${due.year}-${due.month.toString().padLeft(2, '0')}-'
              '${due.day.toString().padLeft(2, '0')}',
        );
      }
      api.seedTask(title: 'Plain work');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      if (find.byKey(const Key('board-column-open')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('home-view-toggle')));
        await tester.pumpAndSettle();
      }

      final column = find.byKey(const Key('board-column-open'));
      expect(
        find.descendant(of: column, matching: find.text('Invoice Acme')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: column, matching: find.text('+2 next')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: column, matching: find.text('2')),
        findsOneWidget,
        reason: 'the column counts the cards it shows',
      );
    });
  });
}
