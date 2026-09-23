import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/widgets/widget_grouping.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-336 — a widget can be set to one project, and the lock screen names the
/// next task. Both decisions live in Dart: the native side only PICKS a list
/// id out of the snapshot (W9). These pin the Dart half; the Swift and Kotlin
/// readers are pinned by name at the bottom.
Task _task(
  String id, {
  DateTime? dueAt,
  String? projectId,
  String status = 'open',
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: 'title of $id',
  status: status,
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
  projectId: projectId,
);

Project _project(String id, {String status = 'active', String? name}) =>
    Project(
      id: id,
      workspaceId: 'W1',
      name: name ?? 'Project $id',
      colorRgb: '#0A5CFF',
      status: status,
      sortOrder: 0,
      isFavorite: false,
      revision: 1,
    );

void main() {
  final now = DateTime(2026, 7, 17, 10); // Friday

  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  final tasks = [
    _task('work-late', dueAt: DateTime(2026, 7, 10, 9), projectId: 'work'),
    _task('work-today', dueAt: DateTime(2026, 7, 17, 14), projectId: 'work'),
    _task('home-today', dueAt: DateTime(2026, 7, 17, 9), projectId: 'home'),
    _task('loose', dueAt: DateTime(2026, 7, 20, 9)),
  ];

  group('filterTasksForWidgetList', () {
    test('the whole list is every task, untouched', () {
      expect(filterTasksForWidgetList(tasks, kWidgetListAll), same(tasks));
    });

    test('a project is its own tasks and nothing else', () {
      expect(filterTasksForWidgetList(tasks, 'work').map((t) => t.id), [
        'work-late',
        'work-today',
      ]);
      // A task with no project is in no project's list.
      expect(filterTasksForWidgetList(tasks, 'home').map((t) => t.id), [
        'home-today',
      ]);
    });
  });

  group('nextTaskForWidget', () {
    test('overdue comes first — it is the most late', () {
      final next = nextTaskForWidget(groupTasksForWidget(tasks, now: now));
      expect(next?.task.id, 'work-late');
      expect(next?.bucket, WidgetBucket.overdue);
    });

    test('a finished task is never next', () {
      // Finished today, due yesterday: it still sits in Overdue (OPH-185's
      // dimmed row), ALONE — so the first row of the first bucket is done.
      // (Within one bucket the grouping already sinks done rows, which is
      // why a same-bucket case proves nothing — measured by injection.)
      final next = nextTaskForWidget(
        groupTasksForWidget([
          _task('done', dueAt: DateTime(2026, 7, 16, 8), status: 'completed'),
          _task('open', dueAt: DateTime(2026, 7, 17, 12)),
        ], now: now),
      );
      expect(next?.task.id, 'open');
    });

    test('a dateless task waits until nothing dated is open', () {
      final withDated = nextTaskForWidget(
        groupTasksForWidget([
          _task('someday'),
          _task('in-two-weeks', dueAt: DateTime(2026, 7, 31, 9)),
        ], now: now),
      );
      // The widget draws "No date" above "This month"; the lock screen does
      // not — every day's work is nobody's "next".
      expect(withDated?.task.id, 'in-two-weeks');

      final alone = nextTaskForWidget(
        groupTasksForWidget([_task('someday')], now: now),
      );
      expect(alone?.task.id, 'someday');
      expect(alone?.bucket, WidgetBucket.noDate);
    });

    test('nothing open means no next task', () {
      expect(nextTaskForWidget(const []), isNull);
    });
  });

  group('snapshot v4', () {
    final projects = [
      _project('work', name: 'Work'),
      _project('old', status: 'archived'),
      _project('home', name: 'Home'),
      _project('quiet', name: 'Quiet'),
    ];

    Map<String, dynamic> jsonOf(WidgetSnapshot snapshot) =>
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;

    test('an unconfigured widget reads exactly what it read before', () {
      final plain = jsonOf(buildWidgetSnapshot(tasks, now: now));
      final withLists = jsonOf(
        buildWidgetSnapshot(tasks, now: now, projects: projects),
      );
      // The whole list stays at the top level — the lists are ADDED beside
      // it, so a widget that never heard of `views` still draws everything.
      expect(withLists['buckets'], plain['buckets']);
      expect(withLists['openToday'], plain['openToday']);
      expect(withLists['strings']['openToday'], plain['strings']['openToday']);
      expect(
        (withLists['buckets'] as List).expand((b) => b['items'] as List),
        hasLength(tasks.length),
      );
      expect(withLists['v'], 4);
    });

    test('the picker offers the whole list, then the live projects', () {
      final json = jsonOf(
        buildWidgetSnapshot(tasks, now: now, projects: projects),
      );
      expect(
        json['lists'],
        [
          {'id': 'all', 'name': 'All tasks'},
          {'id': 'work', 'name': 'Work', 'color': '#0A5CFF'},
          {'id': 'home', 'name': 'Home', 'color': '#0A5CFF'},
          {'id': 'quiet', 'name': 'Quiet', 'color': '#0A5CFF'},
        ],
        reason:
            'archived projects are not offered — a task cannot be filed '
            'under one either',
      );
      expect((json['views'] as Map).keys, ['work', 'home', 'quiet']);
    });

    test('a project view holds that project and only that project', () {
      final json = jsonOf(
        buildWidgetSnapshot(tasks, now: now, projects: projects),
      );
      final work = json['views']['work'] as Map<String, dynamic>;
      final ids = [
        for (final bucket in work['buckets'] as List)
          for (final item in bucket['items'] as List) item['id'],
      ];
      expect(ids, ['work-late', 'work-today']);
      // Its OWN count, in its own words — not the whole list's "3 open".
      expect(work['openToday'], 2);
      expect(work['openTodayLabel'], '2 open');
      expect(json['openToday'], 3);
      expect(work['next'], {
        'id': 'work-late',
        'title': 'title of work-late',
        'bucket': 'overdue',
        'label': 'Overdue',
        'time': isA<String>(),
      });
    });

    test('an empty project says "all caught up", not "everything"', () {
      final json = jsonOf(
        buildWidgetSnapshot(tasks, now: now, projects: projects),
      );
      // Present and empty: the widget falls back to the whole list only for
      // an id it has never heard of (a project deleted since it was set up).
      expect(json['views']['quiet'], {'buckets': <Object>[]});
    });

    test('no projects: the whole list alone, and no views key', () {
      final json = jsonOf(buildWidgetSnapshot(tasks, now: now));
      expect(json['lists'], [
        {'id': 'all', 'name': 'All tasks'},
      ]);
      expect(json.containsKey('views'), isFalse);
      expect(json['next']['id'], 'work-late');
    });

    test('the words are the app’s, in the app’s language', () {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      final json = jsonOf(
        buildWidgetSnapshot(tasks, now: now, projects: projects),
      );
      expect(json['lists'][0]['name'], 'Tüm görevler');
      expect(json['strings']['upNext'], 'Sıradaki');
      expect(json['strings']['chooseList'], 'Bu widget\'ta göster');
      expect(json['next']['label'], 'Gecikmiş');
    });
  });

  // The Swift and Kotlin readers cannot run here; this pins what they must
  // keep saying (the widget_clock_native_test pattern — structure, not
  // formatting).
  group('the native readers pick a list, they never filter one', () {
    final swift = File(
      'ios/AllisWellWidget/AllisWellWidget.swift',
    ).readAsStringSync();
    final bundle = File(
      'ios/AllisWellWidget/AllisWellWidgetBundle.swift',
    ).readAsStringSync();
    const kotlinDir = 'android/app/src/main/kotlin/com/alliswell/alliswell';
    final lists = File('$kotlinDir/WidgetLists.kt').readAsStringSync();
    final kotlin = [
      for (final name in [
        'WidgetLists.kt',
        'TasksWidgetProvider.kt',
        'TasksWidgetService.kt',
        'TasksWidgetConfigureActivity.kt',
      ])
        File('$kotlinDir/$name').readAsStringSync(),
    ].join('\n');
    final info = File(
      'android/app/src/main/res/xml/tasks_widget_info.xml',
    ).readAsStringSync();

    test('all three spell the whole list the same way', () {
      expect(swift, contains('let kAWListAll = "$kWidgetListAll"'));
      expect(lists, contains('const val WIDGET_LIST_ALL = "$kWidgetListAll"'));
    });

    test('an id the snapshot lost draws the whole list on both', () {
      expect(swift, contains('let view = views?[listId] else {'));
      expect(
        lists,
        contains('optJSONObject("views")?.optJSONObject(listId) ?: snapshot'),
      );
    });

    test('no native file asks which project a task is in', () {
      // The filter is Dart's (W9). A `projectId` in a reader would be a second
      // definition of what "Work" holds — the one this task exists to avoid.
      expect(swift, isNot(contains('projectId')));
      expect(kotlin, isNot(contains('projectId')));
    });

    test('iOS 17 takes the kind over; the iOS 16 widget steps aside', () {
      expect(bundle, contains('AllisWellConfigurableWidget()'));
      expect(
        swift,
        contains('kind: kWidgetKind, intent: AWWidgetConfigIntent'),
      );
      // Without these two the gallery lists AllisWell twice on iOS 17+.
      expect(swift, contains('return kWidgetKind + ".ios16"'));
      expect(
        swift,
        contains('if #available(iOS 17.0, macOS 14.0, *) { return [] }'),
      );
    });

    test('the lock screen families are offered on iOS', () {
      expect(swift, contains('.accessoryRectangular, .accessoryCircular,'));
    });

    test('Android configures per widget, and places without asking on 12+', () {
      expect(
        info,
        contains(
          'android:configure="com.alliswell.alliswell.TasksWidgetConfigureActivity"',
        ),
      );
      expect(info, contains('reconfigurable|configuration_optional'));
    });
  });
}
