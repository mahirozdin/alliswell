import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_grouping.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../support/fake_widget_host.dart';

Task _task(
  String id, {
  DateTime? dueAt,
  String priority = 'none',
  String? projectId,
  String? colorRgb,
  String status = 'open',
  int sortOrder = 0,
  DateTime? startAt,
  DateTime? completedAt,
  String? title,
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: title ?? id,
  status: status,
  priority: priority,
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: sortOrder,
  revision: 1,
  dueAt: dueAt,
  startAt: startAt,
  projectId: projectId,
  colorRgb: colorRgb,
  completedAt: completedAt,
);

Project _project(String id) => Project(
  id: id,
  workspaceId: 'W1',
  name: 'Project $id',
  colorRgb: '#0A5CFF',
  status: 'active',
  sortOrder: 0,
  isFavorite: false,
  revision: 1,
);

Map<String, dynamic> _json(WidgetSnapshot snapshot) =>
    jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;

List<String> _ids(Map<String, dynamic> view) => [
  for (final bucket in view['buckets'] as List)
    for (final item in (bucket as Map)['items'] as List) item['id'] as String,
];

void main() {
  final now = DateTime(2026, 7, 17, 10); // Friday

  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('groupTasksForWidget (OPH-130)', () {
    test('buckets tasks by due window; drops beyond +30', () {
      final groups = groupTasksForWidget([
        _task('overdue', dueAt: DateTime(2026, 7, 10, 9)),
        _task('noDate'),
        _task('today', dueAt: DateTime(2026, 7, 17, 14)),
        _task('week', dueAt: DateTime(2026, 7, 20, 9)), // +3
        _task('month', dueAt: DateTime(2026, 7, 31, 9)), // +14
        _task('beyond', dueAt: DateTime(2026, 8, 20, 9)), // +34 → dropped
      ], now: now);

      final byBucket = {for (final g in groups) g.bucket: g.tasks};
      expect(byBucket[WidgetBucket.overdue]!.single.id, 'overdue');
      expect(byBucket[WidgetBucket.noDate]!.single.id, 'noDate');
      expect(byBucket[WidgetBucket.today]!.single.id, 'today');
      expect(byBucket[WidgetBucket.thisWeek]!.single.id, 'week');
      expect(byBucket[WidgetBucket.thisMonth]!.single.id, 'month');
      expect(groups.any((g) => g.tasks.any((t) => t.id == 'beyond')), isFalse);
    });

    test('order is overdue → noDate → today → week → month; empty omitted', () {
      final groups = groupTasksForWidget([
        _task('today', dueAt: DateTime(2026, 7, 17, 9)),
        _task('overdue', dueAt: DateTime(2026, 7, 1, 9)),
      ], now: now);
      expect(groups.map((g) => g.bucket).toList(), [
        WidgetBucket.overdue,
        WidgetBucket.today,
      ]);
    });
  });

  group('buildWidgetSnapshot (OPH-130)', () {
    test('labels localize; date header + counts are present', () {
      final snap = buildWidgetSnapshot([
        _task('today', dueAt: DateTime(2026, 7, 17, 11, 30)),
      ], now: now);

      expect(snap.version, kWidgetSnapshotVersion);
      expect(snap.locale, 'en');
      expect(snap.date.weekday, 'Friday');
      expect(snap.date.day, '17');
      expect(snap.date.month, 'July');
      expect(snap.buckets.single.key, 'today');
      expect(snap.buckets.single.label, 'Today');
      expect(snap.buckets.single.count, 1);
      // OPH-174: the widget speaks the app's format. Following the language
      // means English gets its own 12h clock (Turkish stays 24h, below).
      // CLDR separates the AM/PM marker with a narrow no-break space, so match
      // the parts instead of pinning invisible whitespace.
      final enTime = snap.buckets.single.items.single.time!;
      expect(enTime, contains('11:30'));
      expect(enTime, contains('AM'));
      expect(snap.strings['allCaughtUp'], 'All caught up');

      AwI18n.instance.setActiveCached(const Locale('tr'));
      final tr = buildWidgetSnapshot([
        _task('t', dueAt: DateTime(2026, 7, 17, 11, 30)),
      ], now: now);
      expect(tr.date.weekday, 'Cuma');
      expect(tr.date.month, 'Temmuz');
      expect(tr.buckets.single.label, 'Bugün');
      expect(tr.buckets.single.items.single.time, '11:30');
    });

    test('truncates a bucket to rowsPerBucket with a "+N more" count', () {
      final many = [
        for (var i = 0; i < 5; i++)
          _task('t$i', dueAt: DateTime(2026, 7, 17, 9)),
      ];
      final snap = buildWidgetSnapshot(many, now: now, rowsPerBucket: 3);
      final today = snap.buckets.single;
      expect(today.count, 5);
      expect(today.items.length, 3);
      expect(today.more, 2);
      expect(today.toJson()['more'], 2);
    });

    // OPH-451 (#50, IOS-10): a bucket's number is what is still owed, by
    // Home's own rule (OPH-394): today's finished row stays visible at the
    // bottom, but it is not counted. Z-02: nor is it in the "+N" — `more` is
    // the open rows trimmed, so a finished row past the cap adds nothing.
    test('a bucket counts its open rows only; +N counts the open rows '
        'trimmed', () {
      final snap = buildWidgetSnapshot(
        [
          for (var i = 0; i < 3; i++)
            _task('t$i', dueAt: DateTime(2026, 7, 17, 9)),
          _task(
            'done',
            dueAt: DateTime(2026, 7, 17, 8),
            status: 'completed',
            completedAt: DateTime(2026, 7, 17, 9, 30),
          ),
        ],
        now: now,
        rowsPerBucket: 2,
      );
      final today = snap.buckets.single;
      expect(today.count, 3);
      expect(today.items.map((r) => r.id), ['t0', 't1']);
      expect(today.more, 1);
      expect(snap.openToday, 3);
    });

    // OPH-451 (#50, Z-02): the native "+N" is the bucket's count less the open
    // rows it draws (AWWidgetDayPick.swift, awMoreCount). `more` must say the
    // same of the rows the app keeps — the open ones past the cap — in every
    // view the snapshot carries, or Android's +N (which draws every kept row)
    // and iOS's disagree. The walkthrough's "BUGÜN 11" had five finished rows
    // in it and drew "+13" for eight hidden tasks.
    test('more is the open rows trimmed: count less the open rows kept, in '
        'every view', () {
      final snap = buildWidgetSnapshot(
        [
          for (var i = 0; i < 11; i++)
            _task('t$i', dueAt: DateTime(2026, 7, 17, 9), projectId: 'p1'),
          for (var i = 0; i < 5; i++)
            _task(
              'done$i',
              dueAt: DateTime(2026, 7, 17, 8),
              projectId: 'p1',
              status: 'completed',
              completedAt: DateTime(2026, 7, 17, 9, 30),
            ),
          _task('later', dueAt: DateTime(2026, 7, 20, 9)),
        ],
        now: now,
        projects: [_project('p1')],
      );
      final today = snap.buckets.firstWhere((b) => b.key == 'today');
      expect(today.count, 11);
      expect(today.items, hasLength(kWidgetRowsPerBucket));
      expect(today.items.where((r) => !r.done), hasLength(11));
      expect(today.more, 0, reason: 'every open row is kept');
      expect(today.toJson().containsKey('more'), isFalse);

      final json = _json(snap);
      final levels = <Map<String, dynamic>>[
        json,
        for (final day in json['days'] as List) day as Map<String, dynamic>,
      ];
      final views = [
        for (final level in levels) ...[
          level,
          for (final view in ((level['views'] as Map?) ?? {}).values)
            view as Map<String, dynamic>,
        ],
      ];
      expect(views.length, greaterThan(3));
      for (final view in views) {
        for (final bucket in view['buckets'] as List) {
          final b = bucket as Map<String, dynamic>;
          final openKept = (b['items'] as List)
              .where((r) => (r as Map)['done'] != true)
              .length;
          expect(
            (b['more'] as int?) ?? 0,
            (b['count'] as int) - openKept,
            reason: '${b['key']} in ${view['date'] ?? 'a view'}',
          );
        }
      }
    });

    test('more past the cap counts open rows only', () {
      final snap = buildWidgetSnapshot(
        [
          for (var i = 0; i < 5; i++)
            _task('t$i', dueAt: DateTime(2026, 7, 17, 9)),
          for (var i = 0; i < 3; i++)
            _task(
              'done$i',
              dueAt: DateTime(2026, 7, 17, 8),
              status: 'completed',
              completedAt: DateTime(2026, 7, 17, 9, 30),
            ),
        ],
        now: now,
        rowsPerBucket: 3,
      );
      final today = snap.buckets.single;
      expect(today.count, 5);
      expect(today.items.map((r) => r.id), ['t0', 't1', 't2']);
      expect(today.more, 2);

      final allShown = buildWidgetSnapshot(
        [
          for (var i = 0; i < 3; i++)
            _task('t$i', dueAt: DateTime(2026, 7, 17, 9)),
          for (var i = 0; i < 5; i++)
            _task(
              'done$i',
              dueAt: DateTime(2026, 7, 17, 8),
              status: 'completed',
              completedAt: DateTime(2026, 7, 17, 9, 30),
            ),
        ],
        now: now,
        rowsPerBucket: 3,
      ).buckets.single;
      expect(allShown.count, 3);
      expect(allShown.more, 0);
      expect(allShown.toJson().containsKey('more'), isFalse);
    });

    // OPH-451 (#50): the words a native completion needs — the open count's
    // phrase with its number still to fill, and the circle's spoken label
    // with the title still to fill. The native side owns no translations.
    test('strings carry the open-count pattern and the circle\'s label', () {
      final snap = buildWidgetSnapshot([
        _task('today', dueAt: DateTime(2026, 7, 17, 11, 30)),
      ], now: now);
      expect(snap.strings['openTodayPattern'], '{count} open');
      expect(snap.strings['completeTask'], 'Complete: {title}');

      AwI18n.instance.setActiveCached(const Locale('tr'));
      final tr = buildWidgetSnapshot([
        _task('t', dueAt: DateTime(2026, 7, 17, 11, 30)),
      ], now: now);
      expect(tr.strings['openTodayPattern'], '{count} açık');
      expect(tr.strings['completeTask'], 'Tamamla: {title}');
    });

    test('carries the project color and a done flag', () {
      final snap = buildWidgetSnapshot(
        [_task('t', dueAt: DateTime(2026, 7, 17, 9), projectId: 'P1')],
        now: now,
        projectColorById: {'P1': '#FF8800'},
      );
      final row = snap.buckets.single.items.single;
      expect(row.projectColor, '#FF8800');
      expect(row.done, isFalse);
    });
  });

  // OPH-372 (ADR-0053): the widget files by Home's plan-day rule.
  group('"when" on the widget (OPH-372)', () {
    test('a started task due later is in Today; overdue still wins', () {
      final groups = groupTasksForWidget([
        _task(
          'started',
          startAt: DateTime(2026, 7, 16),
          dueAt: DateTime(2026, 7, 20, 17),
        ),
        _task(
          'late',
          startAt: DateTime(2026, 7, 17),
          dueAt: DateTime(2026, 7, 15, 9),
        ),
        _task('undated-later', startAt: DateTime(2026, 7, 21)),
      ], now: now);
      final byBucket = {for (final g in groups) g.bucket: g.tasks};
      expect(byBucket[WidgetBucket.today]!.single.id, 'started');
      expect(byBucket[WidgetBucket.overdue]!.single.id, 'late');
      expect(byBucket[WidgetBucket.thisWeek]!.single.id, 'undated-later');
      expect(byBucket[WidgetBucket.noDate], isNull);
    });

    test('its Today row says the due DAY, not a time, and it is counted', () {
      final snap = buildWidgetSnapshot([
        _task(
          'started',
          startAt: DateTime(2026, 7, 16),
          dueAt: DateTime(2026, 7, 20, 17),
        ),
      ], now: now);
      final today = snap.buckets.single;
      expect(today.key, 'today');
      final time = today.items.single.time!;
      expect(time, contains('20'));
      expect(time, isNot(contains('5:00')));
      expect(time, isNot(contains('17:00')));
      expect(snap.openToday, 1);
      expect(snap.next!.id, 'started');
      expect(snap.next!.bucket, 'today');
      expect(snap.next!.time, time);
    });

    test('a started undated task in Today has no time label', () {
      final snap = buildWidgetSnapshot([
        _task('undated', startAt: DateTime(2026, 7, 10)),
      ], now: now);
      expect(snap.buckets.single.key, 'today');
      expect(snap.buckets.single.items.single.time, isNull);
      expect(snap.openToday, 1);
    });
  });

  // Snapshot v6 (#50, ADR-0010 revision 2026-11-12): today and the next two
  // days, each a full view, so a WidgetKit entry past midnight draws its own
  // day instead of yesterday's list under today's date.
  group('snapshot v6 day views', () {
    final tasks = [
      _task('late', dueAt: DateTime(2026, 7, 10, 9), projectId: 'P1'),
      _task('today', dueAt: DateTime(2026, 7, 17, 14), projectId: 'P1'),
      _task('tomorrow', dueAt: DateTime(2026, 7, 18, 9), projectId: 'P2'),
      _task('later', dueAt: DateTime(2026, 7, 25, 9)),
      _task('undated'),
      _task(
        'done-today',
        dueAt: DateTime(2026, 7, 17, 8),
        status: 'completed',
        completedAt: DateTime(2026, 7, 17, 8, 30),
      ),
    ];
    final projects = [_project('P1'), _project('P2')];

    test('day views use the same grouping as the top level for day 0', () {
      final json = _json(
        buildWidgetSnapshot(tasks, now: now, projects: projects),
      );
      expect(json['v'], 6);
      final days = json['days'] as List;
      expect(days, hasLength(3));
      expect(
        [for (final d in days) d['date']],
        ['2026-07-17', '2026-07-18', '2026-07-19'],
      );
      final day0 = days.first as Map<String, dynamic>;
      // Day 0 IS the v5 top level: an old extension reads the top level, a
      // new one reads days[0], and both draw the same widget.
      expect(day0['header'], json['date']);
      expect(day0['buckets'], json['buckets']);
      expect(day0['openToday'], json['openToday']);
      expect(day0['openTodayLabel'], json['strings']['openToday']);
      expect(day0['next'], json['next']);
      expect(day0['views'], json['views']);
      // Every v5 field is still where a v5 reader looks for it.
      for (final key in [
        'v',
        'generatedAt',
        'locale',
        'date',
        'strings',
        'clockFormat',
        'openToday',
        'next',
        'buckets',
        'lists',
        'views',
      ]) {
        expect(json.containsKey(key), isTrue, reason: key);
      }
      // Tomorrow is its own day: today's task is late, tomorrow's is Today.
      final day1 = days[1] as Map<String, dynamic>;
      expect(day1['header'], {
        'weekday': 'Saturday',
        'day': '18',
        'month': 'July',
      });
      final byKey = {
        for (final b in day1['buckets'] as List) b['key']: b['items'],
      };
      expect(
        [for (final i in byKey['overdue'] as List) i['id']],
        ['late', 'today'],
      );
      expect([for (final i in byKey['today'] as List) i['id']], ['tomorrow']);
      expect(day1['openToday'], 3);
      expect(day1['openTodayLabel'], '3 open');
      expect(day1['next']['id'], 'late');
    });

    test("a task completed today is not a dimmed row in tomorrow's view", () {
      final json = _json(buildWidgetSnapshot(tasks, now: now));
      final days = json['days'] as List;
      final day0 = _ids(days[0] as Map<String, dynamic>);
      expect(day0, contains('done-today'), reason: 'OPH-185: dimmed today');
      for (final day in days.skip(1)) {
        expect(
          _ids(day as Map<String, dynamic>),
          isNot(contains('done-today')),
        );
      }
    });

    test('the stale line is the app\'s words, in its language', () {
      expect(
        buildWidgetSnapshot(const [], now: now).strings['stale'],
        'List out of date · Open to update',
      );
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(
        buildWidgetSnapshot(const [], now: now).strings['stale'],
        'Liste güncel değil · Güncellemek için aç',
      );
    });

    test(
      'snapshot stays under kWidgetSnapshotMaxBytes for 300 tasks and 20 projects',
      () {
        // A heavy but real account: 20 projects, 300 open tasks spread over
        // every bucket, titles of a long sentence, Turkish letters (two bytes
        // each in UTF-8). The limit is a measurement plus headroom, and this
        // test is what keeps it honest when a field is added.
        AwI18n.instance.setActiveCached(const Locale('tr'));
        final projects = [for (var p = 0; p < 20; p++) _project('P$p')];
        final offsets = [-9, -2, 0, 0, 1, 2, 4, 9, 20, null];
        final heavy = [
          for (var i = 0; i < 300; i++)
            _task(
              'T${i.toString().padLeft(25, '0')}',
              title:
                  'Görev $i · müşteriyle sözleşme taslağını gözden geçir ve '
                  'çağrı notlarını işle',
              projectId: 'P${i % 20}',
              priority: const ['none', 'low', 'medium', 'high'][i % 4],
              dueAt: offsets[i % offsets.length] == null
                  ? null
                  : DateTime(
                      2026,
                      7,
                      17 + offsets[i % offsets.length]!,
                      9 + i % 12,
                    ),
            ),
        ];
        final bytes = utf8
            .encode(
              jsonEncode(
                buildWidgetSnapshot(
                  heavy,
                  now: now,
                  projects: projects,
                  projectColorById: {
                    for (final p in projects) p.id: p.colorRgb,
                  },
                ).toJson(),
              ),
            )
            .length;
        // ignore: avoid_print
        print('widget snapshot v6, 300 tasks / 20 projects: $bytes bytes');
        expect(bytes, lessThanOrEqualTo(kWidgetSnapshotMaxBytes));
      },
    );
  });

  group('WidgetBridge (OPH-130)', () {
    test(
      'publish configures once, saves the JSON snapshot, and updates',
      () async {
        final host = FakeWidgetHost();
        final bridge = WidgetBridge(host);

        await bridge.publish([
          _task('today', dueAt: DateTime(2026, 7, 17, 9)),
        ], now: now);

        expect(host.configured, isTrue);
        expect(host.updates, 1);
        final json = jsonDecode(host.lastSaved!) as Map<String, dynamic>;
        expect(json['v'], kWidgetSnapshotVersion);
        expect((json['buckets'] as List).first['label'], 'Today');

        // A second publish updates again but does not re-configure.
        await bridge.publish(const [], now: now);
        expect(host.updates, 2);
      },
    );
  });
}
