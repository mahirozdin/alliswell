import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/widgets/widget_grouping.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-185 / OPH-186 — completing is feedback, not disappearance
/// (DESIGN §20 C1/C4). The query layer, without any widgets.
void main() {
  late AwDatabase db;
  late TaskStore store;
  const ws = 'W1';

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    store = TaskStore(db, () {});
  });
  tearDown(() => db.close());

  /// A completed task whose `completed_at` we control — the whole point is the
  /// day boundary, so the test has to be able to put a task on either side.
  Future<String> completedAt(String title, DateTime when) async {
    final id = await store.create(ws, {'title': title});
    await store.complete(id);
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(completedAt: Value(when.toUtc())),
    );
    return id;
  }

  group('watchOpen', () {
    test(
      'keeps a task completed today, drops one completed yesterday',
      () async {
        final now = DateTime(2026, 7, 28, 14, 30);
        final dayStart = awStartOfDay(now);
        await store.create(ws, {'title': 'Açık'});
        await completedAt(
          'Bugün bitti',
          now.subtract(const Duration(hours: 2)),
        );
        await completedAt(
          'Dün bitti',
          dayStart.subtract(const Duration(hours: 1)),
        );

        final open = await store.watchOpen(ws, completedSince: dayStart).first;
        expect(open.map((t) => t.title), containsAll(['Açık', 'Bugün bitti']));
        expect(open.map((t) => t.title), isNot(contains('Dün bitti')));
      },
    );

    test(
      'exactly at midnight counts as today — the boundary is inclusive',
      () async {
        final dayStart = DateTime(2026, 7, 28);
        await completedAt('Gece yarısı', dayStart);
        final open = await store.watchOpen(ws, completedSince: dayStart).first;
        expect(open.map((t) => t.title), ['Gece yarısı']);
      },
    );

    test(
      'no boundary → the old behaviour: terminal statuses stay hidden',
      () async {
        await completedAt('Bitti', DateTime(2026, 7, 28, 10));
        expect(await store.watchOpen(ws).first, isEmpty);
      },
    );

    test('cancelled and archived never come back, boundary or not', () async {
      final cancelled = await store.create(ws, {'title': 'İptal'});
      await store.update(cancelled, {'status': 'cancelled'});
      final archived = await store.create(ws, {'title': 'Arşiv'});
      await store.update(archived, {'status': 'archived'});

      final open = await store
          .watchOpen(ws, completedSince: DateTime(2020))
          .first;
      expect(open, isEmpty);
    });

    test('the project tab follows the same rule', () async {
      const project = 'P1';
      final dayStart = DateTime(2026, 7, 28);
      final id = await store.create(ws, {
        'title': 'Proje işi',
        'projectId': project,
      });
      await store.complete(id);
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          completedAt: Value(dayStart.add(const Duration(hours: 9)).toUtc()),
        ),
      );

      final rows = await store
          .watchProjectTasks(ws, project, completedSince: dayStart)
          .first;
      expect(rows.map((t) => t.title), ['Proje işi']);
    });
  });

  group('watchCompleted (the archive)', () {
    /// The user's rule: the task's own date when it has one, otherwise the
    /// completion time — newest first.
    test('sorts by dueAt when present, completedAt when not', () async {
      // Finished in one order, DATED in another: only the sort key can tell
      // them apart, so a test that used a single instant would pass either way.
      final a = await store.create(ws, {
        'title': 'Tarihli eski',
        'dueAt': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
      });
      await store.complete(a);
      final b = await store.create(ws, {
        'title': 'Tarihli yeni',
        'dueAt': DateTime.utc(2026, 7, 20, 9).toIso8601String(),
      });
      await store.complete(b);
      final c = await completedAt('Tarihsiz', DateTime.utc(2026, 7, 10, 9));

      final rows = await store.watchCompleted(ws, limit: 10).first;
      expect(rows.map((t) => t.title), [
        'Tarihli yeni', // due 20 Jul
        'Tarihsiz', // completed 10 Jul
        'Tarihli eski', // due 1 Jul
      ]);
      expect(rows.map((t) => t.id), containsAll([a, b, c]));
    });

    test('pages: a bigger limit is a superset with the same prefix', () async {
      for (var i = 0; i < 5; i++) {
        await completedAt('T$i', DateTime.utc(2026, 7, i + 1, 9));
      }
      final firstPage = await store.watchCompleted(ws, limit: 2).first;
      final bigger = await store.watchCompleted(ws, limit: 4).first;

      expect(firstPage, hasLength(2));
      expect(bigger, hasLength(4));
      // Growing the window must not reshuffle what the user already read.
      expect(bigger.take(2).map((t) => t.id), firstPage.map((t) => t.id));
    });

    test('only completed tasks — open and cancelled stay out', () async {
      await store.create(ws, {'title': 'Açık'});
      final cancelled = await store.create(ws, {'title': 'İptal'});
      await store.update(cancelled, {'status': 'cancelled'});
      await completedAt('Bitti', DateTime.utc(2026, 7, 5));

      final rows = await store.watchCompleted(ws, limit: 10).first;
      expect(rows.map((t) => t.title), ['Bitti']);
    });

    test('a task with many tags still costs ONE row of the page', () async {
      // The reason `watchCompleted` does not reuse the joined `_watchList`: a
      // LIMIT on a joined statement counts JOINED rows, so a 3-tag task would
      // eat three slots and page size would depend on the user's tagging.
      final tagged = await completedAt('Etiketli', DateTime.utc(2026, 7, 9));
      await store.setTags(tagged, ['G1', 'G2', 'G3']);
      await completedAt('Sade', DateTime.utc(2026, 7, 8));

      final page = await store.watchCompleted(ws, limit: 2).first;
      expect(page.map((t) => t.title), ['Etiketli', 'Sade']);
      expect(page.first.tagIds, ['G1', 'G2', 'G3']);
    });
  });

  group('grouping', () {
    Task task({required String title, DateTime? due, bool done = false}) =>
        Task(
          id: title.padRight(26, '0'),
          workspaceId: ws,
          title: title,
          status: done ? 'completed' : 'open',
          priority: 'none',
          timezone: 'Europe/Istanbul',
          isUrgent: false,
          requiresAcknowledgement: false,
          sortOrder: 0,
          revision: 1,
          dueAt: due,
        );

    test('a completed task sinks to the END of its own group', () async {
      final now = DateTime(2026, 7, 28, 12);
      final groups = groupTasksForHome([
        task(title: 'Bitti', due: DateTime(2026, 7, 28, 9), done: true),
        task(title: 'Duruyor', due: DateTime(2026, 7, 28, 17)),
      ], now: now);
      final today = groups.firstWhere((g) => g.bucket == HomeBucket.today);
      // Chronologically 'Bitti' (09:00) precedes 'Duruyor' (17:00) — done work
      // must still land under it.
      expect(
        [for (final item in today.items) (item as TaskItem).task.title],
        ['Duruyor', 'Bitti'],
      );
    });

    test('calendar dots ignore completed work', () {
      final day = DateTime(2026, 7, 28, 9);
      expect(
        daysWithTasks([task(title: 'Bitti', due: day, done: true)]),
        isEmpty,
      );
      expect(daysWithTasks([task(title: 'Açık', due: day)]), hasLength(1));
    });

    test('the widget sorts the same way the app does (C5)', () {
      final groups = groupTasksForWidget([
        task(title: 'Bitti', due: DateTime(2026, 7, 28, 9), done: true),
        task(title: 'Duruyor', due: DateTime(2026, 7, 28, 17)),
      ], now: DateTime(2026, 7, 28, 12));
      final today = groups.firstWhere((g) => g.bucket == WidgetBucket.today);
      expect(today.tasks.map((t) => t.title), ['Duruyor', 'Bitti']);
    });
  });

  group('awStartOfDay', () {
    test('strips the time, keeps the local day', () {
      expect(
        awStartOfDay(DateTime(2026, 7, 28, 23, 59, 59)),
        DateTime(2026, 7, 28),
      );
      expect(
        awStartOfDay(DateTime(2026, 7, 29, 0, 0, 1)),
        DateTime(2026, 7, 29),
      );
    });
  });
}
