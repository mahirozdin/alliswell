import 'package:flutter/foundation.dart';

/// An average and the population it speaks for (EE-205).
///
/// The two never travel apart, and the reason is the same one `EeCsatSummary`
/// carries: a figure whose scope nobody states is a figure somebody quotes.
/// `minutes` is null — not zero — when nothing was measured, because a desk
/// that promised nothing has no mean time to anything, and `0` on a screen
/// reads as "instant".
@immutable
class EeTimedAverage {
  const EeTimedAverage({
    required this.minutes,
    required this.measured,
    required this.total,
  });

  final double? minutes;
  final int measured;
  final int total;

  /// True when the average speaks for fewer requests than happened. The screen
  /// says so in words rather than leaving the reader to compare two numbers.
  bool get isPartial => measured < total;

  factory EeTimedAverage.fromJson(Map<String, dynamic>? json) => EeTimedAverage(
    minutes: (json?['minutes'] as num?)?.toDouble(),
    measured: (json?['measured'] as num?)?.toInt() ?? 0,
    total: (json?['total'] as num?)?.toInt() ?? 0,
  );
}

/// Satisfaction, with the response rate it rests on (EE-200's rule).
@immutable
class EeCsatFigure {
  const EeCsatFigure({
    required this.average,
    required this.answered,
    required this.sent,
  });

  final double? average;
  final int answered;
  final int sent;

  factory EeCsatFigure.fromJson(Map<String, dynamic>? json) => EeCsatFigure(
    average: (json?['average'] as num?)?.toDouble(),
    answered: (json?['answered'] as num?)?.toInt() ?? 0,
    sent: (json?['sent'] as num?)?.toInt() ?? 0,
  );
}

/// One row of the performance panel — a unit, or a person.
///
/// `key` and `label` can both be null and they mean different things, exactly
/// as they do on the SLA dashboard. A null KEY on the people axis is work
/// nobody was there for: a sweep, an automation, a request that settled on its
/// own. It is kept rather than dropped, because a panel whose rows do not add
/// up to the desk's totals is a panel somebody spends an afternoon
/// reconciling. A null LABEL is somebody whose account has since gone.
@immutable
class EePerformanceRow {
  const EePerformanceRow({
    this.key,
    this.label,
    required this.opened,
    required this.answered,
    required this.resolved,
    required this.backlogDelta,
    required this.mtta,
    required this.mttr,
    required this.csat,
    this.compliance,
  });

  final String? key;
  final String? label;
  final int opened;
  final int answered;
  final int resolved;
  final int backlogDelta;
  final EeTimedAverage mtta;
  final EeTimedAverage mttr;
  final EeCsatFigure csat;
  final double? compliance;

  factory EePerformanceRow.fromJson(Map<String, dynamic> json) =>
      EePerformanceRow(
        key: json['key'] as String?,
        label: json['label'] as String?,
        opened: (json['opened'] as num?)?.toInt() ?? 0,
        answered: (json['answered'] as num?)?.toInt() ?? 0,
        resolved: (json['resolved'] as num?)?.toInt() ?? 0,
        backlogDelta: (json['backlogDelta'] as num?)?.toInt() ?? 0,
        mtta: EeTimedAverage.fromJson(json['mtta'] as Map<String, dynamic>?),
        mttr: EeTimedAverage.fromJson(json['mttr'] as Map<String, dynamic>?),
        csat: EeCsatFigure.fromJson(json['csat'] as Map<String, dynamic>?),
        compliance: (json['compliance'] as num?)?.toDouble(),
      );
}

/// The panel (EE-205).
///
/// `closedIsNotPerformance` arrives FROM THE SERVER rather than living in the
/// app's strings, and that is deliberate: the sentence has to reach whoever
/// pulls these figures out through the API too, and a warning that exists only
/// in Flutter never does.
@immutable
class EePerformance {
  const EePerformance({
    required this.from,
    required this.to,
    required this.units,
    required this.agents,
    required this.closedIsNotPerformance,
    this.processTypes = const [],
  });

  final String from;
  final String to;
  final List<EePerformanceRow> units;
  final List<EePerformanceRow> agents;
  final String closedIsNotPerformance;

  /// EE-268 (AW-E21): incidents and service requests apart — the same row
  /// shape, keyed by the kind of work (`incident`, `request`, or null for
  /// work counted with no kind), each with its own SLA compliance.
  final List<EePerformanceRow> processTypes;

  factory EePerformance.fromJson(Map<String, dynamic> json) => EePerformance(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    units: ((json['units'] as List<dynamic>?) ?? const [])
        .map((e) => EePerformanceRow.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    agents: ((json['agents'] as List<dynamic>?) ?? const [])
        .map((e) => EePerformanceRow.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    closedIsNotPerformance: json['closedIsNotPerformance'] as String? ?? '',
    processTypes: ((json['processTypes'] as List<dynamic>?) ?? const [])
        .map(
          (e) => EePerformanceRow.fromJson({
            ...(e as Map<String, dynamic>),
            'key': e['processType'],
          }),
        )
        .toList(growable: false),
  );
}
