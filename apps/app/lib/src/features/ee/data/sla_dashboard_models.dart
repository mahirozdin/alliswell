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
    this.number,
    this.slaDueAt,
    this.breachedAt,
  });

  final String id;

  /// UI-AUDIT #53 (EE-303): two requests with one subject are told apart by
  /// their number, as everywhere else. Null from an older server.
  final int? number;
  final String subject;
  final String priority;
  final String status;
  final DateTime? slaDueAt;

  /// When the promise broke — the order the server lists them in.
  final DateTime? breachedAt;

  factory EeSlaBreach.fromJson(Map<String, dynamic> json) => EeSlaBreach(
    id: json['id'] as String,
    number: (json['number'] as num?)?.toInt(),
    subject: json['subject'] as String,
    priority: json['priority'] as String,
    status: json['status'] as String,
    slaDueAt: json['slaDueAt'] == null
        ? null
        : DateTime.parse(json['slaDueAt'] as String).toLocal(),
    breachedAt: json['breachedAt'] == null
        ? null
        : DateTime.parse(json['breachedAt'] as String).toLocal(),
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
    int? judged,
    this.hasDefaultPolicy,
    this.byStatus = const [],
    this.byUnit = const [],
    this.byService = const [],
    this.bySla = const [],
    this.breaches = const [],
    // A public `judged` getter falls back to `bySla`, so the stored value
    // stays private — and a private named parameter is not portable yet.
    // ignore: prefer_initializing_formals
  }) : _judged = judged;

  final double? compliance;

  final int? _judged;

  /// UI-AUDIT #22 (EE-303): false = the team has no default policy, so new
  /// requests get no SLA at all. Null from an older server, which is not
  /// a claim either way — the board then says nothing about it.
  final bool? hasDefaultPolicy;
  final List<EeSlaBucket> byStatus;
  final List<EeSlaBucket> byUnit;
  final List<EeSlaBucket> byService;
  final List<EeSlaBucket> bySla;
  final List<EeSlaBreach> breaches;

  int get total => byStatus.fold(0, (n, b) => n + b.count);

  /// How many requests `compliance` was computed over (UI-AUDIT #52): kept
  /// plus broken. The byStatus total also counts requests nobody promised
  /// anything about, which made "40 % of 199" a sum nobody could check. An
  /// older server does not send it, so it is summed here from `bySla`.
  int get judged => _judged ?? (slaCount('met') + slaCount('breached'));

  /// One `bySla` bucket's count — 0 when the bucket is absent.
  int slaCount(String key) {
    for (final b in bySla) {
      if (b.key == key) return b.count;
    }
    return 0;
  }

  static List<EeSlaBucket> _buckets(dynamic raw) => ((raw as List?) ?? const [])
      .map((b) => EeSlaBucket.fromJson(b as Map<String, dynamic>))
      .toList();

  factory EeSlaDashboard.fromJson(Map<String, dynamic> json) => EeSlaDashboard(
    compliance: (json['compliance'] as num?)?.toDouble(),
    judged: (json['judged'] as num?)?.toInt(),
    hasDefaultPolicy: json['hasDefaultPolicy'] as bool?,
    byStatus: _buckets(json['byStatus']),
    byUnit: _buckets(json['byUnit']),
    byService: _buckets(json['byService']),
    bySla: _buckets(json['bySla']),
    breaches: ((json['breaches'] as List?) ?? const [])
        .map((b) => EeSlaBreach.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}
