import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/tasks_api.dart';
import 'package:alliswell/src/features/tasks/providers.dart';

import '../auth/test_support.dart';

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

  test('TaskListKind quick-add bodies match their list semantics', () {
    final now = DateTime(2026, 7, 14, 15, 30);

    expect(TaskListKind.inbox.quickAddBody('Fikir', now), {
      'title': 'Fikir',
      'status': 'inbox',
    });

    final today = TaskListKind.today.quickAddBody('Bugün', now);
    expect(
      DateTime.parse(today['dueAt'] as String).toLocal().day,
      now.day,
      reason: 'today quick-add is due today',
    );

    final upcoming = TaskListKind.upcoming.quickAddBody('Yarın', now);
    final upcomingDue = DateTime.parse(upcoming['dueAt'] as String).toLocal();
    expect(upcomingDue.day, now.add(const Duration(days: 1)).day);
    expect(upcomingDue.hour, 9);
  });

  test('TaskListKind filters: today bounded above, upcoming starts after', () {
    final now = DateTime(2026, 7, 14, 15, 30);
    final today = TaskListKind.today.describe(now);
    final upcoming = TaskListKind.upcoming.describe(now);

    expect(today['statuses'], isNot(contains('completed')));
    final dueTo = today['dueTo'] as DateTime;
    final dueFrom = upcoming['dueFrom'] as DateTime;
    expect(dueFrom.isAfter(dueTo), isTrue);
    expect(TaskListKind.inbox.describe(now)['statuses'], ['inbox']);
  });
}
