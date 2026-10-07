/// Worked time and what it cost — the two shapes every EE surface that
/// shows labour shares (the request's worklog panel since EE-208, a
/// machine's history since EE-240).
///
/// A leaf with no imports of its own models: the worklog models and the
/// asset models both need these, and each importing the other would make
/// them a cycle.
library;

import 'package:intl/intl.dart';

import '../../../i18n/i18n.dart';

/// Money in ONE currency, which is the only shape this product prints money in.
///
/// There is deliberately no `total` beside a list of these: adding two
/// currencies would invent an exchange rate, and a figure in a currency nobody
/// chose is worse than no figure because it looks like an answer.
class EeMoneyByCurrency {
  const EeMoneyByCurrency({
    required this.currency,
    required this.costMinor,
    required this.minutes,
  });

  final String currency;

  /// The currency's smallest unit — kuruş, cent. Divided only at the moment it
  /// is drawn, never in the model.
  final int costMinor;
  final int minutes;

  factory EeMoneyByCurrency.fromJson(Map<String, dynamic> json) =>
      EeMoneyByCurrency(
        currency: json['currency'] as String? ?? '',
        costMinor: (json['costMinor'] as num?)?.toInt() ?? 0,
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      );
}

/// The request's hours, and what they are worth — in the only shape money has.
///
/// `minutes` is ONE number because minutes are one unit everywhere.
/// `byCurrency` is a LIST because money is not, and there is deliberately no
/// field that could hold a single total: two technicians billed in two
/// currencies are two figures, and a third one would be an invented exchange
/// rate.
class EeWorklogTotals {
  const EeWorklogTotals({
    required this.minutes,
    required this.unpricedMinutes,
    required this.byCurrency,
  });

  final int minutes;

  /// Time logged by people whose role has no rate. Shown, because an empty
  /// cost beside real minutes means "nobody priced this role", not "free".
  final int unpricedMinutes;
  final List<EeMoneyByCurrency> byCurrency;

  static const empty = EeWorklogTotals(
    minutes: 0,
    unpricedMinutes: 0,
    byCurrency: [],
  );

  factory EeWorklogTotals.fromJson(Map<String, dynamic> json) =>
      EeWorklogTotals(
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        unpricedMinutes: (json['unpricedMinutes'] as num?)?.toInt() ?? 0,
        byCurrency: (json['byCurrency'] as List<dynamic>? ?? const [])
            .map((e) => EeMoneyByCurrency.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One spelling of worked time for every surface that writes it (OPH-358,
/// UI-AUDIT #71): whole minutes and hours, the way people say them — "45 dk",
/// "1 sa 15 dk", "2 sa". The old one-decimal hours turned 45 minutes into
/// "0.8" with an English decimal point, and lost the minutes doing it.
String eeDurationText(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return 'ee.duration.minutes'.tr(args: {'m': '$m'});
  if (m == 0) return 'ee.duration.hours'.tr(args: {'h': '$h'});
  return 'ee.duration.hoursMinutes'.tr(args: {'h': '$h', 'm': '$m'});
}

/// Money in the reader's locale (OPH-358, UI-AUDIT #78): "385.000,00 TRY",
/// never "385000.00 TRY". The currency is the record's own, never converted.
String eeMoneyText(int minor, String? currency) {
  final amount = NumberFormat.decimalPatternDigits(
    locale: AwI18n.instance.locale.toLanguageTag(),
    decimalDigits: 2,
  ).format(minor / 100);
  return currency == null ? amount : '$amount $currency';
}
