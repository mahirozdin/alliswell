import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/list_sort.dart';
import 'package:alliswell/src/features/calendar/data/external_event.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_sort.dart';

/// OPH-305 — choosing the order inside Home's groups.
///
/// Home groups by day and always will: that is what Home IS (§20). What it
/// never offered was a say in the order WITHIN a group, which is what the user
/// asked for — *"sort and categorise upcoming tasks … listed by the order of
/// priority"*. Sorting existed for notes and for files and had simply never
/// reached the one list people spend their day in.
///
/// Two written rules survive every order, and they are what these tests are
/// really guarding: a finished task sinks to the bottom of its group (§20 C1)
/// whatever the sort says, and the default order is byte-for-byte the
/// chronological one Home has always had — a preference nobody set must change
/// nothing.
Task _task(
  String id, {
  DateTime? dueAt,
  String priority = 'none',
  String status = 'open',
  String? title,
  int sortOrder = 0,
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
);

ExternalEvent _event(String id, {required DateTime startsAt}) => ExternalEvent(
  id: id,
  summary: id,
  startsAt: startsAt,
  endsAt: startsAt.add(const Duration(hours: 1)),
  isAllDay: false,
  isBusy: true,
);

void main() {
  final now = DateTime(2026, 7, 14, 9, 0); // Tuesday morning
  final today = DateTime(2026, 7, 14);

  List<String> idsOfTodayUnder(
    AwSortState? sort,
    List<Task> tasks, {
    List<ExternalEvent> events = const [],
  }) {
    final groups = groupTasksForHome(
      tasks,
      now: now,
      events: events,
      sort: sort,
    );
    final group = groups.singleWhere((g) => g.bucket == HomeBucket.today);
    return [
      for (final item in group.items)
        switch (item) {
          TaskItem(:final task) => task.id,
          EventItem(:final event) => event.id,
        },
    ];
  }

  test('priority puts urgent first inside the day', () {
    final ids = idsOfTodayUnder(const AwSortState('priority'), [
      _task('low', dueAt: today.add(const Duration(hours: 10))),
      _task(
        'urgent',
        priority: 'urgent',
        dueAt: today.add(const Duration(hours: 18)),
      ),
      _task(
        'medium',
        priority: 'medium',
        dueAt: today.add(const Duration(hours: 12)),
      ),
    ]);
    // Chronologically this is low, medium, urgent — the whole point is that it
    // is not, once the user has asked for priority.
    expect(ids, ['urgent', 'medium', 'low']);
  });

  test('a finished task still sinks, whatever the order says', () {
    final ids = idsOfTodayUnder(const AwSortState('priority'), [
      _task(
        'done-urgent',
        priority: 'urgent',
        status: 'completed',
        dueAt: today.add(const Duration(hours: 10)),
      ),
      _task('open-low', dueAt: today.add(const Duration(hours: 11))),
    ]);
    // §20 C1: done work never sits above work that is still waiting. Priority
    // is a preference; this is a rule.
    expect(ids, ['open-low', 'done-urgent']);
  });

  test('title folds Turkish before comparing', () {
    final ids = idsOfTodayUnder(const AwSortState('title', descending: false), [
      // The clock and the alphabet deliberately disagree here: chronological
      // would give ['a', 'b']. A test both orders satisfy proves nothing.
      _task('a', title: 'Islak', dueAt: today.add(const Duration(hours: 10))),
      _task('b', title: 'Ilık', dueAt: today.add(const Duration(hours: 11))),
    ]);
    // Neither SQLite nor MySQL folds ı→i (ADR-0013); `foldSearchText` does, and
    // a sort that disagrees with the app's own search would be its own bug.
    // Folded: "ilik" < "islak".
    expect(ids, ['b', 'a']);
  });

  test('an event has no priority, so it sorts as the lowest one', () {
    final ids = idsOfTodayUnder(
      const AwSortState('priority'),
      [
        _task(
          'urgent',
          priority: 'urgent',
          dueAt: today.add(const Duration(hours: 18)),
        ),
      ],
      events: [
        _event('meeting', startsAt: today.add(const Duration(hours: 10))),
      ],
    );
    // A meeting is not something you choose when to do, so it has nothing to
    // rank. Landing it with the unranked work is the predictable answer.
    expect(ids, ['urgent', 'meeting']);
  });

  test('reversing the date order actually reverses it', () {
    final tasks = [
      _task('early', dueAt: today.add(const Duration(hours: 9))),
      _task('late', dueAt: today.add(const Duration(hours: 18))),
    ];
    expect(
      idsOfTodayUnder(const AwSortState('date', descending: false), tasks),
      ['early', 'late'],
    );
    // The menu offers "Reverse order" for every choice. `date` used to
    // short-circuit straight to the chronological comparator, so the control
    // was there and did nothing — which is worse than not offering it.
    expect(idsOfTodayUnder(const AwSortState('date'), tasks), [
      'late',
      'early',
    ]);
  });

  test('no preference means exactly the order Home always had', () {
    final tasks = [
      _task('late', dueAt: today.add(const Duration(hours: 18))),
      _task(
        'early',
        priority: 'urgent',
        dueAt: today.add(const Duration(hours: 9, minutes: 30)),
      ),
    ];
    expect(idsOfTodayUnder(null, tasks), ['early', 'late']);
    // …and an unrecognised preference lands on the first choice, which IS that
    // order — a preference that outlived its option must not reshuffle the day.
    expect(
      idsOfTodayUnder(
        AwSortState.parse('galaxies:desc', kTaskSortChoices),
        tasks,
      ),
      ['early', 'late'],
    );
  });
}
