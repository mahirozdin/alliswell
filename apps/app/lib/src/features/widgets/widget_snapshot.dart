import 'package:intl/intl.dart';

import '../../core/date_format.dart';

import '../../i18n/i18n.dart';
import '../projects/data/project.dart';
import '../tasks/data/task.dart';
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
/// **v4 (OPH-336):** adds `next` (the lock screen's one row), `lists` (what a
/// widget can be set to) and `views` (each project's own buckets, count and
/// next task). The whole list stays at the top level, where v3 put it, so an
/// unconfigured widget — and a widget from before v4 — reads exactly what it
/// always read. Same tolerance rule again: every new field is optional.
const int kWidgetSnapshotVersion = 4;

/// How many rows per bucket the snapshot carries; the native layer trims further
/// per widget size. The largest tier shows the most, so keep this generous.
const int kWidgetRowsPerBucket = 12;

class WidgetTaskRow {
  const WidgetTaskRow({
    required this.id,
    required this.title,
    required this.done,
    required this.priority,
    this.time,
    this.projectColor,
  });

  final String id;
  final String title;
  final bool done;
  final String priority;

  /// Pre-formatted short label (HH:mm for Today, a short date otherwise), or null.
  final String? time;

  /// The task's project color as `#RRGGBB`, or null. Native computes readable ink.
  final String? projectColor;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'priority': priority,
    if (time != null) 'time': time,
    if (projectColor != null) 'projectColor': projectColor,
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

  /// `count - items.length` — how many rows were trimmed ("+N more").
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

  /// What is on the user TODAY: overdue + due today, open tasks only
  /// (OPH-187, DESIGN §8 W9). Snoozed and muted tasks count — they are still
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

  Map<String, dynamic> toJson() => {
    'v': version,
    'generatedAt': generatedAt,
    'locale': locale,
    'date': date.toJson(),
    'strings': strings,
    'clockFormat': clockFormat,
    if (openToday > 0) 'openToday': openToday,
    if (next != null) 'next': next!.toJson(),
    'buckets': [for (final bucket in buckets) bucket.toJson()],
    'lists': [for (final list in lists) list.toJson()],
    if (views.isNotEmpty)
      'views': {
        for (final entry in views.entries) entry.key: entry.value.toJson(),
      },
  };
}

String? _timeLabel(
  Task task,
  WidgetBucket bucket,
  String localeTag,
  String dateFormat,
) {
  final due = task.dueAt;
  if (due == null) return null;
  // OPH-174: the widget speaks the SAME format as the app — a widget and an app
  // disagreeing about a date, side by side on one screen, is indefensible.
  if (bucket == WidgetBucket.today) {
    return awFormatTime(due, format: dateFormat, locale: localeTag);
  }
  // Overdue / this week / this month: a short date says more than a bare time.
  return awFormatShort(
    due,
    format: dateFormat,
    locale: localeTag,
    withTime: false,
  );
}

WidgetTaskRow _rowFor(
  Task task,
  WidgetBucket bucket,
  String dateFormat,
  String localeTag,
  Map<String, String> projectColorById,
) {
  final color = task.projectId != null
      ? projectColorById[task.projectId]
      : task.colorRgb;
  return WidgetTaskRow(
    id: task.id,
    title: task.title,
    done: task.status == 'completed',
    priority: task.priority,
    time: _timeLabel(task, bucket, localeTag, dateFormat),
    projectColor: color,
  );
}

/// The projects a widget can be set to (OPH-336), after the whole list: the
/// ones a task can be filed under — not the archived ones, which is the task
/// picker's rule too (`project_picker.dart`) — in the order given, which is
/// the Projects screen's (sort order, then creation).
List<WidgetListChoice> widgetListChoices(Iterable<Project> projects) => [
  WidgetListChoice(id: kWidgetListAll, name: 'widget.list.all'.tr()),
  for (final project in projects)
    if (project.status != 'archived')
      WidgetListChoice(
        id: project.id,
        name: project.name,
        color: project.colorRgb,
      ),
];

/// One list's buckets, open count and next task. The whole list and every
/// project view come out of this one function, so they cannot drift apart.
({List<WidgetBucketData> buckets, int openToday, WidgetNextTask? next})
_listData(
  List<Task> tasks, {
  required DateTime now,
  required Map<String, String> projectColorById,
  required int rowsPerBucket,
  required String dateFormat,
  required String localeTag,
}) {
  final groups = groupTasksForWidget(tasks, now: now);

  final buckets = [
    for (final group in groups)
      WidgetBucketData(
        key: group.bucket.name,
        label: 'widget.bucket.${group.bucket.name}'.tr(),
        count: group.tasks.length,
        items: [
          for (final task in group.tasks.take(rowsPerBucket))
            _rowFor(
              task,
              group.bucket,
              dateFormat,
              localeTag,
              projectColorById,
            ),
        ],
        more: group.tasks.length > rowsPerBucket
            ? group.tasks.length - rowsPerBucket
            : 0,
      ),
  ];

  // Counted from the SAME grouping the widget draws, so the number and the
  // rows can never disagree — and counted here, in pure Dart, because the
  // native layer must never carry product logic (W9).
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

  final picked = nextTaskForWidget(groups);
  final next = picked == null
      ? null
      : WidgetNextTask(
          id: picked.task.id,
          title: picked.task.title,
          bucket: picked.bucket.name,
          label: 'widget.bucket.${picked.bucket.name}'.tr(),
          time: _timeLabel(picked.task, picked.bucket, localeTag, dateFormat),
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
WidgetSnapshot buildWidgetSnapshot(
  List<Task> tasks, {
  required DateTime now,
  Map<String, String> projectColorById = const {},
  Iterable<Project> projects = const [],
  int rowsPerBucket = kWidgetRowsPerBucket,

  /// The user's display format (OPH-174). Defaults to "follow the language" so
  /// unit tests and any future caller stay honest without extra ceremony.
  String dateFormat = kAwSystemDateFormat,
}) {
  final localeTag = AwI18n.instance.locale.toLanguageTag();

  final all = _listData(
    tasks,
    now: now,
    projectColorById: projectColorById,
    rowsPerBucket: rowsPerBucket,
    dateFormat: dateFormat,
    localeTag: localeTag,
  );

  // OPH-336: every list a widget can be set to is computed HERE, with the same
  // function as the whole list — the native side only picks one by id.
  final lists = widgetListChoices(projects);
  final views = <String, WidgetListView>{};
  for (final list in lists) {
    if (list.id == kWidgetListAll) continue;
    final data = _listData(
      filterTasksForWidgetList(tasks, list.id),
      now: now,
      projectColorById: projectColorById,
      rowsPerBucket: rowsPerBucket,
      dateFormat: dateFormat,
      localeTag: localeTag,
    );
    views[list.id] = WidgetListView(
      openToday: data.openToday,
      openTodayLabel: 'widget.openToday'.tr(
        args: {'count': '${data.openToday}'},
      ),
      buckets: data.buckets,
      next: data.next,
    );
  }

  return WidgetSnapshot(
    version: kWidgetSnapshotVersion,
    openToday: all.openToday,
    // The header clock's pattern, from the same preference the rows above use
    // (OPH-253 — the native side formats the minute, it does not choose how).
    clockFormat: widgetClockPattern(format: dateFormat, locale: localeTag),
    generatedAt: now.toUtc().toIso8601String(),
    locale: AwI18n.instance.locale.languageCode,
    date: WidgetDateHeader(
      weekday: DateFormat.EEEE(localeTag).format(now),
      day: DateFormat.d(localeTag).format(now),
      month: DateFormat.MMMM(localeTag).format(now),
    ),
    strings: {
      'allCaughtUp': 'widget.allCaughtUp'.tr(),
      'addTask': 'widget.addTask'.tr(),
      // Pre-localized like every other widget word — the native side owns no
      // translations (W-rule).
      'openToday': 'widget.openToday'.tr(args: {'count': '${all.openToday}'}),
      // OPH-336: the lock screen's heading, and the Android configure
      // screen's title — native words, the app's translations.
      'upNext': 'widget.upNext'.tr(),
      'chooseList': 'widget.chooseList'.tr(),
    },
    buckets: all.buckets,
    next: all.next,
    lists: lists,
    views: views,
  );
}
