import 'package:intl/intl.dart';

import '../../core/date_format.dart';

import '../../i18n/i18n.dart';
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
const int kWidgetSnapshotVersion = 3;

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

  Map<String, dynamic> toJson() => {
    'v': version,
    'generatedAt': generatedAt,
    'locale': locale,
    'date': date.toJson(),
    'strings': strings,
    'clockFormat': clockFormat,
    if (openToday > 0) 'openToday': openToday,
    'buckets': [for (final bucket in buckets) bucket.toJson()],
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

/// Builds the widget snapshot from open tasks. Pure (pass [now]); labels come
/// from the active locale (`AwI18n`) and dates from `intl` — so it carries
/// already-localized text and the native widget needs no translations.
///
/// [projectColorById] maps a task's `projectId` to its `#RRGGBB` color.
WidgetSnapshot buildWidgetSnapshot(
  List<Task> tasks, {
  required DateTime now,
  Map<String, String> projectColorById = const {},
  int rowsPerBucket = kWidgetRowsPerBucket,

  /// The user's display format (OPH-174). Defaults to "follow the language" so
  /// unit tests and any future caller stay honest without extra ceremony.
  String dateFormat = kAwSystemDateFormat,
}) {
  final localeTag = AwI18n.instance.locale.toLanguageTag();
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

  return WidgetSnapshot(
    version: kWidgetSnapshotVersion,
    openToday: openToday,
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
      'openToday': 'widget.openToday'.tr(args: {'count': '$openToday'}),
    },
    buckets: buckets,
  );
}
