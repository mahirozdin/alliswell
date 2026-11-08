/// The one formatter, `awFormat*` (OPH-408, ADR-0063 #6, DESIGN §17).
///
/// Date, time, duration, money, percent and file size come from here and from
/// `date_format.dart`, which this file exports. Separators, the date order and
/// the 12/24-hour clock follow the device REGION (`format_region.dart`); the
/// words follow the app language. A screen that formats a figure on its own —
/// `toStringAsFixed`, `NumberFormat(…)`, a hand-built "MB" — is a bug:
/// `test/core/format_single_source_test.dart` scans `lib/` for them.
library;

import 'package:intl/intl.dart';

import '../i18n/i18n.dart';
import 'format_region.dart';

export 'date_format.dart';
export 'format_region.dart';

/// What a figure with nothing to divide by shows: a ratio over 0 is "—",
/// never "0 %" (a promise kept 0 times out of 0 is not a failure).
const String kAwNoValue = '—';

String _numberLocale(String? locale, String? region) =>
    awConventions(language: awLanguageOf(locale), region: region).locale;

/// A plain figure in the region's separators: "48.500" / "48,500".
/// [decimals] is the most decimals shown; trailing zeros are dropped.
String awFormatNumber(
  num value, {
  int decimals = 0,
  String? locale,
  String? region,
}) {
  final f = NumberFormat.decimalPattern(_numberLocale(locale, region))
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = decimals;
  return f.format(value);
}

/// A figure typed into a form ("48500") shown in the region's separators
/// ("48.500"); text that is not a number comes back as it was. Every decimal
/// that was typed is kept ("0.001" stays "0,001"); trailing zeros drop.
String awFormatNumberText(String raw, {String? locale, String? region}) {
  final text = raw.trim();
  final parsed = num.tryParse(text);
  if (parsed == null) return raw;
  return awFormatNumber(
    parsed,
    decimals: _typedDecimals(text),
    locale: locale,
    region: region,
  );
}

/// How many decimals [text] (already a valid number) carries: "0.001" → 3,
/// "1e-3" → 3, "1.5e2" → 0. Capped at 15, what a double holds.
int _typedDecimals(String text) {
  final lower = text.toLowerCase();
  final e = lower.indexOf('e');
  final mantissa = e < 0 ? lower : lower.substring(0, e);
  final exponent = e < 0 ? 0 : int.tryParse(lower.substring(e + 1)) ?? 0;
  final dot = mantissa.indexOf('.');
  final fraction = dot < 0 ? 0 : mantissa.length - dot - 1;
  return (fraction - exponent).clamp(0, 15);
}

/// A percentage given as 0–100 (the server's shape): "%51,4", "51.4%",
/// "51,4 %" — the sign where the region puts it. Null (a ratio over 0) is
/// [kAwNoValue].
String awFormatPercent(
  double? percent, {
  int decimals = 1,
  String? locale,
  String? region,
}) {
  if (percent == null || percent.isNaN) return kAwNoValue;
  return NumberFormat.decimalPercentPattern(
    locale: _numberLocale(locale, region),
    decimalDigits: decimals,
  ).format(percent / 100);
}

/// Money from minor units in the record's own [currency], never converted:
/// "48.500 TL", "385.000,50 TL", "$48,500", "48.500 €". Whole amounts drop
/// the ",00". Turkish lira is written "TL", never the code "TRY".
String awFormatMoney(
  int minor,
  String? currency, {
  String? locale,
  String? region,
}) {
  final numberLocale = _numberLocale(locale, region);
  final decimals = minor % 100 == 0 ? 0 : 2;
  final amount = minor / 100;
  final code = currency?.toUpperCase();
  if (code == null || code.isEmpty) {
    return NumberFormat.decimalPatternDigits(
      locale: numberLocale,
      decimalDigits: decimals,
    ).format(amount);
  }
  if (code == 'TRY') {
    final n = NumberFormat.decimalPatternDigits(
      locale: numberLocale,
      decimalDigits: decimals,
    ).format(amount);
    return '$n TL';
  }
  final simple = NumberFormat.simpleCurrency(
    locale: numberLocale,
    name: code,
    decimalDigits: decimals,
  );
  if (!_kSharedCurrencySymbols.contains(simple.currencySymbol) ||
      code == NumberFormat.simpleCurrency(locale: numberLocale).currencyName) {
    return simple.format(amount);
  }
  // A symbol several currencies use ("$" for USD, CAD, AUD…) names the
  // region's own currency only; any other is written by its ISO code, kept
  // apart from the figure by a no-break space: "CAD 100", "100 CAD".
  final text = NumberFormat.currency(
    locale: numberLocale,
    name: code,
    symbol: code,
    decimalDigits: decimals,
  ).format(amount);
  return text.replaceFirstMapped(RegExp('$code(?=[0-9])'), (m) => '$code ');
}

/// Symbols `intl`'s simple-currency table gives to more than one currency
/// (G-C-R6): "$" alone could be USD, CAD, AUD or MXN.
const Set<String> _kSharedCurrencySymbols = {
  r'$',
  '£',
  '¥',
  'kr',
  '₩', // ₩: KRW, KPW
  'din',
  'dh',
  'Bs',
  'Rial',
  'Riyal',
  'Rs',
};

/// A file size: "Under 1 KB" below a kilobyte (a byte count is not a size
/// anyone reads), then KB/MB/GB with at most one decimal in the region's
/// separator ("6,3 MB").
String awFormatFileSize(int bytes, {String? locale, String? region}) {
  if (bytes < 1024) {
    return AwI18n.instance.translateIn(
      awLanguageOf(locale),
      'format.fileSize.underKb',
    );
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final n = awFormatNumber(value, decimals: 1, locale: locale, region: region);
  return '$n ${units[unit]}';
}

/// A span of minutes as people say it, in whole words: "45 dk", "2 saat",
/// "1 saat 30 dk", "2 gün 12 saat" — "45 min", "1 hour 30 min", "2 days 12
/// hours". No "g"/"sa" abbreviations (§3.1).
///
/// With [days] (spans: an SLA, an average resolution time) a span past a day
/// is spoken in days and hours, minutes dropped. Without it (a task's
/// estimate, logged work) hours keep counting: 25 hours of labour is not
/// "1 day".
String awFormatDuration(int minutes, {bool days = true, String? locale}) {
  final language = awLanguageOf(locale);
  String part(String unit, int n) => AwI18n.instance
      .translateIn(language, 'format.duration.$unit${n == 1 ? 'One' : 'Other'}')
      .replaceAll('{n}', '$n');

  final total = minutes < 0 ? 0 : minutes;
  final d = days ? total ~/ 1440 : 0;
  final h = (total - d * 1440) ~/ 60;
  final m = total % 60;
  if (d > 0) {
    return [part('days', d), if (h > 0) part('hours', h)].join(' ');
  }
  if (h > 0) {
    return [part('hours', h), if (m > 0) part('minutes', m)].join(' ');
  }
  return part('minutes', m);
}
