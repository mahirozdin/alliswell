import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_when.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-372 (ADR-0053) — the pure "when" rules every surface files by.
Task _task({DateTime? start, DateTime? due, int? minutes}) => Task(
  id: 'T1',
  workspaceId: 'W1',
  title: 'İş',
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  startAt: start,
  dueAt: due,
  estimatedMinutes: minutes,
);

void main() {
  final today = DateTime(2030, 6, 10);

  group('awWhenIso', () {
    test('stores the local midnight of the chosen day', () {
      final iso = awWhenIso(DateTime(2030, 6, 12, 15, 45));
      final back = DateTime.parse(iso).toLocal();
      expect(back, DateTime(2030, 6, 12));
      expect(iso.endsWith('Z'), isTrue, reason: 'UTC on the wire');
    });

    test('round-trips through taskWhenDay', () {
      final task = _task(
        start: DateTime.parse(awWhenIso(DateTime(2030, 6, 1))),
      );
      expect(taskWhenDay(task), DateTime(2030, 6, 1));
      expect(taskWhenDay(_task()), isNull);
    });
  });

  group('taskPlanDay', () {
    test('a past "when" rolls forward to today', () {
      expect(taskPlanDay(_task(start: DateTime(2030, 6, 8)), today), today);
    });

    test('a future "when" is that day', () {
      expect(
        taskPlanDay(
          _task(start: DateTime(2030, 6, 12), due: DateTime(2030, 6, 20, 17)),
          today,
        ),
        DateTime(2030, 6, 12),
      );
    });

    test('a "when" after the deadline gives the deadline day', () {
      expect(
        taskPlanDay(
          _task(start: DateTime(2030, 6, 25), due: DateTime(2030, 6, 14, 17)),
          today,
        ),
        DateTime(2030, 6, 14),
      );
    });

    test('due only gives the due day; neither gives null', () {
      expect(
        taskPlanDay(_task(due: DateTime(2030, 6, 11, 9)), today),
        DateTime(2030, 6, 11),
      );
      expect(taskPlanDay(_task(), today), isNull);
    });
  });

  test('overdue goes by the deadline alone', () {
    // Started long ago, due later: on Today, not Overdue.
    expect(
      taskIsOverdueOn(
        _task(start: DateTime(2030, 5, 1), due: DateTime(2030, 6, 12)),
        today,
      ),
      isFalse,
    );
    // "When" today, deadline yesterday: Overdue.
    expect(
      taskIsOverdueOn(
        _task(start: today, due: DateTime(2030, 6, 9, 23, 59)),
        today,
      ),
      isTrue,
    );
    expect(taskIsOverdueOn(_task(start: DateTime(2030, 5, 1)), today), isFalse);
    // Due earlier today is not overdue by DAY (Home's rule).
    expect(
      taskIsOverdueOn(_task(due: DateTime(2030, 6, 10, 8)), today),
      isFalse,
    );
  });

  group('awFormatDuration', () {
    tearDown(() => AwI18n.instance.setLocale(const Locale('en')));

    test('English', () async {
      await AwI18n.instance.setLocale(const Locale('en'));
      expect(awFormatDuration(15), '15 min');
      expect(awFormatDuration(60), '1 h');
      expect(awFormatDuration(90), '1 h 30 min');
      expect(awFormatDuration(1440), '24 h');
    });

    test('Turkish', () async {
      await AwI18n.instance.setLocale(const Locale('tr'));
      expect(awFormatDuration(15), '15 dk');
      expect(awFormatDuration(60), '1 sa');
      expect(awFormatDuration(90), '1 sa 30 dk');
      expect(awFormatDuration(1440), '24 sa');
    });
  });
}
