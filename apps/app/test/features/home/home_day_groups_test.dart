import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-307 — "This week" becomes one heading per day.
///
/// The report is about the eyes, not the data: *"by EACH DAY of this week …
/// for each day, the tasks are listed one by one (vertically), coz this would
/// be easier to follow"*. Home already knew which day every row belonged to —
/// `futureBucketForDay` computes it and then throws it away into one pile.
///
/// Two rules hold the split honest. **A heading means there is work on that
/// day** — empty days are not rendered as reassuring blanks, which is the same
/// rule the calendar's dots follow (OPH-185). And the split happens INSIDE the
/// bucket: the group order, the horizon and OPH-301's recession rule are
/// untouched, because this is a heading change, not a new way to group.
Task _task(String id, {DateTime? dueAt, DateTime? startAt, String? status}) =>
    Task(
      id: id,
      workspaceId: 'W1',
      title: id,
      status: status ?? 'open',
      priority: 'none',
      timezone: 'Europe/Istanbul',
      isUrgent: false,
      requiresAcknowledgement: false,
      sortOrder: 0,
      revision: 1,
      dueAt: dueAt,
      startAt: startAt,
    );

void main() {
  // Tuesday. "This week" is +2..+6, so Thursday, Friday and Saturday.
  final now = DateTime(2026, 7, 14, 9, 0);
  final thursday = DateTime(2026, 7, 16, 9);
  final saturday = DateTime(2026, 7, 18, 9);

  List<HomeGroup> weekGroups(List<Task> tasks, {DateTime? selectedDay}) =>
      groupTasksForHome(
        tasks,
        now: now,
        selectedDay: selectedDay,
      ).where((g) => g.bucket == HomeBucket.thisWeek).toList();

  test('each day of this week gets its own heading, in day order', () {
    final groups = weekGroups([
      _task('sat', dueAt: saturday),
      _task('thu', dueAt: thursday),
    ]);

    expect(groups, hasLength(2));
    expect(groups.map((g) => g.day), [
      DateTime(2026, 7, 16),
      DateTime(2026, 7, 18),
    ]);
    expect(groups.map((g) => (g.items.single as TaskItem).task.id), [
      'thu',
      'sat',
    ]);
  });

  test('a day with nothing on it gets no heading', () {
    final groups = weekGroups([
      _task('thu', dueAt: thursday),
      _task('thu2', dueAt: DateTime(2026, 7, 16, 17)),
    ]);
    // Friday is inside the week and empty. A heading over nothing reads as
    // "you are free on Friday", which is a claim this list cannot make — it
    // only knows what is scheduled.
    expect(groups, hasLength(1));
    expect(groups.single.day, DateTime(2026, 7, 16));
    expect(groups.single.items, hasLength(2));
  });

  test('the split leaves the bucket order alone', () {
    final groups = groupTasksForHome([
      _task('today', dueAt: DateTime(2026, 7, 14, 18)),
      _task('tomorrow', dueAt: DateTime(2026, 7, 15, 9)),
      _task('thu', dueAt: thursday),
      _task('sat', dueAt: saturday),
      _task('far', dueAt: DateTime(2026, 8, 5, 9)),
    ], now: now);

    // Two week days in the middle, and everything around them where it was.
    expect(groups.map((g) => g.bucket), [
      HomeBucket.today,
      HomeBucket.tomorrow,
      HomeBucket.thisWeek,
      HomeBucket.thisWeek,
      HomeBucket.next30Days,
    ]);
    expect(
      groups.last.day,
      isNull,
      reason:
          'the 30-day group stays one heap; 24 headings is a different screen',
    );
  });

  test('every day of the week recedes together while a day is selected', () {
    final groups = weekGroups([
      _task('thu', dueAt: thursday),
      _task('sat', dueAt: saturday),
    ], selectedDay: DateTime(2026, 7, 14));
    // OPH-301's rule survives the split: these are future groups, all of them.
    expect(groups.every((g) => g.dimmed), isTrue);
  });

  // OPH-372 (ADR-0053): a not-done task is filed by its plan day — its
  // "when" rolled forward to today, never later than its deadline; Overdue is
  // decided by the deadline alone, first.
  group('"when" (OPH-372)', () {
    HomeBucket? bucketOf(List<HomeGroup> groups, String id) {
      for (final group in groups) {
        for (final item in group.items) {
          if (item is TaskItem && item.task.id == id) return group.bucket;
        }
      }
      return null;
    }

    test('a started task due in five days is in Today, not This week', () {
      final groups = groupTasksForHome([
        _task(
          'started',
          startAt: DateTime(2026, 7, 13),
          dueAt: DateTime(2026, 7, 19, 17),
        ),
      ], now: now);
      expect(bucketOf(groups, 'started'), HomeBucket.today);
    });

    test('an undated task with a "when" sits on that day, not No date', () {
      final groups = groupTasksForHome([
        _task('thu', startAt: DateTime(2026, 7, 16)),
      ], now: now);
      final week = groups.where((g) => g.bucket == HomeBucket.thisWeek);
      expect(week.single.day, DateTime(2026, 7, 16));
      expect(bucketOf(groups, 'thu'), HomeBucket.thisWeek);
    });

    test('a "when" past the horizon drops out, but its day still shows it', () {
      final far = DateTime(2026, 8, 23); // +40 days
      final task = _task('far', startAt: far);
      expect(bucketOf(groupTasksForHome([task], now: now), 'far'), isNull);
      final selected = groupTasksForHome([task], now: now, selectedDay: far);
      expect(bucketOf(selected, 'far'), HomeBucket.selectedDay);
    });

    test('Overdue wins over a "when"', () {
      final groups = groupTasksForHome([
        _task(
          'late',
          startAt: DateTime(2026, 7, 14),
          dueAt: DateTime(2026, 7, 13, 9),
        ),
      ], now: now);
      expect(bucketOf(groups, 'late'), HomeBucket.overdue);
    });

    test('a "when" after the deadline files by the deadline', () {
      final groups = groupTasksForHome([
        _task('capped', startAt: DateTime(2026, 7, 25), dueAt: thursday),
      ], now: now);
      expect(bucketOf(groups, 'capped'), HomeBucket.thisWeek);
      final day = groups.firstWhere((g) => g.bucket == HomeBucket.thisWeek).day;
      expect(day, DateTime(2026, 7, 16));
    });

    test('the per-day split agrees with the bucket', () {
      final groups = weekGroups([
        _task(
          'when-sat',
          startAt: DateTime(2026, 7, 18),
          dueAt: DateTime(2026, 7, 30),
        ),
        _task('due-thu', dueAt: thursday),
      ]);
      expect(groups.map((g) => g.day), [
        DateTime(2026, 7, 16),
        DateTime(2026, 7, 18),
      ]);
      expect((groups.last.items.single as TaskItem).task.id, 'when-sat');
    });

    test('the month grid marks the "when" day of open work only', () {
      final days = daysWithTasks([
        _task(
          'a',
          startAt: DateTime(2026, 7, 20),
          dueAt: DateTime(2026, 7, 24),
        ),
        _task('done', startAt: DateTime(2026, 7, 21), status: 'completed'),
      ]);
      expect(days, {DateTime(2026, 7, 20), DateTime(2026, 7, 24)});
    });
  });

  testWidgets('the heading on screen names the day, not the bucket', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A real day inside this week, whatever day the suite runs on.
    final realNow = DateTime.now();
    final target = DateTime(
      realNow.year,
      realNow.month,
      realNow.day,
    ).add(const Duration(days: 3, hours: 9));
    final api = FakeApi()
      ..seedTask(
        title: 'Hafta içi iş',
        dueAt: target.toUtc().toIso8601String(),
      );

    SharedPreferences.setMockInitialValues({});
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The model half is covered above; this is the wiring — a `day` nobody
    // renders is a field, not a feature (§22).
    final heading = awFormatDayHeading(target, format: kAwSystemDateFormat);
    expect(find.textContaining(heading), findsOneWidget);
  });
}
