/// Dates as the USER sees and picks them (round 9 — DESIGN §17).
///
/// One formatter for the whole app (D1): `DateTime.toString()` and hand-rolled
/// `padLeft` strings in the UI are bugs — they cannot follow a locale, and they
/// cannot follow the user's chosen format. The functions are pure (the format id
/// and locale are parameters), so they unit-test without a widget or a provider;
/// the preference itself lives in `dateFormatProvider` (core/persisted_prefs).
library;

import 'package:intl/intl.dart';

import '../i18n/i18n.dart';

/// A display format the user can pick. The [id] is PERSISTED (localKv), so ids
/// are append-only — never rename one.
class AwDateFormatSpec {
  const AwDateFormatSpec(this.id, {this.date, this.time, this.short});

  final String id;

  /// ICU pattern for the date part; null = the locale's own short date.
  final String? date;

  /// ICU pattern for the time part; null = the locale's own clock (which is
  /// where 12h vs 24h comes from when the user follows the system).
  final String? time;

  /// ICU pattern for list rows — no year, because a row is about *when soon*;
  /// null = the locale's own "MMM d".
  final String? short;
}

/// "Follow the app language" — the factory default (D3).
const String kAwSystemDateFormat = 'system';

/// The offered formats, in the order the picker lists them. Each renders the
/// same sample instant in Settings, so the user chooses a RESULT, never a
/// pattern (D2).
const List<AwDateFormatSpec> kAwDateFormats = [
  // tr → 31.12.2026 23:59 · en → 12/31/2026 11:59 PM
  AwDateFormatSpec(kAwSystemDateFormat),
  AwDateFormatSpec(
    'dmy_dot',
    date: 'dd.MM.yyyy',
    time: 'HH:mm',
    short: 'd MMM',
  ),
  AwDateFormatSpec(
    'dmy_slash',
    date: 'dd/MM/yyyy',
    time: 'HH:mm',
    short: 'd MMM',
  ),
  AwDateFormatSpec(
    'mdy_12h',
    date: 'MM/dd/yyyy',
    time: 'h:mm a',
    short: 'MMM d',
  ),
  AwDateFormatSpec('iso', date: 'yyyy-MM-dd', time: 'HH:mm', short: 'dd-MM'),
  AwDateFormatSpec(
    'dmy_long',
    date: 'd MMMM yyyy',
    time: 'HH:mm',
    short: 'd MMMM',
  ),
];

/// The instant every option is previewed with (Settings): a date whose parts are
/// unmistakable in any order — 31.12.2026 23:59.
final DateTime kAwDateFormatSample = DateTime(2026, 12, 31, 23, 59);

/// The spec for [id], falling back to "follow the language" — a corrupted or
/// retired preference must never break a screen (the `parseTaskTime` rule).
AwDateFormatSpec awDateFormatSpec(String? id) => kAwDateFormats.firstWhere(
  (spec) => spec.id == id,
  orElse: () => kAwDateFormats.first,
);

String _locale(String? locale) =>
    locale ?? AwI18n.instance.locale.toLanguageTag();

/// Date only: "31.12.2026".
String awFormatDate(DateTime value, {required String format, String? locale}) {
  final spec = awDateFormatSpec(format);
  final tag = _locale(locale);
  final formatter = spec.date == null
      ? DateFormat.yMd(tag)
      : DateFormat(spec.date!, tag);
  return formatter.format(value.toLocal());
}

/// Time only: "23:59" (or "11:59 PM" where the format says so).
String awFormatTime(DateTime value, {required String format, String? locale}) {
  final spec = awDateFormatSpec(format);
  final tag = _locale(locale);
  final formatter = spec.time == null
      ? DateFormat.jm(tag)
      : DateFormat(spec.time!, tag);
  return formatter.format(value.toLocal());
}

/// The full instant: "31.12.2026 23:59". Detail rows and pickers use this.
String awFormatDateTime(
  DateTime value, {
  required String format,
  String? locale,
}) =>
    '${awFormatDate(value, format: format, locale: locale)} '
    '${awFormatTime(value, format: format, locale: locale)}';

/// The list-row form: "31 Ara 23:59" — no year, because rows are read at a
/// glance (D4). [withTime] false gives just the day ("31 Ara").
String awFormatShort(
  DateTime value, {
  required String format,
  String? locale,
  bool withTime = true,
}) {
  final spec = awDateFormatSpec(format);
  final tag = _locale(locale);
  final formatter = spec.short == null
      ? DateFormat.MMMd(tag)
      : DateFormat(spec.short!, tag);
  final day = formatter.format(value.toLocal());
  if (!withTime) return day;
  return '$day, ${awFormatTime(value, format: format, locale: locale)}';
}

/// Where a date picker OPENS when the field is still empty (round 9 #4,
/// OPH-173): **tomorrow**, never today.
///
/// Someone who means today taps today — it is right there. The far more common
/// intent is "the next day", and opening on today made that a two-tap move every
/// single time.
///
/// - [current] — an existing value always wins; you never fight a picker that
///   forgot what the field already says.
/// - [anchor] — the date this field belongs NEXT TO. A reminder opens on its
///   task's due day (a nudge lives near its deadline), not on tomorrow.
DateTime awInitialPickerDate({
  DateTime? current,
  DateTime? anchor,
  required DateTime now,
}) {
  final existing = current ?? anchor;
  if (existing != null) return existing;
  // Day arithmetic through the constructor so month/year roll over correctly
  // (and DST never shifts the calendar day the way `add(Duration(days: 1))` can).
  return DateTime(now.year, now.month, now.day + 1);
}
