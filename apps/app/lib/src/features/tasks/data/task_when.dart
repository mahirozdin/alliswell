import '../../../i18n/i18n.dart';
import 'task.dart';

/// "When" and "Duration" (OPH-372, ADR-0053) — the pure rules every surface
/// shares, so Home, the widget, the AI context and (OPH-373) the natural
/// language parser cannot disagree about them.
///
/// A task carries three times and they are NEVER merged:
///
/// - `dueAt` — the deadline. It owns the alarm and Overdue.
/// - `scheduledStartAt`/`scheduledEndAt` — the calendar block, written only by
///   a drag in Google or Apple Calendar.
/// - `startAt` — "when": the DAY the user plans to do it, the day it enters
///   Today. Only its local date matters.
///
/// Pulling a Friday deadline's "when" to Monday therefore moves nothing but
/// the row: the alarm stays on Friday.

/// The local calendar day of [value] (00:00, no time).
DateTime awLocalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// THE value a "when" is stored as: the chosen day's local 00:00, in UTC ISO.
///
/// Local midnight, so the server's "start_at < end of today" (the MCP today
/// view) and the device's day arithmetic agree on the day. Write it through
/// the store body: `{'startAt': awWhenIso(day)}`; `null` clears it.
String awWhenIso(DateTime day) {
  final local = day.isUtc ? day.toLocal() : day;
  return DateTime(local.year, local.month, local.day).toUtc().toIso8601String();
}

/// The task's "when" day, or null when it has none.
DateTime? taskWhenDay(Task task) =>
    task.startAt == null ? null : awLocalDay(task.startAt!);

/// Overdue is decided by the deadline ALONE (ADR-0053): a past "when" is not
/// a debt — it just means the task is on today's list.
bool taskIsOverdueOn(Task task, DateTime today) {
  final due = task.dueAt;
  return due != null && awLocalDay(due).isBefore(today);
}

/// The one filing rule (ADR-0053): the day a NOT-overdue task belongs to.
///
/// - With a "when": that day, rolled forward to [today] once it has come —
///   and never later than the deadline's day (the deadline wins when "when"
///   was set after it).
/// - Without one: the deadline's day.
/// - With neither: null (No date).
///
/// Callers decide Overdue first ([taskIsOverdueOn]); this is only asked about
/// the rest.
DateTime? taskPlanDay(Task task, DateTime today) {
  final dueDay = task.dueAt == null ? null : awLocalDay(task.dueAt!);
  final whenDay = taskWhenDay(task);
  if (whenDay == null) return dueDay;
  var day = whenDay.isBefore(today) ? today : whenDay;
  if (dueDay != null && dueDay.isBefore(day)) day = dueDay;
  return day;
}

/// The longest duration the app offers (a block never outgrows its day — the
/// mirror caps there too). The server accepts more (0..60000).
const int kAwMaxEstimatedMinutes = 1440;

/// The duration picker's one-tap choices.
const List<int> kAwDurationPresets = [15, 30, 45, 60, 90, 120, 180];

/// "45 min", "1 h", "1 h 30 min" ("45 dk", "1 sa", "1 sa 30 dk").
String awFormatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) {
    return 'task.durationValue.minutes'.tr(args: {'m': '$m'});
  }
  if (m == 0) return 'task.durationValue.hours'.tr(args: {'h': '$h'});
  return 'task.durationValue.hoursMinutes'.tr(args: {'h': '$h', 'm': '$m'});
}
