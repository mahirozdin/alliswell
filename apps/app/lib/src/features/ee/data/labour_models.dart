/// Worked time and what it cost — the two shapes every EE surface that
/// shows labour shares (the request's worklog panel since EE-208, a
/// machine's history since EE-240).
///
/// A leaf with no imports of its own: the worklog models and the asset models
/// both need these, and each importing the other would make them a cycle.
library;

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

/// One spelling of worked time for every surface that writes it: hours with
/// one decimal, so twenty minutes reads "0.3", never "0".
String eeHoursText(int minutes) => (minutes / 60).toStringAsFixed(1);
