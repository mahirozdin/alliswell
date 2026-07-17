import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/tasks_api.dart';
import 'package:alliswell/src/features/tasks/ui/task_visuals.dart';

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

  test('groupTasksForHome buckets chronologically within a 30-day horizon', () {
    final now = DateTime(2026, 7, 14, 15, 30);
    final groups = groupTasksForHome([
      _task('overdue', dueAt: DateTime(2026, 7, 10, 9)),
      _task('today', dueAt: DateTime(2026, 7, 14, 18)),
      _task('tomorrow', dueAt: DateTime(2026, 7, 15, 9)),
      _task('week', dueAt: DateTime(2026, 7, 19, 9)),
      _task('next30', dueAt: DateTime(2026, 8, 10, 9)), // +27d → in
      _task('beyond', dueAt: DateTime(2026, 8, 20, 9)), // +37d → dropped
      _task('undated'),
    ], now: now);

    // Dateless sits under Overdue and above Today; nothing past +30d appears.
    expect(groups.map((g) => g.bucket), [
      HomeBucket.overdue,
      HomeBucket.noDate,
      HomeBucket.today,
      HomeBucket.tomorrow,
      HomeBucket.thisWeek,
      HomeBucket.next30Days,
    ]);
    expect(groups.every((g) => !g.dimmed), isTrue);
    expect((groups.first.items.single as TaskItem).task.id, 'overdue');
    expect(
      groups.expand((g) => g.items).map((i) => (i as TaskItem).task.id),
      isNot(contains('beyond')),
      reason: 'a +37d task is beyond the horizon → Calendar tab only',
    );
  });

  test('a selected day pulls its group first and dims only future groups', () {
    final now = DateTime(2026, 7, 14, 15, 30);
    final groups = groupTasksForHome(
      [
        _task('selected', dueAt: DateTime(2026, 7, 20, 9)),
        _task('today', dueAt: DateTime(2026, 7, 14, 18)),
        _task('tomorrow', dueAt: DateTime(2026, 7, 15, 9)),
        _task('undated'),
      ],
      now: now,
      selectedDay: DateTime(2026, 7, 20),
    );

    expect(groups.first.bucket, HomeBucket.selectedDay);
    expect(groups.first.dimmed, isFalse);
    expect((groups.first.items.single as TaskItem).task.id, 'selected');
    // Only genuinely future groups dim; Today and the dateless group stay
    // lit — current work must never look disabled (feedback round 6).
    expect(
      groups.singleWhere((g) => g.bucket == HomeBucket.tomorrow).dimmed,
      isTrue,
    );
    expect(
      groups.singleWhere((g) => g.bucket == HomeBucket.today).dimmed,
      isFalse,
    );
    expect(
      groups.singleWhere((g) => g.bucket == HomeBucket.noDate).dimmed,
      isFalse,
    );
  });

  test('every status has an icon; priorities have stable colors', () {
    // Statuses → icons (no fallback hit for the known set).
    final icons = {for (final s in kTaskStatuses) s: taskStatusIcon(s)};
    expect(icons.values.toSet(), hasLength(kTaskStatuses.length));
    expect(icons['completed'], Icons.check_circle);
    expect(icons['inbox'], Icons.inbox_outlined);
    // OPH-105: 'open' is a pending hourglass, never a bare circle (which
    // collided with the row's circular completion checkbox).
    expect(icons['open'], Icons.hourglass_empty);
    expect(icons['open'], isNot(Icons.radio_button_unchecked));
    expect(icons['waiting'], Icons.pause_circle_outline);

    // Priorities → colors from the design tokens (docs/DESIGN.md): hues are
    // fixed per priority, lightness adapts per brightness for contrast;
    // none stays neutral in both modes.
    for (final brightness in Brightness.values) {
      final t = brightness == Brightness.dark ? AwTokens.dark : AwTokens.light;
      expect(taskPriorityColor('none', brightness), isNull);
      expect(taskPriorityColor('low', brightness), t.prioLow);
      expect(taskPriorityColor('medium', brightness), t.prioMedium);
      expect(taskPriorityColor('high', brightness), t.prioHigh);
      expect(taskPriorityColor('urgent', brightness), t.prioUrgent);
    }
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
