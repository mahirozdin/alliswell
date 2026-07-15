import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/calendar/data/external_event.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';

/// OPH-084 — the user's calendar in Home's chronological stream (§12: "the
/// single chronological view where everything shows").
Task _task(String id, {DateTime? dueAt, int sortOrder = 0}) => Task(
  id: id,
  workspaceId: 'W1',
  title: id,
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: sortOrder,
  revision: 1,
  dueAt: dueAt,
);

ExternalEvent _event(
  String id, {
  required DateTime startsAt,
  required DateTime endsAt,
  bool isAllDay = false,
}) => ExternalEvent(
  id: id,
  summary: id,
  startsAt: startsAt,
  endsAt: endsAt,
  isAllDay: isAllDay,
  isBusy: true,
);

void main() {
  final now = DateTime(2026, 7, 14, 15, 30); // Tuesday afternoon

  test('a meeting and a task share one chronological stream', () {
    final groups = groupTasksForHome(
      [_task('16:00 iş', dueAt: DateTime(2026, 7, 14, 16))],
      now: now,
      events: [
        _event(
          '10:00 toplantı',
          startsAt: DateTime(2026, 7, 14, 10),
          endsAt: DateTime(2026, 7, 14, 11),
        ),
      ],
    );

    final today = groups.singleWhere((g) => g.bucket == HomeBucket.today);
    // The meeting sorts ABOVE the task because it happens first — that is what
    // makes Home chronological rather than "tasks, then a calendar sidebar".
    expect(today.items.map((i) => i.at), [
      DateTime(2026, 7, 14, 10),
      DateTime(2026, 7, 14, 16),
    ]);
    expect(today.items.first, isA<EventItem>());
    expect(today.items.last, isA<TaskItem>());
  });

  test('a meeting that already happened is not a debt you owe', () {
    final groups = groupTasksForHome(
      [_task('gecikmiş iş', dueAt: DateTime(2026, 7, 10, 9))],
      now: now,
      events: [
        _event(
          'dünkü toplantı',
          startsAt: DateTime(2026, 7, 13, 10),
          endsAt: DateTime(2026, 7, 13, 11),
        ),
      ],
    );

    // Overdue means "you still have to do this". A past meeting is history: it
    // leaves Home entirely rather than nagging next to real debts.
    final overdue = groups.singleWhere((g) => g.bucket == HomeBucket.overdue);
    expect(overdue.items, hasLength(1));
    expect(overdue.items.single, isA<TaskItem>());
    expect(
      groups.expand((g) => g.items).whereType<EventItem>(),
      isEmpty,
      reason: 'a finished meeting has no bucket at all',
    );
  });

  test('an ongoing multi-day event belongs to today, once', () {
    final groups = groupTasksForHome(
      const [],
      now: now,
      events: [
        _event(
          'seyahat',
          startsAt: DateTime(2026, 7, 12, 9), // started Sunday
          endsAt: DateTime(2026, 7, 16, 18), // runs to Thursday
        ),
      ],
    );

    // It is happening NOW, so it belongs to Today — not to Overdue (it started
    // in the past) and not repeated across every day it spans.
    expect(groups.map((g) => g.bucket), [HomeBucket.today]);
    expect(groups.single.items, hasLength(1));
  });

  test('a future event lands in its own bucket', () {
    final groups = groupTasksForHome(
      const [],
      now: now,
      events: [
        _event(
          'yarınki toplantı',
          startsAt: DateTime(2026, 7, 15, 9),
          endsAt: DateTime(2026, 7, 15, 10),
        ),
        _event(
          'gelecek ay',
          startsAt: DateTime(2026, 8, 20, 9),
          endsAt: DateTime(2026, 8, 20, 10),
        ),
      ],
    );

    expect(groups.map((g) => g.bucket), [
      HomeBucket.tomorrow,
      HomeBucket.later,
    ]);
  });

  test('a selected day gathers that day’s meetings too', () {
    final groups = groupTasksForHome(
      [_task('o günkü iş', dueAt: DateTime(2026, 7, 20, 14))],
      now: now,
      selectedDay: DateTime(2026, 7, 20),
      events: [
        _event(
          'o günkü toplantı',
          startsAt: DateTime(2026, 7, 20, 9),
          endsAt: DateTime(2026, 7, 20, 10),
        ),
        _event(
          'başka gün',
          startsAt: DateTime(2026, 7, 21, 9),
          endsAt: DateTime(2026, 7, 21, 10),
        ),
      ],
    );

    final selected = groups.first;
    expect(selected.bucket, HomeBucket.selectedDay);
    expect(selected.dimmed, isFalse);
    expect(selected.items, hasLength(2)); // the meeting AND the task
    expect(selected.items.first, isA<EventItem>()); // 09:00 before 14:00
    expect(groups.skip(1).every((g) => g.dimmed), isTrue);
  });

  test('an all-day event marks exactly one day', () {
    // Google's all-day end is exclusive: the 5th runs 05-00:00 → 06-00:00.
    final oneDay = _event(
      'tatil',
      startsAt: DateTime(2026, 7, 15),
      endsAt: DateTime(2026, 7, 16),
      isAllDay: true,
    );
    expect(daysOfEvent(oneDay), [DateTime(2026, 7, 15)]);
    expect(daysWithEvents([oneDay]), {DateTime(2026, 7, 15)});

    final groups = groupTasksForHome(const [], now: now, events: [oneDay]);
    expect(groups.single.bucket, HomeBucket.tomorrow);
  });

  test('no calendar connected changes nothing', () {
    final groups = groupTasksForHome([
      _task('iş', dueAt: DateTime(2026, 7, 14, 18)),
    ], now: now);
    expect(groups.single.bucket, HomeBucket.today);
    expect(groups.single.items.single, isA<TaskItem>());
  });
}
