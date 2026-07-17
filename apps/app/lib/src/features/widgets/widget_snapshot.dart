import 'package:intl/intl.dart';

import '../../i18n/i18n.dart';
import '../tasks/data/task.dart';
import 'widget_grouping.dart';

/// The JSON snapshot the app writes to the shared container for the native
/// widgets to render (OPH-130, WIDGETS.md §3.1). Kept SMALL and pre-localized —
/// the native side does no i18n and no DB access, it just draws this.
const int kWidgetSnapshotVersion = 1;

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
  });

  final int version;
  final String generatedAt;
  final String locale;
  final WidgetDateHeader date;
  final List<WidgetBucketData> buckets;

  Map<String, dynamic> toJson() => {
    'v': version,
    'generatedAt': generatedAt,
    'locale': locale,
    'date': date.toJson(),
    'buckets': [for (final bucket in buckets) bucket.toJson()],
  };
}

String? _timeLabel(Task task, WidgetBucket bucket, String localeTag) {
  final due = task.dueAt;
  if (due == null) return null;
  final local = due.toLocal();
  if (bucket == WidgetBucket.today) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  // Overdue / this week / this month: a short date says more than a bare time.
  return DateFormat.MMMd(localeTag).format(local);
}

WidgetTaskRow _rowFor(
  Task task,
  WidgetBucket bucket,
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
    time: _timeLabel(task, bucket, localeTag),
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
            _rowFor(task, group.bucket, localeTag, projectColorById),
        ],
        more: group.tasks.length > rowsPerBucket
            ? group.tasks.length - rowsPerBucket
            : 0,
      ),
  ];

  return WidgetSnapshot(
    version: kWidgetSnapshotVersion,
    generatedAt: now.toUtc().toIso8601String(),
    locale: AwI18n.instance.locale.languageCode,
    date: WidgetDateHeader(
      weekday: DateFormat.EEEE(localeTag).format(now),
      day: DateFormat.d(localeTag).format(now),
      month: DateFormat.MMMM(localeTag).format(now),
    ),
    buckets: buckets,
  );
}
