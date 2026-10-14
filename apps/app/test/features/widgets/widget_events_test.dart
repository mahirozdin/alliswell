import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/calendar/data/external_event.dart';
import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_grouping.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../../support/fake_widget_host.dart';

/// Snapshot v5 — the user's calendar events in the home-screen widget, under
/// Home's own rules (`groupTasksForHome`): never overdue, never dateless, a
/// finished one dropped, a running one filed under today, the same 30 days.
Task _task(String id, {DateTime? dueAt, String? projectId}) => Task(
  id: id,
  workspaceId: 'W1',
  title: 'task $id',
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
  projectId: projectId,
);

ExternalEvent _event(
  String id,
  DateTime start,
  DateTime end, {
  bool allDay = false,
  String? summary,
}) => ExternalEvent(
  id: id,
  summary: summary ?? 'event $id',
  startsAt: start,
  endsAt: end,
  isAllDay: allDay,
  isBusy: true,
);

List<String> _ids(WidgetGroup group) => [
  for (final entry in group.entries)
    switch (entry) {
      WidgetTaskEntry(:final task) => task.id,
      WidgetEventEntry(:final event) => event.id,
    },
];

/// The user's clock as the widget writes it — the system format, English
/// (intl puts a narrow no-break space before "PM").
String _t(int hour) => awFormatTime(
  DateTime(2026, 7, 17, hour),
  format: kAwSystemDateFormat,
  locale: 'en',
);

Map<String, dynamic> _json(WidgetSnapshot snapshot) =>
    jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;

Map<String, dynamic>? _row(Map<String, dynamic> json, String id) {
  for (final bucket in json['buckets'] as List) {
    for (final item in (bucket as Map)['items'] as List) {
      if ((item as Map)['id'] == id) {
        return {...item.cast<String, dynamic>(), 'bucket': bucket['key']};
      }
    }
  }
  return null;
}

void main() {
  final now = DateTime(2026, 7, 17, 10); // Friday
  final today = DateTime(2026, 7, 17);

  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('groupTasksForWidget with events', () {
    test('a past event is dropped, never overdue', () {
      final groups = groupTasksForWidget(
        [_task('late', dueAt: DateTime(2026, 7, 10, 9))],
        now: now,
        events: [
          _event('gone', DateTime(2026, 7, 15, 9), DateTime(2026, 7, 15, 10)),
        ],
      );
      expect(groups.map((g) => g.bucket), [WidgetBucket.overdue]);
      expect(_ids(groups.single), ['late']);
    });

    test('a running event belongs to today, not the day it began', () {
      final groups = groupTasksForWidget(
        const [],
        now: now,
        events: [
          _event(
            'trip',
            DateTime(2026, 7, 14),
            DateTime(2026, 7, 20),
            allDay: true,
          ),
        ],
      );
      expect(groups.single.bucket, WidgetBucket.today);
      final entry = groups.single.entries.single as WidgetEventEntry;
      expect(entry.day, today);
    });

    test('all-day first, then by time — mixed with tasks', () {
      final groups = groupTasksForWidget(
        [_task('t-11', dueAt: DateTime(2026, 7, 17, 11))],
        now: now,
        events: [
          _event('e-14', DateTime(2026, 7, 17, 14), DateTime(2026, 7, 17, 15)),
          _event('e-9', DateTime(2026, 7, 17, 9), DateTime(2026, 7, 17, 9, 30)),
          _event(
            'e-allday',
            DateTime(2026, 7, 17),
            DateTime(2026, 7, 18),
            allDay: true,
          ),
        ],
      );
      expect(groups.single.bucket, WidgetBucket.today);
      expect(_ids(groups.single), ['e-allday', 'e-9', 't-11', 'e-14']);
    });

    test('the 30-day horizon, and a one-day all-day event marks one day', () {
      final groups = groupTasksForWidget(
        const [],
        now: now,
        events: [
          // Exclusive end: the 18th's all-day event is NOT also on the 19th.
          _event(
            'sat',
            DateTime(2026, 7, 18),
            DateTime(2026, 7, 19),
            allDay: true,
          ),
          _event('far', DateTime(2026, 8, 16, 9), DateTime(2026, 8, 16, 10)),
          _event('beyond', DateTime(2026, 8, 17, 9), DateTime(2026, 8, 17, 10)),
        ],
      );
      expect(groups.map((g) => g.bucket), [
        WidgetBucket.thisWeek,
        WidgetBucket.thisMonth,
      ]);
      expect(_ids(groups[0]), ['sat']);
      expect(_ids(groups[1]), ['far']);
    });

    test('events never become the lock screen\'s next task', () {
      final groups = groupTasksForWidget(
        [_task('later', dueAt: DateTime(2026, 7, 20, 9))],
        now: now,
        events: [
          _event('now', DateTime(2026, 7, 17, 11), DateTime(2026, 7, 17, 12)),
        ],
      );
      expect(nextTaskForWidget(groups)?.task.id, 'later');
      expect(groups.first.tasks, isEmpty);
    });
  });

  group('snapshot v5', () {
    test('declares v5; an event row carries kind and day', () {
      final json = _json(
        buildWidgetSnapshot(
          [_task('t1', dueAt: DateTime(2026, 7, 17, 16))],
          now: now,
          events: [
            _event(
              'meet',
              DateTime(2026, 7, 17, 14),
              DateTime(2026, 7, 17, 15),
            ),
          ],
        ),
      );
      expect(json['v'], 5);
      expect(kWidgetSnapshotVersion, 5);
      final event = _row(json, 'meet')!;
      expect(event['kind'], 'event');
      expect(event['day'], '2026-07-17');
      expect(event['done'], isFalse);
      expect(event['priority'], 'none');
      expect(event['time'], '${_t(14)}–${_t(15)}');
      expect(event['title'], 'event meet');
      expect(event.containsKey('projectColor'), isFalse);
      // A task row reads exactly as it did in v4: no kind, no day.
      final task = _row(json, 't1')!;
      expect(task.containsKey('kind'), isFalse);
      expect(task.containsKey('day'), isFalse);
    });

    test('the bucket counts events; openToday and next stay task-only', () {
      final json = _json(
        buildWidgetSnapshot(
          [_task('t1', dueAt: DateTime(2026, 7, 17, 16))],
          now: now,
          events: [
            _event(
              'meet',
              DateTime(2026, 7, 17, 14),
              DateTime(2026, 7, 17, 15),
            ),
          ],
        ),
      );
      final todayBucket = (json['buckets'] as List).single as Map;
      expect(todayBucket['count'], 2);
      expect(json['openToday'], 1);
      expect(json['next']['id'], 't1');
    });

    test('all-day says "All day" today; a later event a short date', () {
      final json = _json(
        buildWidgetSnapshot(
          const [],
          now: now,
          events: [
            _event(
              'holiday',
              DateTime(2026, 7, 17),
              DateTime(2026, 7, 18),
              allDay: true,
            ),
            _event(
              'tuesday',
              DateTime(2026, 7, 21, 9),
              DateTime(2026, 7, 21, 10),
            ),
          ],
        ),
      );
      expect(_row(json, 'holiday')!['time'], 'All day');
      final tuesday = _row(json, 'tuesday')!;
      expect(tuesday['bucket'], 'thisWeek');
      expect(tuesday['day'], '2026-07-21');
      expect(tuesday['time'], allOf(contains('Jul'), contains(_t(9))));

      AwI18n.instance.setActiveCached(const Locale('tr'));
      final tr = _json(
        buildWidgetSnapshot(
          const [],
          now: now,
          events: [
            _event(
              'holiday',
              DateTime(2026, 7, 17),
              DateTime(2026, 7, 18),
              allDay: true,
            ),
          ],
        ),
      );
      expect(_row(tr, 'holiday')!['time'], 'Tüm gün');
    });

    test('a running event is labelled by its end', () {
      final json = _json(
        buildWidgetSnapshot(
          const [],
          now: now,
          events: [
            _event(
              'overnight',
              DateTime(2026, 7, 16, 22),
              DateTime(2026, 7, 17, 11),
            ),
          ],
        ),
      );
      final row = _row(json, 'overnight')!;
      expect(row['bucket'], 'today');
      expect(row['day'], '2026-07-17');
      expect(row['time'], '–${_t(11)}');
    });

    test('Private widget hides an event\'s title too', () {
      final json = _json(
        buildWidgetSnapshot(
          const [],
          now: now,
          hideTitles: true,
          events: [
            _event(
              'secret',
              DateTime(2026, 7, 17, 14),
              DateTime(2026, 7, 17, 15),
              summary: 'Doctor appointment',
            ),
          ],
        ),
      );
      expect(jsonEncode(json), isNot(contains('Doctor appointment')));
      expect(_row(json, 'secret')!['title'], 'Private event');
      // The row is still a row: its time and its day stay.
      expect(_row(json, 'secret')!['time'], '${_t(14)}–${_t(15)}');
      expect(_row(json, 'secret')!['day'], '2026-07-17');
    });

    test('events stay out of a project view', () {
      final json = _json(
        buildWidgetSnapshot(
          [_task('w1', dueAt: DateTime(2026, 7, 17, 16), projectId: 'work')],
          now: now,
          projects: const [
            Project(
              id: 'work',
              workspaceId: 'W1',
              name: 'Work',
              colorRgb: '#0A5CFF',
              status: 'active',
              sortOrder: 0,
              isFavorite: false,
              revision: 1,
            ),
          ],
          events: [
            _event(
              'meet',
              DateTime(2026, 7, 17, 14),
              DateTime(2026, 7, 17, 15),
            ),
          ],
        ),
      );
      expect(_row(json, 'meet'), isNotNull);
      final work = json['views']['work'] as Map<String, dynamic>;
      expect(jsonEncode(work), isNot(contains('meet')));
      expect(((work['buckets'] as List).single as Map)['count'], 1);
    });
  });

  group('publishWidgetFromReplica with events', () {
    const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
    const other = '01WSBBBBBBBBBBBBBBBBBBBBBB';
    late AwDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
    });

    tearDown(() => db.close());

    Future<void> seedEvent(String id, String workspaceId) => db
        .into(db.externalEvents)
        .insert(
          ExternalEventsCompanion.insert(
            id: id,
            workspaceId: workspaceId,
            summary: Value('Toplantı $id'),
            startsAt: DateTime(2026, 7, 17, 14),
            endsAt: DateTime(2026, 7, 17, 15),
          ),
        );

    test('the background redraw reads the calendar of its workspace', () async {
      await seedEvent('E-MINE', ws);
      await seedEvent('E-OTHER', other);
      final host = FakeWidgetHost();

      expect(
        await publishWidgetFromReplica(
          db,
          scope: TaskScope.workspace(ws),
          now: now,
          host: host,
        ),
        isTrue,
      );
      final json = jsonDecode(host.lastSaved!) as Map<String, dynamic>;
      final mine = _row(json, 'E-MINE')!;
      expect(mine['kind'], 'event');
      expect(mine['day'], '2026-07-17');
      expect(mine['title'], 'Toplantı E-MINE');
      expect(_row(json, 'E-OTHER'), isNull);
    });

    test('an organisation\'s shared workspaces draw no calendar', () async {
      await seedEvent('E-MINE', ws);
      final host = FakeWidgetHost();

      await publishWidgetFromReplica(
        db,
        scope: TaskScope.mine([ws], 'U1'),
        now: now,
        host: host,
      );
      final json = jsonDecode(host.lastSaved!) as Map<String, dynamic>;
      expect(_row(json, 'E-MINE'), isNull);
    });

    test('the private setting reaches the background redraw', () async {
      await seedEvent('E-MINE', ws);
      await localKv.set(kWidgetPrivatePrefKey, 'true');
      final host = FakeWidgetHost();

      await publishWidgetFromReplica(
        db,
        scope: TaskScope.workspace(ws),
        now: now,
        host: host,
      );
      expect(host.lastSaved, isNot(contains('Toplantı')));
    });
  });
}
