/// Dates as the USER sees and picks them (round 9 — DESIGN §17; OPH-408).
///
/// One formatter for the whole app (D1): `DateTime.toString()` and hand-rolled
/// `padLeft` strings in the UI are bugs — they cannot follow a locale, and they
/// cannot follow the user's chosen format. The functions are pure (the format id,
/// language, region and "now" are parameters), so they unit-test without a
/// widget or a provider; the preference itself lives in `dateFormatProvider`
/// (core/persisted_prefs).
///
/// The factory default ("system", ADR-0063 #6) never writes a numeric date: the
/// words follow the app language, the order and the 12/24-hour clock follow the
/// device REGION (`format_region.dart`), today is a bare time in a row, and the
/// year appears only when it is not this year. Numbers, money, percentages,
/// file sizes and durations live beside it in `format.dart`.
library;

import 'package:intl/intl.dart';

import '../i18n/i18n.dart';
import 'format_region.dart';

/// A display format the user can pick. The [id] is PERSISTED (localKv), so ids
/// are append-only — never rename one.
class AwDateFormatSpec {
  const AwDateFormatSpec(this.id, {this.date, this.time, this.short});

  final String id;

  /// ICU pattern for the date part; null only on "system", which composes its
  /// own from the region (`_systemDay`).
  final String? date;

  /// ICU pattern for the time part; null = the region's own clock (which is
  /// where 12h vs 24h comes from when the user follows the system).
  final String? time;

  /// ICU pattern for list rows — no year, because a row is about *when soon*;
  /// null only on "system".
  final String? short;
}

/// "Follow the region" — the factory default (D3, amended by OPH-408).
const String kAwSystemDateFormat = 'system';

/// The offered formats, in the order the picker lists them. Each renders the
/// same sample instant in Settings, so the user chooses a RESULT, never a
/// pattern (D2).
const List<AwDateFormatSpec> kAwDateFormats = [
  // tr/TR → 31 Ara, 23:59 · en/US → Dec 31, 11:59 PM · en/DE → 31 Dec, 23:59
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

bool _isSystem(AwDateFormatSpec spec) => spec.id == kAwSystemDateFormat;

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

/// The day [value] falls on relative to [now]: -1 yesterday, 0 today, 1
/// tomorrow; null for any other day. Calendar days, never 24-hour spans.
int? _relativeDay(DateTime value, DateTime now) {
  final diff = _day(value).difference(_day(now)).inHours;
  // A DST day is 23 or 25 hours long; round to whole days.
  final days = (diff / 24).round();
  return days >= -1 && days <= 1 ? days : null;
}

/// "Bugün" / "Yarın" / "Dün" in [language] — the UI's words.
String _dayWord(int relative, String language) =>
    AwI18n.instance.translateIn(language, switch (relative) {
      -1 => 'format.yesterday',
      0 => 'format.today',
      _ => 'format.tomorrow',
    });

/// The system default's clock: the region's 12/24 hours, the UI's AM/PM
/// words. A narrow no-break space keeps "1:47 PM" on one line.
String _systemTimePattern(AwConventions c) =>
    c.uses24h ? 'HH:mm' : 'h:mm\u202Fa';

/// The system default's day: the region's order, the UI's month names, never
/// numeric (ADR-0063 #6). The year is written only when it is not this year.
String _systemDay(
  DateTime local,
  String language,
  AwConventions c,
  DateTime now,
) {
  final withYear = local.year != now.year;
  final pattern = switch (c.order) {
    AwDateOrder.dmy => withYear ? 'd MMM y' : 'd MMM',
    AwDateOrder.mdy => withYear ? 'MMM d, y' : 'MMM d',
    AwDateOrder.ymd => withYear ? 'y MMM d' : 'MMM d',
  };
  return DateFormat(pattern, language).format(local);
}

/// The system default's instant. [todayWord] false gives a row's bare "13:47"
/// for today; true gives a detail line's "Bugün 13:47".
String _systemInstant(
  DateTime value, {
  required String? locale,
  required String? region,
  required DateTime? now,
  required bool todayWord,
}) {
  final language = awLanguageOf(locale);
  final c = awConventions(language: language, region: region);
  final local = value.toLocal();
  final at = now ?? DateTime.now();
  final time = DateFormat(_systemTimePattern(c), language).format(local);
  final relative = _relativeDay(local, at);
  if (relative == 0 && !todayWord) return time;
  if (relative != null) return '${_dayWord(relative, language)}\u00A0$time';
  // A no-break space after the comma: a date never parts from its time.
  return '${_systemDay(local, language, c, at)},\u00A0$time';
}

/// Date only. The system default: "7 Kas" this year, "7 Kas 2025" otherwise —
/// in the region's order ("Nov 7", "7 Nov"). A chosen format: "31.12.2026".
String awFormatDate(
  DateTime value, {
  required String format,
  String? locale,
  String? region,
  DateTime? now,
}) {
  final spec = awDateFormatSpec(format);
  if (_isSystem(spec)) {
    final language = awLanguageOf(locale);
    return _systemDay(
      value.toLocal(),
      language,
      awConventions(language: language, region: region),
      now ?? DateTime.now(),
    );
  }
  final tag = _locale(locale);
  return DateFormat(spec.date!, tag).format(value.toLocal());
}

/// The ICU clock pattern for [format] — the region's 12/24 hours by default.
/// The home-screen widget's native clock draws with it.
String awTimePattern({required String format, String? locale, String? region}) {
  final spec = awDateFormatSpec(format);
  if (!_isSystem(spec)) return spec.time!;
  return _systemTimePattern(
    awConventions(language: awLanguageOf(locale), region: region),
  );
}

/// Time only: "23:59", or "11:59 PM" where the region (or the chosen format)
/// keeps a 12-hour clock.
String awFormatTime(
  DateTime value, {
  required String format,
  String? locale,
  String? region,
}) {
  final spec = awDateFormatSpec(format);
  final language = _isSystem(spec) ? awLanguageOf(locale) : _locale(locale);
  return DateFormat(
    awTimePattern(format: format, locale: locale, region: region),
    language,
  ).format(value.toLocal());
}

/// The full instant, for detail rows and pickers. The system default:
/// "Bugün 13:47", "Yarın 11:00", "7 Kas, 13:47", "7 Kas 2025, 13:47".
/// A chosen format: "31.12.2026 23:59".
String awFormatDateTime(
  DateTime value, {
  required String format,
  String? locale,
  String? region,
  DateTime? now,
}) {
  final spec = awDateFormatSpec(format);
  if (_isSystem(spec)) {
    return _systemInstant(
      value,
      locale: locale,
      region: region,
      now: now,
      todayWord: true,
    );
  }
  return '${awFormatDate(value, format: format, locale: locale)} '
      '${awFormatTime(value, format: format, locale: locale)}';
}

/// The list-row form, read at a glance (D4). The system default: "13:47"
/// today, "Yarın 11:00", "7 Kas, 13:47", "7 Kas 2025, 13:47". [withTime]
/// false gives just the day ("7 Kas"). A chosen format keeps its short
/// pattern ("31 Ara, 23:59").
String awFormatShort(
  DateTime value, {
  required String format,
  String? locale,
  String? region,
  DateTime? now,
  bool withTime = true,
}) {
  final spec = awDateFormatSpec(format);
  if (_isSystem(spec)) {
    if (!withTime) {
      return awFormatDate(
        value,
        format: format,
        locale: locale,
        region: region,
        now: now,
      );
    }
    return _systemInstant(
      value,
      locale: locale,
      region: region,
      now: now,
      todayWord: false,
    );
  }
  final tag = _locale(locale);
  final day = DateFormat(spec.short!, tag).format(value.toLocal());
  if (!withTime) return day;
  return '$day, ${awFormatTime(value, format: format, locale: locale)}';
}

/// Whether a typed "5/11" means May 11 — the region writes the month first,
/// or the user chose the US format (quick add, OPH-373).
bool awMonthFirst({required String format, String? locale, String? region}) {
  final spec = awDateFormatSpec(format);
  if (!_isSystem(spec)) return spec.id == 'mdy_12h';
  return awConventions(language: awLanguageOf(locale), region: region).order ==
      AwDateOrder.mdy;
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

/// "3 days ago" for an instant in the past (round 19 #2).
///
/// Coarse on purpose: it is used where the exact number of minutes does not
/// matter — a missed-alarm card whose job is to say "this is history, not an
/// emergency" — and the clock time is always printed beside it, so precision is
/// available where precision is wanted.
///
/// Plurals go through separate keys rather than a `{n}` in one string: Turkish
/// does not pluralise the noun after a number ("3 gün önce"), English does
/// ("3 days ago"), and a single template cannot be right in both.
String awRelativePast(DateTime at, DateTime now) {
  final elapsed = now.difference(at.toLocal());
  if (elapsed.inMinutes < 1) return 'time.ago.justNow'.tr();
  if (elapsed.inHours < 1) {
    return 'time.ago.minutes'.tr(args: {'n': '${elapsed.inMinutes}'});
  }
  if (elapsed.inHours < 24) {
    return 'time.ago.hours'.tr(args: {'n': '${elapsed.inHours}'});
  }
  return 'time.ago.days'.tr(args: {'n': '${elapsed.inDays}'});
}

/// A day heading: "Perşembe · 16 Tem" (OPH-307).
///
/// The weekday comes first because that is what the reader is scanning for —
/// the request was "for each day", and people think in Thursday, not in the
/// 16th. The date follows so a heading is never ambiguous about WHICH
/// Thursday, which matters the moment a week rolls over.
///
/// The weekday name is `intl`'s, in the user's own locale; the date half goes
/// through [awFormatShort] so it obeys the same format preference every other
/// row does (D4).
String awFormatDayHeading(
  DateTime value, {
  required String format,
  String? locale,
  String? region,
  DateTime? now,
}) {
  final language = _isSystem(awDateFormatSpec(format))
      ? awLanguageOf(locale)
      : _locale(locale);
  final weekday = DateFormat.EEEE(language).format(value.toLocal());
  final date = awFormatShort(
    value,
    format: format,
    locale: locale,
    region: region,
    now: now,
    withTime: false,
  );
  return '$weekday · $date';
}
