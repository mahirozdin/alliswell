import 'labour_models.dart';

export 'labour_models.dart'
    show EeMoneyByCurrency, EeWorklogTotals, eeHoursText;

/// One person's record of their own labour on a request (EE-208).
///
/// Entered by hand — there is no timer, and the reason is the task's own: a
/// technician in the field does not start a stopwatch, and a start/stop clock
/// would produce a second source of truth for the same minutes, wrong every
/// time somebody forgets to stop it and wrong in the direction that inflates
/// a bill.
class EeWorklog {
  const EeWorklog({
    required this.id,
    required this.userId,
    required this.minutes,
    required this.workedOn,
    this.note,
    this.rateMinor,
    this.currency,
    this.costMinor,
  });

  final String id;

  /// WHOSE hours. Not who typed them — a supervisor entering a colleague's
  /// forgotten Friday does not become the author of that labour.
  final String userId;
  final int minutes;

  /// The day the work happened, not the day it was typed. `YYYY-MM-DD`.
  final String workedOn;
  final String? note;

  /// What the hour was priced at WHEN THIS WAS SAVED. Null when the person's
  /// role carries no rate, and null is not zero: zero is a claim about what an
  /// hour is worth.
  final int? rateMinor;
  final String? currency;

  /// Minor units. Null whenever the rate is — the field is hidden, not empty.
  final int? costMinor;

  bool get hasCost => costMinor != null && currency != null;

  factory EeWorklog.fromJson(Map<String, dynamic> json) => EeWorklog(
    id: json['id'] as String,
    userId: json['userId'] as String? ?? '',
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    workedOn: json['workedOn'] as String? ?? '',
    note: json['note'] as String?,
    rateMinor: (json['rateMinor'] as num?)?.toInt(),
    currency: json['currency'] as String?,
    costMinor: (json['costMinor'] as num?)?.toInt(),
  );
}

/// What the worklog panel draws: the entries and the server's own totals.
///
/// The totals come from the SERVER beside the rows they were computed from,
/// rather than being summed here. It is the one place a client could quietly
/// produce a cross-currency figure, and the way to make that impossible is to
/// never give the client the arithmetic.
class EeWorklogPanel {
  const EeWorklogPanel({required this.worklogs, required this.totals});

  final List<EeWorklog> worklogs;
  final EeWorklogTotals totals;

  static const empty = EeWorklogPanel(
    worklogs: [],
    totals: EeWorklogTotals.empty,
  );

  factory EeWorklogPanel.fromJson(Map<String, dynamic> json) => EeWorklogPanel(
    worklogs: (json['worklogs'] as List<dynamic>? ?? const [])
        .map((e) => EeWorklog.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    totals: EeWorklogTotals.fromJson(
      (json['totals'] as Map<String, dynamic>?) ?? const {},
    ),
  );
}
