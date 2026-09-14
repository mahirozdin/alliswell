import '../../core/list_sort.dart';
import '../../i18n/i18n.dart';
import '../calendar/data/external_event.dart';
import '../tasks/data/task.dart';
import '../tasks/data/task_sort.dart';

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
  /// Localized group header (OPH-123). Keys mirror the enum names, so the widget
  /// snapshot (Epic 12) reuses the same `home.bucket.*` strings.
  String get label => 'home.bucket.$name'.tr();
}

/// How far ahead Home's chronological flow looks. Beyond this the list would
/// fill with every future instance of a recurring calendar event and bury real
/// work (OPH-102). Since the Calendar tab's removal (round 8, OPH-162) the way
/// to reach further-out days is the month grid: a SELECTED day always shows its
/// items, horizon or not. The grid's dots are NOT bounded by this — only the
/// flow.
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
    this.day,
  });

  final HomeBucket bucket;
  final List<HomeItem> items;

  /// True when a day is selected and this group is not that day's group.
  final bool dimmed;

  /// The calendar day this group covers, for buckets that are split per day
  /// (OPH-307). Null for the buckets that are one heap by design.
  final DateTime? day;
}

DateTime dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Groups Home's rows. `selectedDay` (a local calendar day) pulls that day into
/// a highlighted first group; FUTURE groups (tomorrow and beyond) render dimmed
/// while Overdue, Today and No-date stay at full opacity — what demands
/// attention right now must never look disabled (feedback round 6).
///
/// Order (OPH-102): Selected day? → Overdue → **No date** → Today → Tomorrow →
/// This week → Next 30 days. Two rules make it honest to the user:
///
/// - **A 30-day horizon; there is no open-ended "Later".** Anything dated more
///   than [kHomeHorizonDays] days out — tasks AND events — is dropped from the
///   chronological flow, so recurring meetings can't bury real work. The
///   SELECTED day overrides the horizon (checked first below): picking a far
///   day in the month grid shows that day's items — since OPH-162 removed the
///   Calendar tab, this is the product's promised way to look far ahead.
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
  AwSortState? sort,
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

  bool isDone(HomeItem item) => item is TaskItem && item.task.isCompleted;

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

  // OPH-305 — the two orders the user can ask for instead. Both are written
  // ASCENDING; `AwSortState.comparator` is the one place direction is applied,
  // which is why "priority" defaults to descending (urgent first) and "title"
  // does not (names go A→Z).
  //
  // Both fall back to the clock for ties, so the order never depends on which
  // row the sync happened to write first.
  int byPriority(HomeItem a, HomeItem b) {
    int rank(HomeItem item) => switch (item) {
      // A meeting is not something you choose when to do, so it has nothing to
      // rank. It sorts as the lowest priority — with the unranked work, which
      // is the predictable answer rather than a clever one.
      TaskItem(:final task) => taskPriorityRank(task.priority),
      EventItem() => 0,
    };
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : chronologically(a, b);
  }

  int byTitle(HomeItem a, HomeItem b) {
    String key(HomeItem item) => switch (item) {
      TaskItem(:final task) => taskTitleKey(task.title),
      EventItem(:final event) => taskTitleKey(event.summary ?? ''),
    };
    final byKey = key(a).compareTo(key(b));
    return byKey != 0 ? byKey : chronologically(a, b);
  }

  final chosen = switch (sort?.id) {
    'priority' => sort!.comparator<HomeItem>(byPriority),
    'title' => sort!.comparator<HomeItem>(byTitle),
    // `date` goes through the same seam as the others rather than short-
    // circuiting to `chronologically`: the menu offers "Reverse order" for
    // every choice, and a control that silently does nothing for one of them
    // is worse than not offering it.
    'date' => sort!.comparator<HomeItem>(chronologically),
    // No preference, or one that outlived its option: the order Home has
    // always had. A stale preference must not reshuffle somebody's day.
    _ => chronologically,
  };

  /// The chosen order, under the rule that outranks it.
  ///
  /// OPH-185 (DESIGN §20 C1): today's finished work stays in its group but
  /// sinks to the BOTTOM of it — done work must never sit above work that is
  /// still waiting, whatever the clock says. This used to live INSIDE the
  /// chronological comparator, which was fine while there was only one; a rule
  /// buried in one preference is a rule the next preference forgets.
  int ordered(HomeItem a, HomeItem b) {
    final [da, db] = [isDone(a), isDone(b)];
    if (da != db) return da ? 1 : -1;
    return chosen(a, b);
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

  // Work you must face NOW never fades (feedback round 6): dateless belongs to
  // every day, and Overdue/Today are current debts — a selected day only dims
  // the genuinely future groups.
  bool dimmedFor(HomeBucket bucket) =>
      selectedDay != null &&
      bucket != HomeBucket.selectedDay &&
      bucket != HomeBucket.noDate &&
      bucket != HomeBucket.overdue &&
      bucket != HomeBucket.today;

  /// The day a row is filed under, computed the SAME way the bucket above was.
  ///
  /// Not `dayOf(item.at)`: a multi-day event's `startsAt` can sit before the
  /// day it was bucketed by, and a heading that disagrees with the bucket that
  /// produced it is worse than no heading.
  DateTime dayForSplit(HomeItem item) => switch (item) {
    TaskItem(:final task) => dayOf(task.dueAt!),
    EventItem(:final event) => daysOfEvent(
      event,
    ).firstWhere((d) => !d.isBefore(today)),
  };

  final groups = <HomeGroup>[];
  for (final bucket in order) {
    final items = byBucket[bucket]!;
    if (items.isEmpty) continue;
    items.sort(ordered);

    // OPH-307 — "This week" is one heading per day, because the report was
    // about the eyes: *"for each day, the tasks are listed one by one
    // (vertically), coz this would be easier to follow"*. Home already knew the
    // day — `futureBucketForDay` computes it and then drops it into one pile.
    //
    // Only this bucket. "Next 30 days" spans +7..+30, so splitting it would
    // hang up to 24 headings over a list somebody reads at a glance; that is an
    // agenda screen, not a heading change, and the month grid already answers
    // "what is on the 23rd". The split stays INSIDE the bucket for the same
    // reason: the order, the horizon and the recession rule are untouched.
    if (bucket != HomeBucket.thisWeek) {
      groups.add(
        HomeGroup(bucket: bucket, items: items, dimmed: dimmedFor(bucket)),
      );
      continue;
    }

    final byDay = <DateTime, List<HomeItem>>{};
    for (final item in items) {
      byDay.putIfAbsent(dayForSplit(item), () => []).add(item);
    }
    // Empty days are absent rather than empty: a heading means there IS work
    // that day, the same promise the calendar's dots make (OPH-185). A blank
    // "Friday" would read as "you are free on Friday", which this list cannot
    // know — it only knows what is scheduled.
    for (final day in byDay.keys.toList()..sort()) {
      groups.add(
        HomeGroup(
          bucket: bucket,
          items: byDay[day]!,
          dimmed: dimmedFor(bucket),
          day: day,
        ),
      );
    }
  }
  return groups;
}

/// Which local days have at least one OPEN task due — feeds the calendar dots.
///
/// Completed tasks are excluded even while they linger on today's list
/// (OPH-185, DESIGN §20 C1): a dot means "there is work on this day", and a
/// finished day is not a full day.
Set<DateTime> daysWithTasks(List<Task> tasks) => {
  for (final task in tasks)
    if (task.dueAt != null && !task.isCompleted) dayOf(task.dueAt!),
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
