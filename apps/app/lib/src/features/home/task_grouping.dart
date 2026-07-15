import '../calendar/data/external_event.dart';
import '../tasks/data/task.dart';

/// Chronological buckets of the home list (feedback round 1). When a calendar
/// day is selected its group sorts first and the rest render dimmed.
enum HomeBucket {
  selectedDay,
  overdue,
  today,
  tomorrow,
  thisWeek,
  later,
  noDate,
}

extension HomeBucketLabel on HomeBucket {
  String get label => switch (this) {
    HomeBucket.selectedDay => 'Selected day',
    HomeBucket.overdue => 'Overdue',
    HomeBucket.today => 'Today',
    HomeBucket.tomorrow => 'Tomorrow',
    HomeBucket.thisWeek => 'This week',
    HomeBucket.later => 'Later',
    HomeBucket.noDate => 'No date',
  };
}

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
/// renders dimmed.
///
/// Since OPH-084 the user's own calendar rides along (§12: "everything shows").
/// Two rules keep events honest:
///
/// - **Events never land in Overdue.** A meeting that already happened is not a
///   debt you owe — Overdue means "you still have to do this". Past events drop
///   out of Home entirely.
/// - **An ongoing event belongs to today**, not to the day it started: a trip
///   that began on Monday and runs through Friday is something happening NOW.
///   It appears once, at the first day it touches that has not passed.
List<HomeGroup> groupTasksForHome(
  List<Task> tasks, {
  required DateTime now,
  DateTime? selectedDay,
  List<ExternalEvent> events = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final weekEnd = today.add(const Duration(days: 7));

  final byBucket = <HomeBucket, List<HomeItem>>{
    for (final b in HomeBucket.values) b: [],
  };

  HomeBucket? bucketForDay(DateTime day) {
    if (day.isBefore(today)) return null; // caller decides what "past" means
    if (day == today) return HomeBucket.today;
    if (day == tomorrow) return HomeBucket.tomorrow;
    if (day.isBefore(weekEnd)) return HomeBucket.thisWeek;
    return HomeBucket.later;
  }

  for (final task in tasks) {
    final due = task.dueAt;
    if (selectedDay != null && due != null && dayOf(due) == selectedDay) {
      byBucket[HomeBucket.selectedDay]!.add(TaskItem(task));
      continue;
    }
    if (due == null) {
      byBucket[HomeBucket.noDate]!.add(TaskItem(task));
    } else {
      // A task's deadline CAN be in the past — that is the whole point of
      // Overdue.
      final bucket = bucketForDay(dayOf(due)) ?? HomeBucket.overdue;
      byBucket[bucket]!.add(TaskItem(task));
    }
  }

  for (final event in events) {
    final days = daysOfEvent(event).toList();
    if (selectedDay != null && days.contains(selectedDay)) {
      byBucket[HomeBucket.selectedDay]!.add(EventItem(event));
      continue;
    }
    // The first day it touches that has not passed: an ongoing multi-day event
    // is happening today, and a finished one is history, not a debt.
    final upcoming = days.where((d) => !d.isBefore(today));
    if (upcoming.isEmpty) continue;
    final bucket = bucketForDay(upcoming.first);
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
    HomeBucket.today,
    HomeBucket.tomorrow,
    HomeBucket.thisWeek,
    HomeBucket.later,
    HomeBucket.noDate,
  ];

  return [
    for (final bucket in order)
      if (byBucket[bucket]!.isNotEmpty)
        HomeGroup(
          bucket: bucket,
          items: byBucket[bucket]!..sort(chronologically),
          dimmed: selectedDay != null && bucket != HomeBucket.selectedDay,
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
