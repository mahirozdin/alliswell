import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/tasks_api.dart';

import '../auth/test_support.dart';

Task _task(String id, {DateTime? dueAt}) => Task(
  id: id,
  workspaceId: 'ws1',
  title: id,
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
);

void main() {
  test('Task.fromJson maps detail fields and tolerates list rows', () {
    final detail = Task.fromJson({
      'id': 't1',
      'workspaceId': 'ws1',
      'projectId': null,
      'parentTaskId': null,
      'title': 'Görev',
      'description': null,
      'status': 'open',
      'priority': 'high',
      'colorRgb': null,
      'startAt': null,
      'dueAt': '2026-07-20T10:00:00.000Z',
      'remindAt': null,
      'snoozedUntil': null,
      'completedAt': null,
      'timezone': 'Europe/Istanbul',
      'isUrgent': true,
      'requiresAcknowledgement': true,
      'sortOrder': 0,
      'revision': 3,
      'tagIds': ['tag1'],
      'checklist': [
        {'id': 'c1', 'title': 'Adım', 'isDone': false, 'sortOrder': 0},
      ],
    });
    expect(detail.priority, 'high');
    expect(detail.isUrgent, isTrue);
    expect(detail.tagIds, ['tag1']);
    expect(detail.checklist.single.title, 'Adım');
    expect(detail.isCompleted, isFalse);

    // List rows come without tagIds/checklist.
    final row = Task.fromJson({
      'id': 't2',
      'workspaceId': 'ws1',
      'title': 'Liste satırı',
      'status': 'completed',
      'priority': 'none',
      'timezone': 'Europe/Istanbul',
      'isUrgent': false,
      'requiresAcknowledgement': false,
      'sortOrder': 0,
      'revision': 1,
    });
    expect(row.tagIds, isEmpty);
    expect(row.checklist, isEmpty);
    expect(row.isCompleted, isTrue);
  });

  test(
    'list() builds repeated status params, date bounds and cursor',
    () async {
      late Uri seen;
      final adapter = FakeHttpClientAdapter((options, body) async {
        seen = options.uri;
        return jsonBody(200, {'items': [], 'nextCursor': null});
      });
      final api = TasksApi(fakeDio(adapter));

      await api.list(
        'ws1',
        statuses: ['inbox', 'open'],
        dueTo: DateTime.utc(2026, 7, 14, 20, 59, 59),
        urgent: true,
        limit: 100,
        cursor: 'CURSOR000000000000000000000',
      );

      expect(seen.path, '/api/v1/workspaces/ws1/tasks');
      expect(seen.queryParametersAll['status'], ['inbox', 'open']);
      expect(seen.queryParameters['dueTo'], '2026-07-14T20:59:59.000Z');
      expect(seen.queryParameters['urgent'], 'true');
      expect(seen.queryParameters['limit'], '100');
      expect(seen.queryParameters['cursor'], 'CURSOR000000000000000000000');
    },
  );

  test('groupTasksForHome buckets chronologically', () {
    final now = DateTime(2026, 7, 14, 15, 30);
    final groups = groupTasksForHome([
      _task('overdue', dueAt: DateTime(2026, 7, 10, 9)),
      _task('today', dueAt: DateTime(2026, 7, 14, 18)),
      _task('tomorrow', dueAt: DateTime(2026, 7, 15, 9)),
      _task('week', dueAt: DateTime(2026, 7, 19, 9)),
      _task('later', dueAt: DateTime(2026, 8, 20, 9)),
      _task('undated'),
    ], now: now);

    expect(groups.map((g) => g.bucket), [
      HomeBucket.overdue,
      HomeBucket.today,
      HomeBucket.tomorrow,
      HomeBucket.thisWeek,
      HomeBucket.later,
      HomeBucket.noDate,
    ]);
    expect(groups.every((g) => !g.dimmed), isTrue);
    expect(groups.first.tasks.single.id, 'overdue');
  });

  test('a selected day pulls its group first and dims the rest', () {
    final now = DateTime(2026, 7, 14, 15, 30);
    final groups = groupTasksForHome(
      [
        _task('selected', dueAt: DateTime(2026, 7, 20, 9)),
        _task('today', dueAt: DateTime(2026, 7, 14, 18)),
        _task('undated'),
      ],
      now: now,
      selectedDay: DateTime(2026, 7, 20),
    );

    expect(groups.first.bucket, HomeBucket.selectedDay);
    expect(groups.first.dimmed, isFalse);
    expect(groups.first.tasks.single.id, 'selected');
    expect(groups.skip(1).every((g) => g.dimmed), isTrue);
  });

  test('daysWithTasks marks local due days once', () {
    final marked = daysWithTasks([
      _task('a', dueAt: DateTime(2026, 7, 20, 9)),
      _task('b', dueAt: DateTime(2026, 7, 20, 22)),
      _task('c'),
    ]);
    expect(marked, {DateTime(2026, 7, 20)});
  });
}
