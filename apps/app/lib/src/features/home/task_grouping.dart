import '../calendar/data/external_event.dart';
import '../tasks/data/task.dart';

/// Chronological buckets of the home list (feedback round 1). When a calendar
/// day is selected its group sorts first and the rest render dimmed.
enum HomeBucket {
  selectedDay,
  overdue,
  noDate,
  today,
  tomorrow,
  thisWeek,
  next30Days,
}

extension HomeBucketLabel on HomeBucket {
  String get label => switch (this) {
    HomeBucket.selectedDay => 'Selected day',
    HomeBucket.overdue => 'Overdue',
    HomeBucket.noDate => 'No date',
    HomeBucket.today => 'Today',
    HomeBucket.tomorrow => 'Tomorrow',
    HomeBucket.thisWeek => 'This week',
    HomeBucket.next30Days => 'Next 30 days',
  };
}

/// How far ahead Home looks. Beyond this the list would fill with every future
/// instance of a recurring calendar event and bury real work, so anything
/// dated past `today + kHomeHorizonDays` lives on the Calendar tab instead
/// (OPH-102). The month grid's dots are NOT bounded by this — only the list.
const int kHomeHorizonDays = 30;

/// One row of Home. §12 calls Home "the single chronological view where
/// everything shows" — so a 10:00 meeting sorts above a 16:00 task rather than
/// living in a separate list (OPH-084).
sealed class HomeItem {
  const HomeItem();

  /// The instant this row sits at. Null only for dateless tasks, which sink to
  /// the bottom of their group.
  DateTime? get at;
}

class TaskItem extends HomeItem {
  const TaskItem(this.task);

  final Task task;

  @override
  DateTime? get at => task.dueAt;
}

class EventItem extends HomeItem {
  const EventItem(this.event);

  final ExternalEvent event;

  @override
  DateTime? get at => event.startsAt;
}

class HomeGroup {
  const HomeGroup({
    required this.bucket,
    required this.items,
    required this.dimmed,
  });

  final HomeBucket bucket;
  final List<HomeItem> items;

  /// True when a day is selected and this group is not that day's group.
  final bool dimmed;
}

DateTime dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Groups Home's rows. `selectedDay` (a local calendar day) pulls that day into
/// a highlighted first group; everything else keeps its chronological order but
/// renders dimmed — EXCEPT the No-date group (see below).
///
/// Order (OPH-102): Selected day? → Overdue → **No date** → Today → Tomorrow →
/// This week → Next 30 days. Two rules make it honest to the user:
///
/// - **A 30-day horizon; there is no open-ended "Later".** Anything dated more
///   than [kHomeHorizonDays] days out — tasks AND events — is dropped from Home
///   and lives on the Calendar tab, so recurring meetings can't bury real work.
/// - **Dateless work sits at the top and is never dimmed.** A task with no date
///   is "every day's work": it renders directly under Overdue, above Today, and
///   stays full-opacity even while a calendar day is selected.
///
/// Since OPH-084 the user's own calendar rides along (§12: "everything shows").
/// Two more rules keep events honest:
///
/// - **Events never land in Overdue.** A meeting that already happened is not a
///   debt you owe. Past events drop out of Home entirely.
/// - **An ongoing event belongs to today**, not the day it started: a trip that
///   began Monday and runs through Friday is happening NOW. It appears once, at
///   the first day it touches that has not passed.
List<HomeGroup> groupTasksForHome(
  List<Task> tasks, {
  required DateTime now,
  DateTime? selectedDay,
  List<ExternalEvent> events = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final weekEnd = today.add(const Duration(days: 7));
  final horizon = today.add(const Duration(days: kHomeHorizonDays));

  final byBucket = <HomeBucket, List<HomeItem>>{
    for (final b in HomeBucket.values) b: [],
  };

  /// Bucket for a NON-past day (callers handle past/overdue themselves).
  /// Returns null when the day is beyond the horizon → not shown on Home.
  HomeBucket? futureBucketForDay(DateTime day) {
    if (day == today) return HomeBucket.today;
    if (day == tomorrow) return HomeBucket.tomorrow;
    if (day.isBefore(weekEnd)) return HomeBucket.thisWeek; // +2..+6
    if (!day.isAfter(horizon)) return HomeBucket.next30Days; // +7..+30
    return null; // beyond the horizon
  }

  for (final task in tasks) {
    final due = task.dueAt;
    if (selectedDay != null && due != null && dayOf(due) == selectedDay) {
      byBucket[HomeBucket.selectedDay]!.add(TaskItem(task));
      continue;
    }
    if (due == null) {
      byBucket[HomeBucket.noDate]!.add(TaskItem(task));
      continue;
    }
    final day = dayOf(due);
    if (day.isBefore(today)) {
      // A task's deadline CAN be in the past — that is the whole point of
      // Overdue (a beyond-horizon FUTURE task, by contrast, is simply dropped).
      byBucket[HomeBucket.overdue]!.add(TaskItem(task));
      continue;
    }
    final bucket = futureBucketForDay(day);
    if (bucket != null) byBucket[bucket]!.add(TaskItem(task));
  }

  for (final event in events) {
    final days = daysOfEvent(event).toList();
    if (selectedDay != null && days.contains(selectedDay)) {
      byBucket[HomeBucket.selectedDay]!.add(EventItem(event));
      continue;
    }
    final upcoming = days.where((d) => !d.isBefore(today));
    if (upcoming.isEmpty) continue; // finished → history, not Home
    final bucket = futureBucketForDay(upcoming.first);
    if (bucket != null) byBucket[bucket]!.add(EventItem(event));
  }

  int chronologically(HomeItem a, HomeItem b) {
    final [ta, tb] = [a.at, b.at];
    if (ta == null && tb == null) {
      // Dateless tasks only — keep their manual order.
      final sa = a is TaskItem ? a.task.sortOrder : 0;
      final sb = b is TaskItem ? b.task.sortOrder : 0;
      return sa.compareTo(sb);
    }
    if (ta == null) return 1; // undated sinks
    if (tb == null) return -1;
    return ta.compareTo(tb);
  }

  final order = [
    if (selectedDay != null) HomeBucket.selectedDay,
    HomeBucket.overdue,
    HomeBucket.noDate,
    HomeBucket.today,
    HomeBucket.tomorrow,
    HomeBucket.thisWeek,
    HomeBucket.next30Days,
  ];

  return [
    for (final bucket in order)
      if (byBucket[bucket]!.isNotEmpty)
        HomeGroup(
          bucket: bucket,
          items: byBucket[bucket]!..sort(chronologically),
          // Dateless work belongs to every day, so it stays lit even when a
          // day is selected; only truly other-day groups dim.
          dimmed:
              selectedDay != null &&
              bucket != HomeBucket.selectedDay &&
              bucket != HomeBucket.noDate,
        ),
  ];
}

/// Which local days have at least one open task due — feeds the calendar dots.
Set<DateTime> daysWithTasks(List<Task> tasks) => {
  for (final task in tasks)
    if (task.dueAt != null) dayOf(task.dueAt!),
};

// ── The user's own calendar (OPH-083, ADR-0008) ────────────────────────────

/// Every local day an event touches.
///
/// The end is EXCLUSIVE, the way Google models it: an all-day event on the 5th
/// runs 05-00:00 → 06-00:00 and must mark ONE day, not two. Stepping back a
/// millisecond is what keeps a one-day event from bleeding into tomorrow.
Iterable<DateTime> daysOfEvent(ExternalEvent event) sync* {
  var day = dayOf(event.startsAt);
  final lastInstant = event.endsAt.isAfter(event.startsAt)
      ? event.endsAt.subtract(const Duration(milliseconds: 1))
      : event.endsAt;
  final last = dayOf(lastInstant);
  while (!day.isAfter(last)) {
    yield day;
    day = DateTime(day.year, day.month, day.day + 1);
  }
}

/// Days that carry a meeting — a day with one is not an empty day.
Set<DateTime> daysWithEvents(List<ExternalEvent> events) => {
  for (final event in events) ...daysOfEvent(event),
};

/// A day's events: all-day ones first (they frame the day), then by start time.
List<ExternalEvent> eventsOn(List<ExternalEvent> events, DateTime day) {
  final onDay = [
    for (final event in events)
      if (daysOfEvent(event).contains(day)) event,
  ];
  onDay.sort((a, b) {
    if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
    return a.startsAt.compareTo(b.startsAt);
  });
  return onDay;
}
