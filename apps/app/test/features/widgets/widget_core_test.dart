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
      expect(snap.buckets.single.items.single.time, '11:30');
      expect(snap.strings['allCaughtUp'], 'All caught up');

      AwI18n.instance.setActiveCached(const Locale('tr'));
      final tr = buildWidgetSnapshot([
        _task('t', dueAt: DateTime(2026, 7, 17, 11, 30)),
      ], now: now);
      expect(tr.date.weekday, 'Cuma');
      expect(tr.date.month, 'Temmuz');
      expect(tr.buckets.single.label, 'Bugün');
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
