import 'package:flutter/foundation.dart';

/// One axis entry on the SLA dashboard (EE-098).
///
/// `key` is the server's own identifier and `label` is what a person reads;
/// both can be null and they mean different things. A null KEY is the "no
/// service" bucket — requests that named nothing, which is a real category and
/// not an error. A null LABEL is a catalogue entry that has since been
/// retired: the count is still true, so the row stays and the screen says so
/// in words rather than dropping a number nobody can account for.
@immutable
class EeSlaBucket {
  const EeSlaBucket({this.key, this.label, required this.count});

  final String? key;
  final String? label;
  final int count;

  factory EeSlaBucket.fromJson(Map<String, dynamic> json) => EeSlaBucket(
    key: json['key'] as String?,
    label: json['label'] as String?,
    count: (json['count'] as num?)?.toInt() ?? 0,
  );
}

/// One broken promise, named — the list a manager actually acts on.
@immutable
class EeSlaBreach {
  const EeSlaBreach({
    required this.id,
    required this.subject,
    required this.priority,
    required this.status,
    this.slaDueAt,
  });

  final String id;
  final String subject;
  final String priority;
  final String status;
  final DateTime? slaDueAt;

  factory EeSlaBreach.fromJson(Map<String, dynamic> json) => EeSlaBreach(
    id: json['id'] as String,
    subject: json['subject'] as String,
    priority: json['priority'] as String,
    status: json['status'] as String,
    slaDueAt: json['slaDueAt'] == null
        ? null
        : DateTime.parse(json['slaDueAt'] as String).toLocal(),
  );
}

/// The whole dashboard, as one server-computed answer.
///
/// `compliance` is nullable and that is the honest part: a desk where nothing
/// has been judged yet is at NO percentage, not at 100 %. The screen shows a
/// dash where a cheerful number would be a lie.
@immutable
class EeSlaDashboard {
  const EeSlaDashboard({
    this.compliance,
    this.byStatus = const [],
    this.byUnit = const [],
    this.byService = const [],
    this.bySla = const [],
    this.breaches = const [],
  });

  final double? compliance;
  final List<EeSlaBucket> byStatus;
  final List<EeSlaBucket> byUnit;
  final List<EeSlaBucket> byService;
  final List<EeSlaBucket> bySla;
  final List<EeSlaBreach> breaches;

  int get total => byStatus.fold(0, (n, b) => n + b.count);

  static List<EeSlaBucket> _buckets(dynamic raw) => ((raw as List?) ?? const [])
      .map((b) => EeSlaBucket.fromJson(b as Map<String, dynamic>))
      .toList();

  factory EeSlaDashboard.fromJson(Map<String, dynamic> json) => EeSlaDashboard(
    compliance: (json['compliance'] as num?)?.toDouble(),
    byStatus: _buckets(json['byStatus']),
    byUnit: _buckets(json['byUnit']),
    byService: _buckets(json['byService']),
    bySla: _buckets(json['bySla']),
    breaches: ((json['breaches'] as List?) ?? const [])
        .map((b) => EeSlaBreach.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}
