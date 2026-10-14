import '../calendar/data/external_event.dart';
import '../home/task_grouping.dart' show daysOfEvent;
import '../tasks/data/task.dart';

/// The home-screen widget's task buckets (OPH-130) — the user's "geçmiş / nodate
/// / bugün / bu hafta / bu ay". A glanceable sibling of Home's `groupTasksForHome`
/// (`features/home/task_grouping.dart`): no selected day (the calendar header
/// covers the date), and it collapses Home's Tomorrow into This week and
/// renames the 30-day tail to This month. Since snapshot v5 it carries the
/// user's calendar events the way Home does.
enum WidgetBucket { overdue, noDate, today, thisWeek, thisMonth }

/// How far ahead the widget looks — a rolling 30 days, like Home's horizon, so a
/// far-future or recurring item can't flood the glance. Beyond this, tasks drop.
const int kWidgetHorizonDays = 30;

/// One row of a widget bucket: a task, or (snapshot v5) an event from the
/// user's own calendar — the same pair Home draws (`HomeItem`), because the
/// widget is a glance at Home and Home is "the single chronological view
/// where everything shows".
sealed class WidgetEntry {
  const WidgetEntry();
}

class WidgetTaskEntry extends WidgetEntry {
  const WidgetTaskEntry(this.task);

  final Task task;
}

class WidgetEventEntry extends WidgetEntry {
  const WidgetEventEntry(this.event, {required this.day});

  final ExternalEvent event;

  /// The local day the event was filed under — the first day it touches that
  /// has not passed (an ongoing trip belongs to TODAY). It is what the row's
  /// tap opens (`alliswell://day/<yyyy-MM-dd>`).
  final DateTime day;
}

class WidgetGroup {
  const WidgetGroup({required this.bucket, required this.entries});

  final WidgetBucket bucket;

  /// Every row, in the order the widget draws them.
  final List<WidgetEntry> entries;

  /// The bucket's tasks alone, in order. What the counts, the lock screen's
  /// "next" and every pre-v5 reader of a group mean by "the group".
  List<Task> get tasks => [
    for (final entry in entries)
      if (entry is WidgetTaskEntry) entry.task,
  ];
}

DateTime _dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Groups open tasks — and, since snapshot v5, the user's calendar [events] —
/// into the widget's buckets, chronologically within each. Pure and
/// deterministic (pass [now]) so it is fully unit-testable.
///
/// Order: Overdue → No date → Today → This week → This month. Only non-empty
/// buckets are returned. Boundaries (local days): overdue = due < today;
/// today = due == today; this week = +1…+6; this month = +7…+30 inclusive;
/// beyond +30 is dropped. Undated tasks are "every day's work" (No date).
///
/// Events follow Home's rules (`groupTasksForHome`), so the glance and the app
/// cannot disagree about a meeting: never Overdue (a meeting that happened is
/// not a debt) and never No date; a finished event is dropped; an ongoing one
/// is filed under the first day it touches that has not passed; the same
/// 30-day horizon. Within a bucket an all-day event — and one already running
/// — sits at the start of its day.
List<WidgetGroup> groupTasksForWidget(
  List<Task> tasks, {
  required DateTime now,
  List<ExternalEvent> events = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  final weekEnd = today.add(const Duration(days: 7)); // +7 exclusive
  final horizon = today.add(const Duration(days: kWidgetHorizonDays));

  final byBucket = <WidgetBucket, List<WidgetEntry>>{
    for (final b in WidgetBucket.values) b: [],
  };

  /// Bucket for a NON-past day; null beyond the horizon.
  WidgetBucket? futureBucketForDay(DateTime day) {
    if (day == today) return WidgetBucket.today;
    if (day.isBefore(weekEnd)) return WidgetBucket.thisWeek; // +1…+6
    if (!day.isAfter(horizon)) return WidgetBucket.thisMonth; // +7…+30
    return null; // beyond the horizon → dropped.
  }

  for (final task in tasks) {
    final due = task.dueAt;
    if (due == null) {
      byBucket[WidgetBucket.noDate]!.add(WidgetTaskEntry(task));
      continue;
    }
    final day = _dayOf(due);
    if (day.isBefore(today)) {
      byBucket[WidgetBucket.overdue]!.add(WidgetTaskEntry(task));
      continue;
    }
    final bucket = futureBucketForDay(day);
    if (bucket != null) byBucket[bucket]!.add(WidgetTaskEntry(task));
  }

  for (final event in events) {
    // Home's own helper: the end is exclusive, so an all-day event marks ONE
    // day, not two.
    final upcoming = daysOfEvent(event).where((d) => !d.isBefore(today));
    if (upcoming.isEmpty) continue; // finished → history, not the widget
    final day = upcoming.first;
    final bucket = futureBucketForDay(day);
    if (bucket != null) {
      byBucket[bucket]!.add(WidgetEventEntry(event, day: day));
    }
  }

  /// The instant a row sorts at. An all-day event, and one that began before
  /// its filed day, open that day: they frame it rather than follow it.
  DateTime? at(WidgetEntry entry) => switch (entry) {
    WidgetTaskEntry(:final task) => task.dueAt,
    WidgetEventEntry(:final event, :final day) =>
      event.isAllDay || event.startsAt.isBefore(day) ? day : event.startsAt,
  };

  int chronologically(WidgetEntry a, WidgetEntry b) {
    // OPH-185 (DESIGN §20 C5): the widget and the app agree — today's finished
    // work is still visible, at the bottom of its bucket. `openTasksProvider`
    // now carries it, so without this line the widget would sort a done task
    // above a waiting one.
    bool done(WidgetEntry e) => e is WidgetTaskEntry && e.task.isCompleted;
    if (done(a) != done(b)) return done(a) ? 1 : -1;
    final da = at(a), db = at(b);
    if (da == null && db == null) {
      final sa = a is WidgetTaskEntry ? a.task.sortOrder : 0;
      final sb = b is WidgetTaskEntry ? b.task.sortOrder : 0;
      return sa.compareTo(sb);
    }
    if (da == null) return 1;
    if (db == null) return -1;
    final byTime = da.compareTo(db);
    if (byTime != 0) return byTime;
    // A tie at a day's start: the event that frames the day first.
    final ea = a is WidgetEventEntry, eb = b is WidgetEventEntry;
    if (ea != eb) return ea ? -1 : 1;
    return 0;
  }

  return [
    for (final bucket in WidgetBucket.values)
      if (byBucket[bucket]!.isNotEmpty)
        WidgetGroup(
          bucket: bucket,
          entries: byBucket[bucket]!..sort(chronologically),
        ),
  ];
}

/// The id of the widget's whole list (OPH-336): Home's tasks, every project.
/// What an unconfigured widget shows, and the first choice a configured one
/// offers. The Swift and Kotlin readers name it too — widget_lists_test.dart
/// pins all three to this spelling.
const String kWidgetListAll = 'all';

/// The tasks a widget set to [listId] draws (OPH-336, WIDGETS §9).
///
/// The native side only PICKS a list id; which tasks belong to that list is
/// decided here, in pure Dart, next to the grouping it feeds (W9) — so a
/// Swift picker and a Kotlin one can never disagree about what "Work" holds.
/// [kWidgetListAll] is every task; a project id is that project's tasks and
/// nothing else.
List<Task> filterTasksForWidgetList(List<Task> tasks, String listId) {
  if (listId == kWidgetListAll) return tasks;
  return [
    for (final task in tasks)
      if (task.projectId == listId) task,
  ];
}

/// The lock screen's "next task" (OPH-336): the first OPEN task in the order
/// the widget draws its buckets — overdue, today, this week, this month — with
/// the dateless ones last. They are every day's work (see
/// [groupTasksForWidget]), so they are nobody's "next" while something dated
/// is still open. Null when nothing is open. The bucket comes back with the
/// task because the lock screen says which one it is ("Overdue", "Today").
///
/// Reads the same [groups] the list is drawn from, so the lock screen cannot
/// name a task the home-screen widget does not have.
({Task task, WidgetBucket bucket})? nextTaskForWidget(
  List<WidgetGroup> groups,
) {
  const order = [
    WidgetBucket.overdue,
    WidgetBucket.today,
    WidgetBucket.thisWeek,
    WidgetBucket.thisMonth,
    WidgetBucket.noDate,
  ];
  for (final bucket in order) {
    for (final group in groups) {
      if (group.bucket != bucket) continue;
      for (final task in group.tasks) {
        if (!task.isCompleted) return (task: task, bucket: bucket);
      }
    }
  }
  return null;
}
