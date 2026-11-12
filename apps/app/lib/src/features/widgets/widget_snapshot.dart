import 'package:intl/intl.dart';

import '../../core/date_format.dart';
import '../../core/deep_link.dart';
import '../../core/format_region.dart';

import '../../i18n/i18n.dart';
import '../calendar/data/external_event.dart';
import '../projects/data/project.dart';
import '../tasks/data/task.dart';
import '../tasks/data/task_scope.dart';
import '../tasks/data/task_when.dart';
import 'widget_clock.dart';
import 'widget_grouping.dart';

/// The JSON snapshot the app writes to the shared container for the native
/// widgets to render (OPH-130, WIDGETS.md §3.1). Kept SMALL and pre-localized —
/// the native side does no i18n and no DB access, it just draws this.
///
/// **v2 (OPH-187):** adds `openToday`. The native side must tolerate its
/// absence — during an app update a v1 snapshot and a v2 widget (and the
/// reverse) live side by side for a while, and a widget that blanks out because
/// one field is missing is worse than one that hides a badge.
///
/// **v3 (OPH-253):** adds `clockFormat`, the ICU pattern the header clock is
/// drawn with. The clock is the one thing the app cannot pre-render (it changes
/// every minute), so native formats it — but the *choice* of format is still a
/// product rule and stays here (W9, and OPH-174's "the widget speaks the app's
/// format"). Same tolerance rule as v2: an older snapshot has no `clockFormat`
/// and the widget falls back to the locale's own clock.
///
/// **v4 (OPH-336, OPH-337):** adds `next` (the lock screen's one row), `lists`
/// (what a widget can be set to), `views` (each project's own buckets, count
/// and next task) and `density`. The whole list stays at the top level, where
/// v3 put it, so an unconfigured widget — and a widget from before v4 — reads
/// exactly what it always read. Same tolerance rule again: every new field is
/// optional. (Both tasks landed before any release, so one version covers
/// both.) The "Private widget" setting is not a field at all: it changes what
/// the title fields HOLD — see [buildWidgetSnapshot]'s `hideTitles`.
///
/// **v5:** the whole list carries the user's calendar events beside the tasks,
/// as Home does. An event row is an ordinary item with two extra fields:
/// `"kind": "event"` (absent = a task, so every v4 row reads unchanged) and
/// `"day": "yyyy-MM-dd"` (the day its tap opens — `alliswell://day/<day>`).
/// Events never enter a project's view, the open count or `next`: those are
/// about work. A v4 widget that ignores `kind` draws an event as a task row —
/// a tap opens nothing and a circle press completes nothing (no task has
/// that id), so the fallback is harmless.
///
/// **v6 (#50, ADR-0010 revision 2026-11-12):** adds `days`, today and the next
/// [kWidgetSnapshotDays] - 1 days, each a full [WidgetDayView] — header, open
/// count, next task, buckets with that day's calendar rows, every project
/// view — so a WidgetKit entry past midnight draws its own day without Dart.
/// Every top-level field stays and equals `days[0]`, so a v5 extension keeps
/// rendering. `strings.stale` is what a widget says once its date is past the
/// last day it holds: the old list is never shown under a new date.
const int kWidgetSnapshotVersion = 6;

/// How many days the snapshot carries (v6): today + 2. A WidgetKit timeline
/// past the last one shows `strings.stale`.
const int kWidgetSnapshotDays = 3;

/// The largest snapshot the app expects to write, in UTF-8 bytes (v6). Set from
/// a measurement — 300 open tasks in 20 projects, every bucket full, long
/// Turkish titles: 282 425 bytes on 2026-11-12 — plus about a third of
/// headroom, and locked by widget_core_test.dart. It is a budget, not a cut:
/// a failing test means "look at what grew", not "trim the snapshot".
const int kWidgetSnapshotMaxBytes = 384 * 1024;

/// How many rows per bucket the snapshot carries; the native layer trims further
/// per widget size. The largest tier shows the most, so keep this generous.
const int kWidgetRowsPerBucket = 12;

/// The `kind` an event row carries (v5). Spelled once — the Swift and Kotlin
/// readers are pinned to it by widget_lists_test.dart.
const String kWidgetKindEvent = 'event';

class WidgetTaskRow {
  const WidgetTaskRow({
    required this.id,
    required this.title,
    required this.done,
    required this.priority,
    this.time,
    this.projectColor,
    this.kind,
    this.day,
  });

  final String id;
  final String title;
  final bool done;
  final String priority;

  /// Pre-formatted short label (HH:mm for Today, a short date otherwise), or null.
  final String? time;

  /// The task's project color as `#RRGGBB`, or null. Native computes readable ink.
  final String? projectColor;

  /// v5: [kWidgetKindEvent] for a calendar event; null (absent) for a task.
  final String? kind;

  /// v5: an event row's day as `yyyy-MM-dd` — what its tap opens.
  final String? day;

  bool get isEvent => kind == kWidgetKindEvent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'priority': priority,
    if (time != null) 'time': time,
    if (projectColor != null) 'projectColor': projectColor,
    if (kind != null) 'kind': kind,
    if (day != null) 'day': day,
  };
}

class WidgetBucketData {
  const WidgetBucketData({
    required this.key,
    required this.label,
    required this.count,
    required this.items,
    required this.more,
  });

  final String key;
  final String label;
  final int count;
  final List<WidgetTaskRow> items;

  /// How many open rows were trimmed ("+N more"): the entries past [items]
  /// that are still owed — [count] less the open rows in [items]. A finished
  /// row past the cap is not in it (OPH-451, Z-02): [count] leaves today's
  /// finished rows out (Home's header rule), and so does the "+N". The iOS
  /// widget applies the same rule to the rows it draws (`awMoreCount`).
  final int more;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'count': count,
    'items': [for (final item in items) item.toJson()],
    if (more > 0) 'more': more,
  };
}

class WidgetDateHeader {
  const WidgetDateHeader({
    required this.weekday,
    required this.day,
    required this.month,
  });

  final String weekday;
  final String day;
  final String month;

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'day': day,
    'month': month,
  };
}

/// The lock screen's one row (OPH-336): the task [nextTaskForWidget] picked,
/// with its bucket's label and its time already in the user's words and
/// format.
class WidgetNextTask {
  const WidgetNextTask({
    required this.id,
    required this.title,
    required this.bucket,
    required this.label,
    this.time,
  });

  final String id;
  final String title;

  /// The bucket's key (`overdue`, `today`, …), as a bucket carries it.
  final String bucket;

  /// The bucket's localized label ("Overdue", "Bugün"). The lock screen is
  /// drawn in one tint, so this word — not a red — is what says it is late.
  final String label;

  /// The same short label a row carries (HH:mm today, a short date otherwise).
  final String? time;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'bucket': bucket,
    'label': label,
    if (time != null) 'time': time,
  };
}

/// One entry in the widget's list picker (OPH-336) — what the iOS
/// configuration sheet and the Android configure screen offer. Pre-localized
/// like every other widget word: the whole list's name comes from the app.
class WidgetListChoice {
  const WidgetListChoice({required this.id, required this.name, this.color});

  final String id;
  final String name;

  /// The project's `#RRGGBB`; null for the whole list.
  final String? color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (color != null) 'color': color,
  };
}

/// What a widget set to one project draws (OPH-336): the three things the
/// snapshot's top level carries for the whole list, computed from that
/// project's tasks alone.
class WidgetListView {
  const WidgetListView({
    required this.openToday,
    required this.openTodayLabel,
    required this.buckets,
    this.next,
  });

  final int openToday;

  /// The count in words ("2 open"). The top level's `strings.openToday` spells
  /// the WHOLE list's number, so a project view carries its own.
  final String openTodayLabel;
  final List<WidgetBucketData> buckets;
  final WidgetNextTask? next;

  Map<String, dynamic> toJson() => {
    if (openToday > 0) 'openToday': openToday,
    if (openToday > 0) 'openTodayLabel': openTodayLabel,
    if (next != null) 'next': next!.toJson(),
    'buckets': [for (final bucket in buckets) bucket.toJson()],
  };
}

/// One day of the widget (v6): what the snapshot's top level carries for
/// today, computed for that day — the day's header, its open count and words,
/// its next task, its buckets (calendar rows included) and every project's
/// view. The native side picks the element whose [date] is the entry's local
/// day; it never re-buckets (DESIGN §8 W9).
class WidgetDayView {
  const WidgetDayView({
    required this.date,
    required this.header,
    required this.openToday,
    required this.openTodayLabel,
    required this.buckets,
    this.next,
    this.views = const {},
  });

  /// The local day as `yyyy-MM-dd`.
  final String date;
  final WidgetDateHeader header;
  final int openToday;
  final String openTodayLabel;
  final List<WidgetBucketData> buckets;
  final WidgetNextTask? next;
  final Map<String, WidgetListView> views;

  Map<String, dynamic> toJson() => {
    'date': date,
    'header': header.toJson(),
    if (openToday > 0) 'openToday': openToday,
    if (openToday > 0) 'openTodayLabel': openTodayLabel,
    if (next != null) 'next': next!.toJson(),
    'buckets': [for (final bucket in buckets) bucket.toJson()],
    if (views.isNotEmpty)
      'views': {
        for (final entry in views.entries) entry.key: entry.value.toJson(),
      },
  };
}

class WidgetSnapshot {
  const WidgetSnapshot({
    required this.version,
    required this.generatedAt,
    required this.locale,
    required this.date,
    required this.buckets,
    required this.strings,
    required this.openToday,
    required this.clockFormat,
    this.next,
    this.lists = const [],
    this.views = const {},
    this.days = const [],
    this.compact = false,
  });

  final int version;
  final String generatedAt;
  final String locale;
  final WidgetDateHeader date;
  final List<WidgetBucketData> buckets;

  /// The ICU pattern the header clock is drawn with (OPH-253, DESIGN §31 C2) —
  /// "HH:mm", "h:mm a", … Resolved from the user's date-format preference so the
  /// clock and the task rows under it can never disagree (OPH-174).
  final String clockFormat;

  /// What is on the user TODAY: overdue + the Today bucket (due today, or
  /// "when" reached — OPH-372), open tasks only (OPH-187, DESIGN §8 W9). Snoozed and muted tasks count — they are still
  /// open work. Dateless ones do not: they belong to every day, so they would
  /// inflate every day. Zero means the badge is hidden, not drawn as "0".
  final int openToday;

  /// Pre-localized chrome the native widget needs (empty state, quick-add label)
  /// so it carries no translations of its own.
  final Map<String, String> strings;

  /// The whole list's next task, for the lock screen (OPH-336); null when
  /// nothing is open.
  final WidgetNextTask? next;

  /// The lists a widget can be set to (OPH-336): [kWidgetListAll] first, then
  /// every project a task can be filed under, in the app's own order.
  final List<WidgetListChoice> lists;

  /// Each project's own view, keyed by project id (OPH-336). A project with
  /// nothing on it still gets one — an empty view is how the widget knows to
  /// say "all caught up" for it rather than fall back to the whole list, which
  /// it does only for an id this map has never heard of (a deleted project).
  final Map<String, WidgetListView> views;

  /// v6: today and the next days, each a full view; `days[0]` equals the top
  /// level above.
  final List<WidgetDayView> days;

  /// Draw tighter rows (OPH-337) — `"density": "compact"` in the JSON, absent
  /// for the normal density so an unchanged widget writes unchanged bytes.
  final bool compact;

  Map<String, dynamic> toJson() => {
    'v': version,
    'generatedAt': generatedAt,
    'locale': locale,
    'date': date.toJson(),
    'strings': strings,
    'clockFormat': clockFormat,
    if (compact) 'density': 'compact',
    if (openToday > 0) 'openToday': openToday,
    if (next != null) 'next': next!.toJson(),
    'buckets': [for (final bucket in buckets) bucket.toJson()],
    'lists': [for (final list in lists) list.toJson()],
    if (views.isNotEmpty)
      'views': {
        for (final entry in views.entries) entry.key: entry.value.toJson(),
      },
    if (days.isNotEmpty) 'days': [for (final day in days) day.toJson()],
  };
}

/// How a row's time reads, without the words (#50, WIDGETS §3.2). The ONE
/// rule both labels come from: the app turns a style into text here
/// ([_styleText]), and the widget extension turns the server's copy of the
/// same style into text with the profile's patterns. The wire names are the
/// enum names.
enum WidgetTimeStyle {
  /// time(dueAt) — a task due on the view's day, in Today.
  time,

  /// day(dueAt) — any other dated task; day(`day`) for an all-day event
  /// outside Today.
  day,

  /// `strings.allDay` — an all-day event in Today.
  allDay,

  /// time(dueAt)–time(endAt) — an event that starts and ends on the day.
  range,

  /// time(dueAt) — an event that starts on the day and runs past it.
  start,

  /// –time(endAt) — an event that began before the day.
  end,

  /// The row form of an instant ([awFormatShort] with the time) — a timed
  /// event outside Today.
  dayTime,
}

/// A task row's time style, or null for a dateless task (no label).
///
/// OPH-174: the widget speaks the SAME format as the app — a widget and an app
/// disagreeing about a date, side by side on one screen, is indefensible. A
/// Today row due on the view's day says its time. One that is on Today
/// because its "when" came (OPH-372) is due LATER — a bare time would read as
/// "due at 17:00 today", so it says the due day instead. Overdue / this week
/// / this month: a short date says more than a bare time.
WidgetTimeStyle? widgetTaskTimeStyle(
  Task task,
  WidgetBucket bucket,
  DateTime now,
) {
  final due = task.dueAt;
  if (due == null) return null;
  if (bucket == WidgetBucket.today && awLocalDay(due) == awLocalDay(now)) {
    return WidgetTimeStyle.time;
  }
  return WidgetTimeStyle.day;
}

/// An event row's time style (v5): all day on today's all-day event; the
/// range on today's timed one; elsewhere a short date — with the start time
/// when the event has one. [day] is the day the event is filed under.
WidgetTimeStyle widgetEventTimeStyle(
  ExternalEvent event,
  DateTime day,
  WidgetBucket bucket,
) {
  if (bucket == WidgetBucket.today) {
    if (event.isAllDay) return WidgetTimeStyle.allDay;
    final startsToday = awLocalDay(event.startsAt) == day;
    final endsToday = awLocalDay(event.endsAt) == day;
    if (startsToday && endsToday) return WidgetTimeStyle.range;
    // Began before today (a running trip) or runs past midnight: the end is
    // what the person needs, the start alone when it is still ahead.
    if (startsToday) return WidgetTimeStyle.start;
    return WidgetTimeStyle.end;
  }
  // Outside today an event is filed under the day it starts, so the start is
  // the whole answer.
  return event.isAllDay ? WidgetTimeStyle.day : WidgetTimeStyle.dayTime;
}

/// [style] in the user's words and format. [at] is the task's due instant or
/// the event's start, [end] the event's end, [day] an all-day event's day;
/// [now] is the view's own moment, so a later day's rows say "Tomorrow" from
/// THAT day, as the widget does when it draws it.
String _styleText(
  WidgetTimeStyle style, {
  required DateTime? at,
  DateTime? end,
  DateTime? day,
  required DateTime now,
  required String dateFormat,
  required String localeTag,
}) {
  String time(DateTime t) =>
      awFormatTime(t, format: dateFormat, locale: localeTag);
  return switch (style) {
    WidgetTimeStyle.time || WidgetTimeStyle.start => time(at!),
    WidgetTimeStyle.day => awFormatShort(
      day ?? at!,
      format: dateFormat,
      locale: localeTag,
      now: now,
      withTime: false,
    ),
    WidgetTimeStyle.allDay => 'widget.allDay'.tr(),
    WidgetTimeStyle.range => '${time(at!)}–${time(end!)}',
    WidgetTimeStyle.end => '–${time(end!)}',
    WidgetTimeStyle.dayTime => awFormatShort(
      at!,
      format: dateFormat,
      locale: localeTag,
      now: now,
    ),
  };
}

String? _timeLabel(
  Task task,
  WidgetBucket bucket,
  String localeTag,
  String dateFormat,
  DateTime now,
) {
  final style = widgetTaskTimeStyle(task, bucket, now);
  if (style == null) return null;
  return _styleText(
    style,
    at: task.dueAt,
    now: now,
    dateFormat: dateFormat,
    localeTag: localeTag,
  );
}

/// What a row says instead of its title when the widget is private (OPH-337).
/// The same words for every task: the row is still a row — its time, its
/// project's color and its circle stay — but nothing the user wrote.
String _titleOf(Task task, {required bool hideTitles}) =>
    hideTitles ? 'widget.privateTitle'.tr() : task.title;

/// A task row's color: its project's when it has one (null when that project
/// is unknown here), else its own.
String? _colorOf(Task task, Map<String, String> projectColorById) =>
    task.projectId != null ? projectColorById[task.projectId] : task.colorRgb;

WidgetTaskRow _rowFor(
  Task task,
  WidgetBucket bucket,
  String dateFormat,
  String localeTag,
  Map<String, String> projectColorById, {
  required bool hideTitles,
  required DateTime now,
}) {
  final color = _colorOf(task, projectColorById);
  return WidgetTaskRow(
    id: task.id,
    title: _titleOf(task, hideTitles: hideTitles),
    done: task.status == 'completed',
    priority: task.priority,
    time: _timeLabel(task, bucket, localeTag, dateFormat, now),
    projectColor: color,
  );
}

/// An event row's short label (v5), from [widgetEventTimeStyle].
String _eventTimeLabel(
  ExternalEvent event,
  DateTime day,
  WidgetBucket bucket,
  String localeTag,
  String dateFormat,
  DateTime now,
) => _styleText(
  widgetEventTimeStyle(event, day, bucket),
  at: event.startsAt,
  end: event.endsAt,
  day: event.isAllDay ? day : null,
  now: now,
  dateFormat: dateFormat,
  localeTag: localeTag,
);

/// One calendar event as a widget row (v5). Never done, never ranked, no
/// project color — and under "Private widget" no title either: a meeting's
/// name says as much as a task's.
WidgetTaskRow _eventRowFor(
  WidgetEventEntry entry,
  WidgetBucket bucket,
  String dateFormat,
  String localeTag, {
  required bool hideTitles,
  required DateTime now,
}) => WidgetTaskRow(
  id: entry.event.id,
  title: hideTitles ? 'widget.privateEvent'.tr() : entry.event.title,
  done: false,
  priority: 'none',
  time: _eventTimeLabel(
    entry.event,
    entry.day,
    bucket,
    localeTag,
    dateFormat,
    now,
  ),
  kind: kWidgetKindEvent,
  day: awDayParam(entry.day),
);

/// The projects a widget can be set to (OPH-336), after the whole list: the
/// ones a task can be filed under — not the archived ones, which is the task
/// picker's rule too (`project_picker.dart`) — in the order given, which is
/// the Projects screen's (sort order, then creation).
List<WidgetListChoice> widgetListChoices(Iterable<Project> projects) => [
  WidgetListChoice(id: kWidgetListAll, name: 'widget.list.all'.tr()),
  for (final project in _listable(projects))
    WidgetListChoice(
      id: project.id,
      name: project.name,
      color: project.colorRgb,
    ),
];

/// The projects that get a view: every one a task can be filed under.
Iterable<Project> _listable(Iterable<Project> projects) =>
    projects.where((project) => project.status != 'archived');

/// A row a bucket still owes: an event, or a task not yet finished.
bool _isOpen(WidgetEntry entry) =>
    !(entry is WidgetTaskEntry && entry.task.isCompleted);

/// One list's buckets, open count and next task. The whole list and every
/// project view come out of this one function, so they cannot drift apart.
({List<WidgetBucketData> buckets, int openToday, WidgetNextTask? next})
_listData(
  List<Task> tasks, {
  List<ExternalEvent> events = const [],
  required DateTime now,
  required Map<String, String> projectColorById,
  required int rowsPerBucket,
  required String dateFormat,
  required String localeTag,
  required bool hideTitles,
}) {
  final groups = groupTasksForWidget(tasks, now: now, events: events);

  final buckets = [
    for (final group in groups)
      WidgetBucketData(
        key: group.bucket.name,
        label: 'widget.bucket.${group.bucket.name}'.tr(),
        // OPH-451 (#50, IOS-10): what is still owed, Home's rule (OPH-394) —
        // today's finished row stays drawn at the bottom but is not counted.
        // Nor is it in `more` below (Z-02).
        count: group.entries.where(_isOpen).length,
        items: [
          for (final entry in group.entries.take(rowsPerBucket))
            switch (entry) {
              WidgetTaskEntry(:final task) => _rowFor(
                task,
                group.bucket,
                dateFormat,
                localeTag,
                projectColorById,
                hideTitles: hideTitles,
                now: now,
              ),
              WidgetEventEntry() => _eventRowFor(
                entry,
                group.bucket,
                dateFormat,
                localeTag,
                hideTitles: hideTitles,
                now: now,
              ),
            },
        ],
        more: group.entries.skip(rowsPerBucket).where(_isOpen).length,
      ),
  ];

  final openToday = _openTodayOf(groups);

  final picked = nextTaskForWidget(groups);
  final next = picked == null
      ? null
      : WidgetNextTask(
          id: picked.task.id,
          title: _titleOf(picked.task, hideTitles: hideTitles),
          bucket: picked.bucket.name,
          label: 'widget.bucket.${picked.bucket.name}'.tr(),
          time: _timeLabel(
            picked.task,
            picked.bucket,
            localeTag,
            dateFormat,
            now,
          ),
        );

  return (buckets: buckets, openToday: openToday, next: next);
}

/// Builds the widget snapshot from open tasks. Pure (pass [now]); labels come
/// from the active locale (`AwI18n`) and dates from `intl` — so it carries
/// already-localized text and the native widget needs no translations.
///
/// [projectColorById] maps a task's `projectId` to its `#RRGGBB` color.
/// [projects] are the workspace's projects in the app's order; each one a
/// widget can be set to gets its own view (OPH-336).
///
/// [events] are the user's calendar events (v5). They join the WHOLE list
/// only — a project view is that project's work, and an event belongs to no
/// project. The open count and the lock screen's `next` stay task-only.
///
/// [hideTitles] is the "Private widget" setting (OPH-337): no task's (nor,
/// since v5, any event's) title is
/// written — not in a row, not in the lock screen's `next`, not in a project's
/// view. Counts, times and placeholders are. It is applied HERE, before the
/// JSON exists, because a title handed to the native side with a "do not
/// show" flag has already left the app (WIDGETS §9). Project names stay: they
/// name the list a widget was set to, and the picker offers them.
WidgetSnapshot buildWidgetSnapshot(
  List<Task> tasks, {
  List<ExternalEvent> events = const [],
  required DateTime now,
  Map<String, String> projectColorById = const {},
  Iterable<Project> projects = const [],
  int rowsPerBucket = kWidgetRowsPerBucket,

  /// The user's display format (OPH-174). Defaults to "follow the language" so
  /// unit tests and any future caller stay honest without extra ceremony.
  String dateFormat = kAwSystemDateFormat,
  bool hideTitles = false,
  bool compact = false,
}) {
  final localeTag = AwI18n.instance.locale.toLanguageTag();

  // OPH-336: every list a widget can be set to is computed HERE, with the same
  // function as the whole list — the native side only picks one by id.
  final lists = widgetListChoices(projects);

  // v6: one full view per day, every one out of the SAME function — so day 0
  // and the top level cannot drift apart, and tomorrow is grouped by the
  // rules today is (W1/W9 stay in Dart).
  final days = [
    for (final at in _dayMoments(now))
      _dayView(
        _tasksForDay(tasks, at, now),
        events: events,
        now: at,
        lists: lists,
        projectColorById: projectColorById,
        rowsPerBucket: rowsPerBucket,
        dateFormat: dateFormat,
        localeTag: localeTag,
        hideTitles: hideTitles,
      ),
  ];
  final day0 = days.first;

  return WidgetSnapshot(
    version: kWidgetSnapshotVersion,
    openToday: day0.openToday,
    // The header clock's pattern, from the same preference the rows above use
    // (OPH-253 — the native side formats the minute, it does not choose how).
    clockFormat: widgetClockPattern(format: dateFormat, locale: localeTag),
    generatedAt: now.toUtc().toIso8601String(),
    locale: AwI18n.instance.locale.languageCode,
    date: day0.header,
    strings: {
      'allCaughtUp': 'widget.allCaughtUp'.tr(),
      'addTask': 'widget.addTask'.tr(),
      // Pre-localized like every other widget word — the native side owns no
      // translations (W-rule).
      'openToday': day0.openTodayLabel,
      // OPH-451 (#50): the same phrase with `{count}` unfilled, so a
      // completion from the widget's circle can say the new number in the
      // app's words before the app runs again.
      'openTodayPattern': 'widget.openToday'.tr(),
      // OPH-451 (#50, IOS-11): the circle's spoken label, `{title}` unfilled.
      'completeTask': 'widget.completeTask'.tr(),
      // OPH-336: the lock screen's heading, and the Android configure
      // screen's title — native words, the app's translations.
      'upNext': 'widget.upNext'.tr(),
      'chooseList': 'widget.chooseList'.tr(),
      // v6: what a widget says once its date is past the last day it holds.
      'stale': 'widget.stale'.tr(),
    },
    buckets: day0.buckets,
    next: day0.next,
    lists: lists,
    views: day0.views,
    days: days,
    compact: compact,
  );
}

/// The moments the snapshot's days are seen from (v6): today is [now]; a
/// later day is seen from its first minute, which is when its WidgetKit entry
/// starts drawing it.
List<DateTime> _dayMoments(DateTime now) => [
  for (var d = 0; d < kWidgetSnapshotDays; d++)
    d == 0 ? now : DateTime(now.year, now.month, now.day + d),
];

/// The tasks a day seen from [at] holds. A task finished today is today's
/// dimmed row (OPH-185), not tomorrow's: a later day keeps only what was
/// finished on it. Today keeps every task given — its caller already asked
/// the store for today's finished work only.
List<Task> _tasksForDay(List<Task> tasks, DateTime at, DateTime now) {
  if (identical(at, now)) return tasks;
  return [
    for (final task in tasks)
      if (!task.isCompleted ||
          (task.completedAt != null && !task.completedAt!.isBefore(at)))
        task,
  ];
}

/// What is on the user that day: overdue + Today, open tasks only (OPH-187,
/// W9). Counted from the SAME grouping the widget draws, so the number and
/// the rows can never disagree — and counted here, in pure Dart, because the
/// native layer must never carry product logic (W9).
int _openTodayOf(List<WidgetGroup> groups) {
  var openToday = 0;
  for (final group in groups) {
    if (group.bucket != WidgetBucket.overdue &&
        group.bucket != WidgetBucket.today) {
      continue;
    }
    for (final task in group.tasks) {
      if (!task.isCompleted) openToday++;
    }
  }
  return openToday;
}

/// One day's full view (v6): the whole list and every project's view, seen
/// from [now], over the tasks that day holds ([_tasksForDay]).
WidgetDayView _dayView(
  List<Task> dayTasks, {
  required List<ExternalEvent> events,
  required DateTime now,
  required List<WidgetListChoice> lists,
  required Map<String, String> projectColorById,
  required int rowsPerBucket,
  required String dateFormat,
  required String localeTag,
  required bool hideTitles,
}) {
  final all = _listData(
    dayTasks,
    events: events,
    now: now,
    projectColorById: projectColorById,
    rowsPerBucket: rowsPerBucket,
    dateFormat: dateFormat,
    localeTag: localeTag,
    hideTitles: hideTitles,
  );

  final views = <String, WidgetListView>{};
  for (final list in lists) {
    if (list.id == kWidgetListAll) continue;
    final data = _listData(
      filterTasksForWidgetList(dayTasks, list.id),
      now: now,
      projectColorById: projectColorById,
      rowsPerBucket: rowsPerBucket,
      dateFormat: dateFormat,
      localeTag: localeTag,
      hideTitles: hideTitles,
    );
    views[list.id] = WidgetListView(
      openToday: data.openToday,
      openTodayLabel: _openLabel(data.openToday),
      buckets: data.buckets,
      next: data.next,
    );
  }

  return WidgetDayView(
    date: awDayParam(DateTime(now.year, now.month, now.day)),
    header: WidgetDateHeader(
      weekday: DateFormat.EEEE(localeTag).format(now),
      day: DateFormat.d(localeTag).format(now),
      month: DateFormat.MMMM(localeTag).format(now),
    ),
    openToday: all.openToday,
    openTodayLabel: _openLabel(all.openToday),
    buckets: all.buckets,
    next: all.next,
    views: views,
  );
}

String _openLabel(int count) =>
    'widget.openToday'.tr(args: {'count': '$count'});

/// The days of the widget in the server's words-free shape (#50, WIDGETS
/// §3.2): what `GET /widget/snapshot` answers in `days`, built from the SAME
/// grouping, counts, caps and time rules as [buildWidgetSnapshot]. Bucket
/// keys instead of labels, raw instants instead of formatted times, a
/// [WidgetTimeStyle] name instead of a label.
///
/// It is how the app states the rule the server ports: the shared fixture
/// (`test/fixtures/widget_grouping_cases.json`) is written from this function,
/// and the API's grouping is tested against that file case by case.
///
/// [hideTitles] (default true, fail-closed like the route's `private=1`)
/// leaves every `title` key out. [instant] writes a moment; by default its
/// UTC ISO-8601 form.
List<Map<String, Object?>> buildWidgetServerDays(
  List<Task> tasks, {
  List<ExternalEvent> events = const [],
  required DateTime now,
  Map<String, String> projectColorById = const {},
  Iterable<Project> projects = const [],
  int rowsPerBucket = kWidgetRowsPerBucket,
  bool hideTitles = true,
  String Function(DateTime)? instant,
}) {
  final at = instant ?? (DateTime t) => t.toUtc().toIso8601String();
  final listable = _listable(projects).toList();

  Map<String, Object?> list(
    List<Task> listTasks,
    List<ExternalEvent> listEvents,
    DateTime viewNow,
  ) {
    final groups = groupTasksForWidget(
      listTasks,
      now: viewNow,
      events: listEvents,
    );

    Map<String, Object?> item(WidgetEntry entry, WidgetBucket bucket) =>
        switch (entry) {
          WidgetTaskEntry(:final task) => {
            'id': task.id,
            'done': task.isCompleted,
            'priority': task.priority,
            if (!hideTitles) 'title': task.title,
            'projectColor': ?_colorOf(task, projectColorById),
            if (task.dueAt case final due?) 'dueAt': at(due),
            if (widgetTaskTimeStyle(task, bucket, viewNow) case final style?)
              'timeStyle': style.name,
          },
          WidgetEventEntry(:final event, :final day) => {
            'id': event.id,
            'done': false,
            'priority': 'none',
            if (!hideTitles) 'title': event.title,
            'kind': kWidgetKindEvent,
            'day': awDayParam(day),
            'dueAt': at(event.startsAt),
            'endAt': at(event.endsAt),
            'allDay': event.isAllDay,
            'timeStyle': widgetEventTimeStyle(event, day, bucket).name,
          },
        };

    final picked = nextTaskForWidget(groups);
    return {
      'openToday': _openTodayOf(groups),
      if (picked != null)
        'next': {
          'id': picked.task.id,
          if (!hideTitles) 'title': picked.task.title,
          'bucket': picked.bucket.name,
          if (picked.task.dueAt case final due?) 'dueAt': at(due),
          if (widgetTaskTimeStyle(picked.task, picked.bucket, viewNow)
              case final style?)
            'timeStyle': style.name,
        },
      'buckets': [
        for (final group in groups)
          {
            'key': group.bucket.name,
            'count': group.entries.where(_isOpen).length,
            if (group.entries.skip(rowsPerBucket).where(_isOpen).length
                case final more when more > 0)
              'more': more,
            'items': [
              for (final entry in group.entries.take(rowsPerBucket))
                item(entry, group.bucket),
            ],
          },
      ],
    };
  }

  return [
    for (final moment in _dayMoments(now))
      () {
        final dayTasks = _tasksForDay(tasks, moment, now);
        return {
          'date': awDayParam(DateTime(moment.year, moment.month, moment.day)),
          ...list(dayTasks, events, moment),
          'views': {
            for (final project in listable)
              project.id: list(
                filterTasksForWidgetList(dayTasks, project.id),
                const [],
                moment,
              ),
          },
        };
      }(),
  ];
}

/// The fetch profile's version (WIDGETS §3.2).
const int kWidgetFetchProfileVersion = 1;

/// The ICU patterns the app's widget rows are written with for [format]
/// (WIDGETS §3.2 `patterns`): what [awFormatTime] and
/// `awFormatShort(withTime: false)` use, so the widget extension can say a
/// server row's time exactly as the app would. The system default: the
/// region's clock and day order, the year added for another year, and
/// Today/Tomorrow/Yesterday words ([relativeDays]); a chosen format: its own
/// time and short patterns, the same with or without a year, no words.
({String time, String day, String dayYear, bool relativeDays})
widgetDatePatterns({required String format, String? locale, String? region}) {
  final spec = awDateFormatSpec(format);
  final time = awTimePattern(format: format, locale: locale, region: region);
  if (spec.id != kAwSystemDateFormat) {
    return (
      time: time,
      day: spec.short!,
      dayYear: spec.short!,
      relativeDays: false,
    );
  }
  final order = awConventions(
    language: awLanguageOf(locale),
    region: region,
  ).order;
  // date_format.dart's `_systemDay`, pinned to it by
  // widget_fetch_profile_test.dart.
  final (day, dayYear) = switch (order) {
    AwDateOrder.dmy => ('d MMM', 'd MMM y'),
    AwDateOrder.mdy => ('MMM d', 'MMM d, y'),
    AwDateOrder.ymd => ('MMM d', 'y MMM d'),
  };
  return (time: time, day: day, dayYear: dayYear, relativeDays: true);
}

/// [url] as the profile carries it: trimmed, no trailing `/` (the widget
/// appends `/api/v1/…`).
String widgetFetchBaseUrl(String url) =>
    url.trim().replaceFirst(RegExp(r'/+$'), '');

/// The fetch profile (WIDGETS §3.2, `aw_widget_fetch_profile`): everything the
/// widget extension needs to ask the server for its days and to say them in
/// the app's words — never a credential (the widget token is its own Keychain
/// item) and never a title.
///
/// [hideTitles] is "Private widget" AS READ: the caller writes a profile only
/// once the setting has been read (OPH-337's fail-closed rule), because a
/// profile is what lets the extension fetch at all. [pendingOutbox] is how
/// many local writes have not reached the server — while it is above zero the
/// extension keeps the app's snapshot. [localWrittenAt] is when the app's
/// snapshot was last written, by this device's clock.
Map<String, Object?> buildWidgetFetchProfile({
  required String baseUrl,
  required TaskScope scope,
  required bool hideTitles,
  required String dateFormat,
  required int pendingOutbox,
  required DateTime localWrittenAt,
  String? region,
}) {
  final tag = AwI18n.instance.locale.toLanguageTag();
  final language = awLanguageOf(tag);
  final system = awDateFormatSpec(dateFormat).id == kAwSystemDateFormat;
  final patterns = widgetDatePatterns(
    format: dateFormat,
    locale: tag,
    region: region,
  );
  return {
    'v': kWidgetFetchProfileVersion,
    'baseUrl': widgetFetchBaseUrl(baseUrl),
    'scope': scope.toJson(),
    'private': hideTitles,
    // The tag the rows are formatted with: the system default formats in the
    // app's language, a chosen format in its full tag.
    'locale': system ? language : tag,
    'patterns': {
      'time': patterns.time,
      'day': patterns.day,
      'dayYear': patterns.dayYear,
      'relativeDays': patterns.relativeDays,
    },
    'strings': {
      for (final bucket in WidgetBucket.values)
        'bucket.${bucket.name}': 'widget.bucket.${bucket.name}'.tr(),
      'privateTitle': 'widget.privateTitle'.tr(),
      'privateEvent': 'widget.privateEvent'.tr(),
      'allDay': 'widget.allDay'.tr(),
      'today': AwI18n.instance.translateIn(language, 'format.today'),
      'tomorrow': AwI18n.instance.translateIn(language, 'format.tomorrow'),
      'yesterday': AwI18n.instance.translateIn(language, 'format.yesterday'),
    },
    'pendingOutbox': pendingOutbox,
    'localWrittenAtMs': localWrittenAt.millisecondsSinceEpoch,
  };
}
