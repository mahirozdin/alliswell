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

  test('a future event within the horizon lands in Next 30 days', () {
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
          'bu ay içinde', // +10 days → within the 30-day horizon
          startsAt: DateTime(2026, 7, 24, 9),
          endsAt: DateTime(2026, 7, 24, 10),
        ),
      ],
    );

    expect(groups.map((g) => g.bucket), [
      HomeBucket.tomorrow,
      HomeBucket.next30Days,
    ]);
  });

  test('recurring instances past the 30-day horizon never reach Home', () {
    // now = 2026-07-14 → horizon = 2026-08-13.
    final groups = groupTasksForHome(
      const [],
      now: now,
      events: [
        _event(
          'bu ay', // +10d, in
          startsAt: DateTime(2026, 7, 24, 9),
          endsAt: DateTime(2026, 7, 24, 10),
        ),
        _event(
          'gelecek ay', // +41d, out
          startsAt: DateTime(2026, 8, 24, 9),
          endsAt: DateTime(2026, 8, 24, 10),
        ),
        _event(
          'daha sonra', // +72d, out
          startsAt: DateTime(2026, 9, 24, 9),
          endsAt: DateTime(2026, 9, 24, 10),
        ),
      ],
    );

    // Only the in-horizon instance survives; the far ones live on Calendar.
    expect(groups.map((g) => g.bucket), [HomeBucket.next30Days]);
    expect(groups.single.items, hasLength(1));
    expect((groups.single.items.single as EventItem).event.id, 'bu ay');
  });

  test('the task list horizon is 30 days: +29d shows, +31d is dropped', () {
    final groups = groupTasksForHome([
      _task('yakın', dueAt: DateTime(2026, 8, 12, 9)), // +29d, in
      _task('uzak', dueAt: DateTime(2026, 8, 14, 9)), // +31d, out
    ], now: now);

    final ids = groups
        .expand((g) => g.items)
        .whereType<TaskItem>()
        .map((i) => i.task.id);
    expect(ids, ['yakın'], reason: '+31d is beyond the horizon → not on Home');
    expect(
      groups.single.bucket,
      HomeBucket.next30Days,
      reason: '+29d is past this-week',
    );
  });

  test('Overdue, No-date and Today stay lit while a day is selected', () {
    final groups = groupTasksForHome(
      [
        _task('gecikmiş', dueAt: DateTime(2026, 7, 10)), // overdue
        _task('tarihsiz'), // no date
        _task('bugünkü', dueAt: DateTime(2026, 7, 14, 18)), // today
        _task('yarınki', dueAt: DateTime(2026, 7, 15, 9)), // tomorrow
      ],
      now: now,
      selectedDay: DateTime(2026, 7, 25), // a day with nothing on it
    );

    // Order: Overdue → No date → Today → Tomorrow (the empty Selected-day
    // group drops out).
    expect(groups.map((g) => g.bucket), [
      HomeBucket.overdue,
      HomeBucket.noDate,
      HomeBucket.today,
      HomeBucket.tomorrow,
    ]);
    // What demands attention NOW never fades; only the future groups dim
    // (feedback round 6).
    for (final lit in [
      HomeBucket.overdue,
      HomeBucket.noDate,
      HomeBucket.today,
    ]) {
      expect(groups.singleWhere((g) => g.bucket == lit).dimmed, isFalse);
    }
    expect(
      groups.singleWhere((g) => g.bucket == HomeBucket.tomorrow).dimmed,
      isTrue,
    );
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
