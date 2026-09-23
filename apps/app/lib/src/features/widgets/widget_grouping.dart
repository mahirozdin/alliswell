import '../tasks/data/task.dart';

/// The home-screen widget's task buckets (OPH-130) — the user's "geçmiş / nodate
/// / bugün / bu hafta / bu ay". A glanceable sibling of Home's `groupTasksForHome`
/// (`features/home/task_grouping.dart`): tasks-only (the calendar header covers
/// the date), and it collapses Home's Tomorrow into This week and renames the
/// 30-day tail to This month.
enum WidgetBucket { overdue, noDate, today, thisWeek, thisMonth }

/// How far ahead the widget looks — a rolling 30 days, like Home's horizon, so a
/// far-future or recurring item can't flood the glance. Beyond this, tasks drop.
const int kWidgetHorizonDays = 30;

class WidgetGroup {
  const WidgetGroup({required this.bucket, required this.tasks});

  final WidgetBucket bucket;
  final List<Task> tasks;
}

DateTime _dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Groups open tasks into the widget's buckets, chronologically within each.
/// Pure and deterministic (pass [now]) so it is fully unit-testable.
///
/// Order: Overdue → No date → Today → This week → This month. Only non-empty
/// buckets are returned. Boundaries (local days): overdue = due < today;
/// today = due == today; this week = +1…+6; this month = +7…+30 inclusive;
/// beyond +30 is dropped. Undated tasks are "every day's work" (No date).
List<WidgetGroup> groupTasksForWidget(
  List<Task> tasks, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final weekEnd = today.add(const Duration(days: 7)); // +7 exclusive
  final horizon = today.add(const Duration(days: kWidgetHorizonDays));

  final byBucket = <WidgetBucket, List<Task>>{
    for (final b in WidgetBucket.values) b: [],
  };

  for (final task in tasks) {
    final due = task.dueAt;
    if (due == null) {
      byBucket[WidgetBucket.noDate]!.add(task);
      continue;
    }
    final day = _dayOf(due);
    if (day.isBefore(today)) {
      byBucket[WidgetBucket.overdue]!.add(task);
    } else if (day == today) {
      byBucket[WidgetBucket.today]!.add(task);
    } else if (day.isBefore(weekEnd)) {
      byBucket[WidgetBucket.thisWeek]!.add(task); // +1…+6
    } else if (!day.isAfter(horizon)) {
      byBucket[WidgetBucket.thisMonth]!.add(task); // +7…+30
    }
    // else: beyond the horizon → dropped.
  }

  int chronologically(Task a, Task b) {
    // OPH-185 (DESIGN §20 C5): the widget and the app agree — today's finished
    // work is still visible, at the bottom of its bucket. `openTasksProvider`
    // now carries it, so without this line the widget would sort a done task
    // above a waiting one.
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
    final da = a.dueAt, db = b.dueAt;
    if (da == null && db == null) return a.sortOrder.compareTo(b.sortOrder);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  return [
    for (final bucket in WidgetBucket.values)
      if (byBucket[bucket]!.isNotEmpty)
        WidgetGroup(
          bucket: bucket,
          tasks: byBucket[bucket]!..sort(chronologically),
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
