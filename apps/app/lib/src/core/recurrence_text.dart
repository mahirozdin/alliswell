import 'package:intl/intl.dart';

import '../i18n/i18n.dart';
import 'date_format.dart';
import 'recurrence.dart';

/// The rule, as a sentence (OPH-207, DESIGN §25 R2).
///
/// Built from the rule per language, never assembled from translated
/// fragments: Turkish and English pick their own word order out of the same
/// object. The i18n facade has no plural machinery (ADR-0009), so every count
/// form is its own key rather than a runtime suffix.
///
/// Pure — no widgets, no providers, unit-testable in `test/core/` like the
/// other `core/` helpers.
String awRepeatSentence(
  AwRepeatRule rule, {
  required String dateFormat,
  String? locale,
}) {
  final parts = <String>[_frequency(rule), ..._selectors(rule, locale: locale)]
    ..removeWhere((part) => part.isEmpty);
  final end = _end(rule, dateFormat: dateFormat, locale: locale);
  final head = parts.join(' ');
  return end.isEmpty ? head : '$head · $end';
}

String _frequency(AwRepeatRule rule) {
  final n = rule.interval;
  final many = n > 1;
  final args = {'n': '$n'};
  return switch (rule.freq) {
    AwRepeatFreq.daily =>
      many ? 'repeat.every.dailyN'.tr(args: args) : 'repeat.every.daily'.tr(),
    AwRepeatFreq.weekly =>
      many ? 'repeat.every.weeklyN'.tr(args: args) : 'repeat.every.weekly'.tr(),
    AwRepeatFreq.monthly =>
      many
          ? 'repeat.every.monthlyN'.tr(args: args)
          : 'repeat.every.monthly'.tr(),
    AwRepeatFreq.yearly =>
      many ? 'repeat.every.yearlyN'.tr(args: args) : 'repeat.every.yearly'.tr(),
  };
}

/// The "which days" half of the sentence.
List<String> _selectors(AwRepeatRule rule, {String? locale}) {
  switch (rule.freq) {
    case AwRepeatFreq.daily:
      return const [];
    case AwRepeatFreq.weekly:
      if (rule.byWeekday.isEmpty) return const [];
      return [_weekdayList(rule.byWeekday)];
    case AwRepeatFreq.monthly:
      return [_monthSelector(rule)];
    case AwRepeatFreq.yearly:
      final months = rule.byMonth.isEmpty
          ? ''
          : rule.byMonth
                .map(
                  (m) => DateFormat.MMMM(
                    locale ?? AwI18n.instance.locale.languageCode,
                  ).format(DateTime(2000, m)),
                )
                .join(', ');
      final day = _monthSelector(rule);
      return [months, day]..removeWhere((p) => p.isEmpty);
  }
}

/// Day-of-month / weekday selectors, shared by monthly and yearly.
String _monthSelector(AwRepeatRule rule) {
  final afterDay = awAfterDayOf(rule);
  if (afterDay != null) {
    return 'repeat.on.afterDay'.tr(
      args: {
        'day': '${afterDay.day}',
        'weekday': _weekdayName(afterDay.weekday),
      },
    );
  }

  final phrases = <String>[];
  for (final day in rule.byMonthDay) {
    phrases.add(
      day == -1
          ? 'repeat.on.lastDay'.tr()
          : 'repeat.on.monthDay'.tr(args: {'day': '$day'}),
    );
  }
  for (final pick in rule.byWeekday) {
    final name = _weekdayName(pick.day);
    phrases.add(switch (pick.ordinal) {
      null => name,
      -1 => 'repeat.on.lastWeekday'.tr(args: {'weekday': name}),
      final ordinal => 'repeat.on.nthWeekday'.tr(
        args: {'ordinal': 'repeat.ordinal.$ordinal'.tr(), 'weekday': name},
      ),
    });
  }
  return phrases.join(', ');
}

/// "Every weekday" says so instead of listing five days.
String _weekdayList(List<AwWeekdayPick> picks) {
  final days = picks.map((p) => p.day).toSet();
  const weekdays = {'MO', 'TU', 'WE', 'TH', 'FR'};
  if (days.length == 5 && days.containsAll(weekdays)) {
    return 'repeat.on.weekdays'.tr();
  }
  return kAwWeekdays.where(days.contains).map(_weekdayName).join(', ');
}

String _weekdayName(String code) => 'repeat.weekday.${code.toLowerCase()}'.tr();

String _end(AwRepeatRule rule, {required String dateFormat, String? locale}) {
  switch (rule.end.type) {
    case 'until':
      final parsed = DateTime.tryParse(rule.end.until ?? '');
      if (parsed == null) return '';
      return 'repeat.end.untilSentence'.tr(
        args: {
          'date': awFormatDate(parsed, format: dateFormat, locale: locale),
        },
      );
    case 'count':
      return 'repeat.end.countSentence'.tr(
        args: {'count': '${rule.end.count}'},
      );
    default:
      return 'repeat.end.neverSentence'.tr();
  }
}

/// Scenario C, recognised rather than stored (ADR-0020 §3): exactly one plain
/// weekday plus a seven-day window of consecutive month days reads as "the
/// first {weekday} after day {N}". Returns null when the rule is something else.
({int day, String weekday})? awAfterDayOf(AwRepeatRule rule) {
  if (rule.byWeekday.length != 1) return null;
  if (rule.byWeekday.single.ordinal != null) return null;
  if (rule.byMonthDay.length != 7) return null;
  final days = [...rule.byMonthDay]..sort();
  if (days.first < 2) return null;
  for (var i = 1; i < days.length; i += 1) {
    if (days[i] != days[i - 1] + 1) return null;
  }
  return (day: days.first - 1, weekday: rule.byWeekday.single.day);
}

/// The inverse of [awAfterDayOf] — what the dialog's builder writes.
AwRepeatRule awAfterDayRule({
  required int day,
  required String weekday,
  AwRepeatEnd end = const AwRepeatEnd.never(),
  int interval = 1,
}) => AwRepeatRule(
  freq: AwRepeatFreq.monthly,
  interval: interval,
  byWeekday: [AwWeekdayPick(weekday)],
  byMonthDay: [for (var i = 1; i <= 7; i += 1) day + i],
  end: end,
);
