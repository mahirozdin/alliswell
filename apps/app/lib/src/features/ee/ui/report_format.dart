import 'package:intl/intl.dart';

import '../../../i18n/i18n.dart';

/// How the boards write a figure (OPH-360, UI-AUDIT #88).
///
/// The dashboards used `toStringAsFixed`, which writes an English decimal
/// point in every language — "%40.3", "3.8", "5587.5 dk" on a Turkish screen.
/// These go through the reader's locale instead ("%40,3", "40.3%"), and an
/// average of minutes is spoken the way people say a span of time
/// ("3 g 21 sa"), not as a four-digit number of minutes.
String get _locale => AwI18n.instance.locale.toLanguageTag();

/// A percentage given as 0–100 (the server's shape), one decimal, in the
/// reader's locale — the sign on the side that language puts it.
String eePercentText(double percent) => NumberFormat.decimalPercentPattern(
  locale: _locale,
  decimalDigits: 1,
).format(percent / 100);

/// A plain figure with one decimal ("4,2" / "4.2").
String eeDecimalText(double value) => NumberFormat.decimalPatternDigits(
  locale: _locale,
  decimalDigits: 1,
).format(value);

/// A span of minutes as people say it: "45 dk", "2 sa 5 dk", "3 g 21 sa".
///
/// Rounded to whole minutes; past a day the minutes are dropped — "3 days 21
/// hours 7 minutes" is a precision nobody acts on in a report.
String eeSpanText(double minutes) {
  final total = minutes.round();
  final d = total ~/ 1440;
  final h = (total % 1440) ~/ 60;
  final m = total % 60;
  if (d > 0) {
    return h == 0
        ? 'ee.duration.days'.tr(args: {'d': '$d'})
        : 'ee.duration.daysHours'.tr(args: {'d': '$d', 'h': '$h'});
  }
  if (h == 0) return 'ee.duration.minutes'.tr(args: {'m': '$m'});
  if (m == 0) return 'ee.duration.hours'.tr(args: {'h': '$h'});
  return 'ee.duration.hoursMinutes'.tr(args: {'h': '$h', 'm': '$m'});
}
