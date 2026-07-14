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

class HomeGroup {
  const HomeGroup({
    required this.bucket,
    required this.tasks,
    required this.dimmed,
  });

  final HomeBucket bucket;
  final List<Task> tasks;

  /// True when a day is selected and this group is not that day's group.
  final bool dimmed;
}

DateTime dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Groups open tasks for the home list. `selectedDay` (a local calendar day)
/// pulls that day's tasks into a highlighted first group; everything else
/// keeps its chronological order but renders dimmed.
List<HomeGroup> groupTasksForHome(
  List<Task> tasks, {
  required DateTime now,
  DateTime? selectedDay,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final weekEnd = today.add(const Duration(days: 7));

  final byBucket = <HomeBucket, List<Task>>{
    for (final b in HomeBucket.values) b: [],
  };

  for (final task in tasks) {
    final due = task.dueAt;
    if (selectedDay != null && due != null && dayOf(due) == selectedDay) {
      byBucket[HomeBucket.selectedDay]!.add(task);
      continue;
    }
    if (due == null) {
      byBucket[HomeBucket.noDate]!.add(task);
    } else if (dayOf(due).isBefore(today)) {
      byBucket[HomeBucket.overdue]!.add(task);
    } else if (dayOf(due) == today) {
      byBucket[HomeBucket.today]!.add(task);
    } else if (dayOf(due) == tomorrow) {
      byBucket[HomeBucket.tomorrow]!.add(task);
    } else if (dayOf(due).isBefore(weekEnd)) {
      byBucket[HomeBucket.thisWeek]!.add(task);
    } else {
      byBucket[HomeBucket.later]!.add(task);
    }
  }

  int byDue(Task a, Task b) {
    final [da, db] = [a.dueAt, b.dueAt];
    if (da == null && db == null) return a.sortOrder.compareTo(b.sortOrder);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
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
          tasks: byBucket[bucket]!..sort(byDue),
          dimmed: selectedDay != null && bucket != HomeBucket.selectedDay,
        ),
  ];
}

/// Which local days have at least one open task due — feeds the calendar dots.
Set<DateTime> daysWithTasks(List<Task> tasks) => {
  for (final task in tasks)
    if (task.dueAt != null) dayOf(task.dueAt!),
};
