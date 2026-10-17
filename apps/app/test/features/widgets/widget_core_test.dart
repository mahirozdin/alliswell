import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: id,
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
);

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
