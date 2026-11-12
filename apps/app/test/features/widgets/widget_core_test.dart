import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_grouping.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';

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

    // #50 (PR2-03): the server's sort is stable, so a tie keeps the input
    // order (newest id first). Dart's List.sort is not stable past 32 rows:
    // the phone drew tied rows in another order than the server's view, and
    // a swap between the two views moved rows under the finger.
    test('a tie keeps the input order past 32 rows, as the server does', () {
      final tasks = [
        for (var i = 40; i >= 1; i--)
          _task('T${'$i'.padLeft(2, '0')}', dueAt: DateTime(2026, 7, 17, 18)),
        for (var i = 40; i >= 1; i--) _task('S${'$i'.padLeft(2, '0')}'),
      ];
      final groups = groupTasksForWidget(tasks, now: now);
      expect(groups.map((g) => g.bucket).toList(), [
        WidgetBucket.noDate,
        WidgetBucket.today,
      ]);
      expect(
        [for (final g in groups) ...g.tasks.map((t) => t.id)],
        [
          ...tasks.skip(40).map((t) => t.id),
          ...tasks.take(40).map((t) => t.id),
        ],
      );
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

  group('the view swap fixture (#50, PR2-03)', () {
    // The phone's snapshot and the server's view of the same rows, from the
    // app's own builders: the Swift tests (WidgetFetchPolicyTests) draw both
    // and check that the rows both hold sit in the same order, so a swap at a
    // refresh only shows the row the phone lacks. The server's port is held
    // to `buildWidgetServerDays` by the shared grouping fixture.
    test('the fixture is current, and the shared rows keep their order', () {
      tzdata.initializeTimeZones();
      final rendered = _renderViewSwapFixture();
      final file = File(_viewSwapFixturePath);
      if (Platform.environment['UPDATE_FIXTURES'] == '1') {
        file.writeAsStringSync(rendered);
      }
      expect(file.existsSync(), isTrue, reason: 'run with UPDATE_FIXTURES=1');
      expect(file.readAsStringSync(), rendered);

      final fixture = jsonDecode(rendered) as Map<String, dynamic>;
      List<String> today(Map<String, dynamic> view) => [
        for (final b in view['buckets'] as List)
          if ((b as Map)['key'] == 'today')
            for (final item in b['items'] as List) item['id'] as String,
      ];
      final local = today(fixture['local'] as Map<String, dynamic>);
      final server = today(
        ((fixture['server'] as Map)['days'] as List).first
            as Map<String, dynamic>,
      );
      expect(local, hasLength(kWidgetRowsPerBucket));
      expect(server.first, _swapServerOnlyId);
      expect(server.skip(1), local.take(kWidgetRowsPerBucket - 1));
    });
  });

  group('the shared grouping fixture (OPH-463, #50)', () {
    test('client grouping matches the shared fixture', () async {
      tzdata.initializeTimeZones();
      final rendered = await _renderGroupingFixture();
      final file = File(_groupingFixturePath);
      if (Platform.environment['UPDATE_FIXTURES'] == '1') {
        file.writeAsStringSync(rendered);
      }
      expect(file.existsSync(), isTrue, reason: 'run with UPDATE_FIXTURES=1');
      // Byte for byte: the file is the one definition the server's grouping
      // is tested against, so a change here that is not written there (and
      // ported there) fails.
      expect(file.readAsStringSync(), rendered);
    });

    test('the fixture covers what the server must port', () {
      final cases =
          ((jsonDecode(File(_groupingFixturePath).readAsStringSync())
                      as Map)['cases']
                  as List)
              .cast<Map<String, dynamic>>();
      final raw = jsonEncode(cases);
      for (final key in WidgetBucket.values) {
        expect(raw, contains('"key":"${key.name}"'), reason: key.name);
      }
      for (final style in WidgetTimeStyle.values) {
        expect(
          raw,
          contains('"timeStyle":"${style.name}"'),
          reason: style.name,
        );
      }
      expect(raw, contains('"more":'));
      expect({for (final c in cases) c['tz']}.length, greaterThan(1));
      expect(cases.any((c) => c['private'] == true), isTrue);
      expect(cases.any((c) => (c['scope'] as Map)['mineFor'] != null), isTrue);
      for (final c in cases.where((c) => c['private'] == true)) {
        expect(jsonEncode(c['expected']), isNot(contains('"title"')));
      }
    });
  });
}

// ---------------------------------------------------------------------------
// The shared grouping fixture (OPH-463, WIDGETS §3.2).
//
// Dart is the fixture's author: `UPDATE_FIXTURES=1 flutter test` writes
// `test/fixtures/widget_grouping_cases.json`; every other run compares byte
// for byte, and the API's Vitest only reads it. Each case is the replica's
// rows (tasks with their assignees, projects, calendar events), a scope, a tz
// and "now"; `expected.selected` is what the replica query returns for that
// scope (newest id first — the input order the grouping's ties keep) and
// `expected.days` is `buildWidgetServerDays` over it, in the words-free shape
// `GET /widget/snapshot` answers.
//
// Times are written here as wall-clock strings in the case's tz and stored in
// the fixture as UTC instants. The Dart grouping works in the machine's local
// zone, so the driver hands it each instant's wall-clock in the case's tz as a
// local DateTime and turns the results back into instants the same way. No
// case sits on a wall-clock that a DST change of the case's tz makes
// ambiguous, and the machine's zone must not skip one either (Europe/Istanbul
// and UTC have no DST).
// ---------------------------------------------------------------------------

const _viewSwapFixturePath = 'test/fixtures/widget_view_swap.json';

/// The row only the server holds: created on another device, newest id.
const _swapServerOnlyId = 'T41';

/// 40 open tasks due at the same minute today, newest id first (the replica
/// query's order and the server's): the phone holds them, the server holds
/// one more. Past 32 rows, so an unstable sort would show itself. "now" is
/// the Swift tests' clock, 2025-11-12 11:00 in Europe/Istanbul.
String _renderViewSwapFixture() {
  final loc = tz.getLocation('Europe/Istanbul');
  final now = DateTime(2025, 11, 12, 11);
  Task row(int i) =>
      _task('T${'$i'.padLeft(2, '0')}', dueAt: DateTime(2025, 11, 12, 18));
  final phone = [for (var i = 40; i >= 1; i--) row(i)];
  final server = [row(41), ...phone];
  AwI18n.instance.setActiveCached(const Locale('tr'));
  final local = _json(buildWidgetSnapshot(phone, now: now))
    // The machine's zone would leak in through now.toUtc().
    ..['generatedAt'] = '2025-11-12T08:00:00.000Z';
  final days = buildWidgetServerDays(
    server,
    now: now,
    instant: (t) => tz.TZDateTime(
      loc,
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
    ).toUtc().toIso8601String(),
  );
  return '${const JsonEncoder.withIndent('  ').convert({
    'note': 'Written by the Dart test (UPDATE_FIXTURES=1); the Swift tests only read it. local is the phone\'s aw_widget_snapshot, server the GET /widget/snapshot body for the same rows plus one created elsewhere.',
    'local': local,
    'server': {'v': 1, 'generatedAt': '2025-11-12T08:00:00.000Z', 'tz': 'Europe/Istanbul', 'days': days},
  })}\n';
}

const _groupingFixturePath = 'test/fixtures/widget_grouping_cases.json';

String _fid(String name) => name.toUpperCase().padRight(26, '0');

Map<String, Object?> _ft(
  String name, {
  String ws = 'W1',
  String? due,
  String? when,
  String? completed,
  String status = 'open',
  String priority = 'none',
  String? project,
  String? color,
  int sort = 0,
  String? createdBy,
  List<String> assignees = const [],
  String? title,
}) => {
  'id': _fid(name),
  'workspaceId': _fid(ws),
  'title': title ?? 'Task $name',
  'status': status,
  'priority': priority,
  'sortOrder': sort,
  'dueAt': ?due,
  'startAt': ?when,
  'completedAt': ?completed,
  if (project != null) 'projectId': _fid(project),
  'colorRgb': ?color,
  if (createdBy != null) 'createdBy': _fid(createdBy),
  if (assignees.isNotEmpty) 'assignees': [for (final a in assignees) _fid(a)],
};

Map<String, Object?> _fp(
  String name, {
  String ws = 'W1',
  String color = '#2563EB',
  String status = 'active',
  int sort = 0,
}) => {
  'id': _fid(name),
  'workspaceId': _fid(ws),
  'name': 'Project $name',
  'colorRgb': color,
  'status': status,
  'sortOrder': sort,
};

Map<String, Object?> _fe(
  String name, {
  String ws = 'W1',
  required String starts,
  required String ends,
  bool allDay = false,
}) => {
  'id': _fid(name),
  'workspaceId': _fid(ws),
  'summary': 'Event $name',
  'startsAt': starts,
  'endsAt': ends,
  'allDay': allDay,
};

class _GroupingCase {
  const _GroupingCase(
    this.name, {
    required this.now,
    this.tz = 'Europe/Istanbul',
    this.workspaceIds = const ['W1'],
    this.mineFor,
    this.private = false,
    this.projects = const [],
    this.tasks = const [],
    this.events = const [],
  });

  final String name;

  /// Wall-clock in [tz], `yyyy-MM-ddTHH:mm`.
  final String now;
  final String tz;
  final List<String> workspaceIds;
  final String? mineFor;
  final bool private;
  final List<Map<String, Object?>> projects;
  final List<Map<String, Object?>> tasks;
  final List<Map<String, Object?>> events;
}

final List<_GroupingCase> _groupingCases = [
  _GroupingCase(
    'buckets, the local day edges and the +6/+7/+30/+31 limits',
    now: '2026-11-12T10:00',
    projects: [_fp('P1')],
    tasks: [
      _ft('late', due: '2026-11-11T09:00', priority: 'high', project: 'P1'),
      _ft('lateMidnight', due: '2026-11-11T23:59'),
      _ft('todayFirstMinute', due: '2026-11-12T00:00', priority: 'low'),
      _ft('todayPassed', due: '2026-11-12T08:00', project: 'P1'),
      _ft('todayLastMinute', due: '2026-11-12T23:59', priority: 'medium'),
      _ft('tomorrow', due: '2026-11-13T00:00'),
      _ft('plus6', due: '2026-11-18T12:00', project: 'P1'),
      _ft('plus7', due: '2026-11-19T12:00'),
      _ft('plus30', due: '2026-12-12T23:00'),
      _ft('plus31', due: '2026-12-13T00:00'),
      _ft('ownColor', due: '2026-11-14T09:00', color: '#16A34A'),
      _ft('somedayA', sort: 2),
      _ft('somedayB', sort: 1, project: 'P1'),
    ],
  ),
  _GroupingCase(
    'the local day, not the UTC one, just after midnight',
    now: '2026-11-13T01:30',
    tasks: [
      _ft('lastNight', due: '2026-11-12T23:00'),
      _ft('justAfter', due: '2026-11-13T00:30'),
      _ft('thisMorning', due: '2026-11-13T09:00'),
      _ft('nextMidnight', due: '2026-11-14T00:00'),
    ],
  ),
  _GroupingCase(
    'New York across the end of daylight saving time',
    now: '2026-10-31T12:00',
    tz: 'America/New_York',
    tasks: [
      _ft('friday', due: '2026-10-30T20:00'),
      _ft('tonight', due: '2026-10-31T23:30'),
      _ft('sundayMorning', due: '2026-11-01T09:00'),
      _ft('mondayEarly', due: '2026-11-02T00:30'),
      _ft('plus7', due: '2026-11-07T10:00'),
    ],
  ),
  _GroupingCase(
    '"when": a past one is today, a future one files the task, the deadline caps it',
    now: '2026-11-12T10:00',
    tasks: [
      _ft('whenPast', when: '2026-11-10T00:00', due: '2026-11-20T17:00'),
      _ft('whenFuture', when: '2026-11-14T00:00'),
      _ft('whenAfterDue', when: '2026-11-25T00:00', due: '2026-11-16T12:00'),
      _ft('whenToday', when: '2026-11-12T00:00', due: '2026-11-12T15:00'),
      _ft('whenButLate', when: '2026-11-12T00:00', due: '2026-11-10T09:00'),
      _ft('whenPastNoDue', when: '2026-11-01T00:00'),
    ],
  ),
  _GroupingCase(
    'finished work: today\'s stays at the bottom, older is gone, a later day drops it',
    now: '2026-11-12T10:00',
    tasks: [
      _ft('openToday', due: '2026-11-12T11:00'),
      _ft(
        'doneToday',
        due: '2026-11-12T08:00',
        status: 'completed',
        completed: '2026-11-12T09:00',
      ),
      _ft('doneNoDue', status: 'completed', completed: '2026-11-12T09:10'),
      _ft(
        'doneYesterday',
        due: '2026-11-12T12:00',
        status: 'completed',
        completed: '2026-11-11T18:00',
      ),
      _ft(
        'doneLateToday',
        due: '2026-11-11T10:00',
        status: 'completed',
        completed: '2026-11-12T09:30',
      ),
      _ft('scheduled', due: '2026-11-13T10:00', status: 'scheduled'),
      _ft('inProgress', due: '2026-11-12T16:00', status: 'in_progress'),
      _ft('waiting', status: 'waiting'),
      _ft('inbox', due: '2026-11-12T12:00', status: 'inbox'),
      _ft('cancelled', due: '2026-11-12T12:00', status: 'cancelled'),
    ],
  ),
  _GroupingCase(
    'the calendar in a one-workspace scope',
    now: '2026-11-12T10:00',
    projects: [_fp('P1')],
    tasks: [
      _ft('tiedWithEvent', due: '2026-11-12T15:00', project: 'P1'),
      _ft('weekTask', due: '2026-11-15T09:00'),
    ],
    events: [
      _fe(
        'allDayToday',
        starts: '2026-11-12T00:00',
        ends: '2026-11-13T00:00',
        allDay: true,
      ),
      _fe('standup', starts: '2026-11-12T09:30', ends: '2026-11-12T10:00'),
      _fe('tied', starts: '2026-11-12T15:00', ends: '2026-11-12T15:30'),
      _fe('overnight', starts: '2026-11-12T22:00', ends: '2026-11-13T02:00'),
      _fe('trip', starts: '2026-11-10T08:00', ends: '2026-11-14T18:00'),
      _fe('finished', starts: '2026-11-11T09:00', ends: '2026-11-11T10:00'),
      _fe('review', starts: '2026-11-14T15:00', ends: '2026-11-14T16:00'),
      _fe(
        'holiday',
        starts: '2026-11-16T00:00',
        ends: '2026-11-17T00:00',
        allDay: true,
      ),
      _fe(
        'conference',
        starts: '2026-11-11T00:00',
        ends: '2026-11-14T00:00',
        allDay: true,
      ),
      _fe('farAway', starts: '2026-12-20T10:00', ends: '2026-12-20T11:00'),
      _fe(
        'otherWorkspace',
        ws: 'W2',
        starts: '2026-11-12T13:00',
        ends: '2026-11-12T14:00',
      ),
    ],
  ),
  _GroupingCase(
    'mine across two workspaces: my work only, and never the calendar',
    now: '2026-11-12T10:00',
    workspaceIds: ['W1', 'W2'],
    mineFor: 'U1',
    projects: [
      _fp('P1'),
      _fp('P2', ws: 'W2', color: '#DC2626'),
      _fp('P3', ws: 'W3'),
    ],
    tasks: [
      _ft('onMe', due: '2026-11-12T12:00', createdBy: 'U2', assignees: ['U1']),
      _ft(
        'madeByMe',
        ws: 'W2',
        due: '2026-11-13T12:00',
        createdBy: 'U1',
        project: 'P2',
      ),
      _ft(
        'madeByMeTaken',
        due: '2026-11-12T13:00',
        createdBy: 'U1',
        assignees: ['U2'],
      ),
      _ft('colleagues', ws: 'W2', due: '2026-11-12T14:00', createdBy: 'U2'),
      _ft(
        'shared',
        due: '2026-11-12T16:00',
        createdBy: 'U2',
        assignees: ['U2', 'U1'],
        project: 'P1',
      ),
      _ft('outOfScope', ws: 'W3', due: '2026-11-12T12:00', assignees: ['U1']),
    ],
    events: [
      _fe('meeting', starts: '2026-11-12T11:00', ends: '2026-11-12T12:00'),
    ],
  ),
  _GroupingCase(
    'mine in one workspace is a shared workspace: no calendar either',
    now: '2026-11-12T10:00',
    mineFor: 'U1',
    tasks: [
      _ft('onMe', due: '2026-11-12T12:00', createdBy: 'U2', assignees: ['U1']),
    ],
    events: [
      _fe('meeting', starts: '2026-11-12T11:00', ends: '2026-11-12T12:00'),
    ],
  ),
  _GroupingCase(
    'private: the same rows and numbers, no title anywhere',
    now: '2026-11-12T10:00',
    private: true,
    projects: [_fp('P1')],
    tasks: [
      _ft('late', due: '2026-11-10T09:00', project: 'P1'),
      _ft('today', due: '2026-11-12T14:00'),
      _ft('someday'),
    ],
    events: [
      _fe('lunch', starts: '2026-11-12T12:00', ends: '2026-11-12T13:00'),
    ],
  ),
  _GroupingCase(
    'twelve rows a bucket, the open rest counted as more',
    now: '2026-11-12T10:00',
    projects: [_fp('P1')],
    tasks: [
      for (var i = 0; i < 15; i++)
        _ft(
          'late${i.toString().padLeft(2, '0')}',
          due:
              '2026-11-${(i % 9 + 1).toString().padLeft(2, '0')}'
              'T${(8 + i ~/ 9).toString().padLeft(2, '0')}:00',
          project: 'P1',
        ),
      for (var i = 0; i < 13; i++)
        _ft(
          'today${i.toString().padLeft(2, '0')}',
          due:
              '2026-11-12T${(10 + i ~/ 2).toString().padLeft(2, '0')}'
              ':${i.isEven ? '00' : '30'}',
          project: 'P1',
        ),
      _ft(
        'doneA',
        due: '2026-11-12T09:00',
        status: 'completed',
        completed: '2026-11-12T09:05',
      ),
      _ft(
        'doneB',
        due: '2026-11-12T09:30',
        status: 'completed',
        completed: '2026-11-12T09:35',
      ),
    ],
  ),
  _GroupingCase(
    'project views: every live project, an empty one too, never an archived one',
    now: '2026-11-12T10:00',
    projects: [
      _fp('P1', sort: 1),
      _fp('P2', color: '#7C3AED', sort: 0),
      _fp('P3', color: '#0891B2', status: 'archived'),
    ],
    tasks: [
      _ft('inP1', due: '2026-11-12T12:00', project: 'P1'),
      _ft('inArchived', due: '2026-11-12T13:00', project: 'P3'),
      _ft('noProject', due: '2026-11-13T09:00'),
      _ft('unknownProject', due: '2026-11-13T10:00', project: 'P9'),
    ],
  ),
  _GroupingCase('nothing at all', now: '2026-11-12T10:00'),
  _GroupingCase(
    'the year\'s end',
    now: '2026-12-30T20:00',
    tasks: [
      _ft('lastYear', due: '2026-12-29T09:00'),
      _ft('newYearsEve', due: '2026-12-31T22:00'),
      _ft('newYear', due: '2027-01-01T10:00'),
      _ft('january', due: '2027-01-20T10:00'),
    ],
  ),
  _GroupingCase(
    'ties keep the newest id first',
    now: '2026-11-12T10:00',
    tasks: [
      _ft('tieA', due: '2026-11-12T15:00'),
      _ft('tieC', due: '2026-11-12T15:00'),
      _ft('tieB', due: '2026-11-12T15:00'),
      _ft('dateless1'),
      _ft('dateless3'),
      _ft('dateless2'),
    ],
  ),
  // #50 (PR2-03): past 32 rows a tie still keeps the newest id first, on
  // both sides — the phone's sort is not allowed to differ from the server's.
  _GroupingCase(
    'ties past 32 rows keep the newest id first',
    now: '2026-11-12T10:00',
    private: true,
    tasks: [
      for (var i = 1; i <= 40; i++)
        _ft('tie${'$i'.padLeft(2, '0')}', due: '2026-11-12T15:00'),
      for (var i = 1; i <= 40; i++) _ft('free${'$i'.padLeft(2, '0')}'),
    ],
  ),
];

/// The fixture as it must be on disk.
Future<String> _renderGroupingFixture() async {
  final cases = <Map<String, Object?>>[];
  for (final c in _groupingCases) {
    final loc = tz.getLocation(c.tz);

    String instantOfWall(String wall) {
      final w = DateTime.parse(wall);
      final at = tz.TZDateTime(loc, w.year, w.month, w.day, w.hour, w.minute);
      return DateTime.fromMillisecondsSinceEpoch(
        at.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
    }

    Map<String, Object?> instants(Map<String, Object?> row) => {
      for (final MapEntry(:key, :value) in row.entries)
        key:
            const {
              'dueAt',
              'startAt',
              'completedAt',
              'startsAt',
              'endsAt',
            }.contains(key)
            ? instantOfWall(value! as String)
            : value,
    };

    final input = <String, Object?>{
      'name': c.name,
      'now': instantOfWall(c.now),
      'tz': c.tz,
      'scope': {
        'workspaceIds': [for (final ws in c.workspaceIds) _fid(ws)],
        if (c.mineFor != null) 'mineFor': _fid(c.mineFor!),
      },
      'private': c.private,
      'projects': c.projects,
      'tasks': [for (final t in c.tasks) instants(t)],
      'events': [for (final e in c.events) instants(e)],
    };
    cases.add({...input, 'expected': await _groupFixtureCase(input, loc)});
  }
  return '${const JsonEncoder.withIndent('  ').convert({'contract': 'docs/WIDGETS.md 3.2 Widget self-fetch contract', 'note': 'Written by the Dart test (UPDATE_FIXTURES=1); every other reader only compares. Instants are UTC; tz is the IANA zone every local day is taken in. expected.selected is what the replica query returns for the scope, newest id first; expected.days is GET /widget/snapshot days for that input.', 'cases': cases})}\n';
}

/// One case through the app's own path: the rows into a replica, the replica
/// query `publishWidgetFromReplica` runs, then [buildWidgetServerDays].
Future<Map<String, Object?>> _groupFixtureCase(
  Map<String, Object?> input,
  tz.Location loc,
) async {
  /// The instant's wall-clock in the case's tz, as a local DateTime.
  DateTime wall(Object? iso) {
    final at = tz.TZDateTime.from(DateTime.parse(iso! as String), loc);
    return DateTime(at.year, at.month, at.day, at.hour, at.minute, at.second);
  }

  /// The way back: a local wall-clock read as the case's tz, as UTC ISO.
  String instant(DateTime w) {
    final at = tz.TZDateTime(
      loc,
      w.year,
      w.month,
      w.day,
      w.hour,
      w.minute,
      w.second,
      w.millisecond,
    );
    return DateTime.fromMillisecondsSinceEpoch(
      at.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
  }

  DateTime? maybeWall(Object? iso) => iso == null ? null : wall(iso);

  final db = AwDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  try {
    for (final p in (input['projects']! as List).cast<Map<String, Object?>>()) {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: p['id']! as String,
              workspaceId: p['workspaceId']! as String,
              name: p['name']! as String,
              colorRgb: Value(p['colorRgb']! as String),
              status: Value(p['status']! as String),
              sortOrder: Value(p['sortOrder']! as int),
            ),
          );
    }
    for (final t in (input['tasks']! as List).cast<Map<String, Object?>>()) {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: t['id']! as String,
              workspaceId: t['workspaceId']! as String,
              title: t['title']! as String,
              status: Value(t['status']! as String),
              priority: Value(t['priority']! as String),
              sortOrder: Value(t['sortOrder']! as int),
              dueAt: Value(maybeWall(t['dueAt'])),
              startAt: Value(maybeWall(t['startAt'])),
              completedAt: Value(maybeWall(t['completedAt'])),
              projectId: Value(t['projectId'] as String?),
              colorRgb: Value(t['colorRgb'] as String?),
              createdBy: Value(t['createdBy'] as String?),
            ),
          );
      for (final user in (t['assignees'] as List? ?? const []).cast<String>()) {
        await db
            .into(db.taskAssignments)
            .insert(
              TaskAssignmentsCompanion.insert(
                id: '${t['id']}:$user',
                workspaceId: t['workspaceId']! as String,
                taskId: t['id']! as String,
                userId: user,
              ),
            );
      }
    }
    for (final e in (input['events']! as List).cast<Map<String, Object?>>()) {
      await db
          .into(db.externalEvents)
          .insert(
            ExternalEventsCompanion.insert(
              id: e['id']! as String,
              workspaceId: e['workspaceId']! as String,
              summary: Value(e['summary'] as String?),
              startsAt: wall(e['startsAt']),
              endsAt: wall(e['endsAt']),
              isAllDay: Value(e['allDay']! as bool),
            ),
          );
    }

    final now = wall(input['now']);
    final scope = TaskScope.fromJson(input['scope'])!;
    final replica = await readWidgetReplica(db, scope: scope, now: now);
    return {
      'selected': [for (final task in replica.tasks) task.id],
      'days': buildWidgetServerDays(
        replica.tasks,
        events: replica.events,
        now: now,
        projectColorById: {
          for (final project in replica.projects) project.id: project.colorRgb,
        },
        projects: replica.projects,
        hideTitles: input['private']! as bool,
        instant: instant,
      ),
    };
  } finally {
    await db.close();
  }
}
