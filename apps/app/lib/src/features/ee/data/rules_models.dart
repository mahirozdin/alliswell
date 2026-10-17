/// EE-308 — automation rules and routing rules, as the admin screen edits them.
///
/// Every field the server sends is kept, and `toBody` writes every field it
/// accepts back: a client model that drops a field deletes it on save (LESSONS
/// `ee-ui`). `changesFrom` is what a PATCH carries — only the keys that moved,
/// with an explicit null for a cleared value — so an unchanged routing
/// priority never trips the `tickets.override_priority` guard, and a save that
/// changes nothing sends nothing.
library;

import 'package:flutter/foundation.dart';

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _str(Object? v) => v is String ? v : null;
int? _int(Object? v) => v is num ? v.toInt() : null;
List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().toList() : const <String>[];

/// The keys whose change makes a PATCH, compared as the server compares them.
Map<String, dynamic> _diff(
  Map<String, dynamic> after,
  Map<String, dynamic>? before,
) {
  if (before == null) {
    // A create: nulls are "not set", and the server's defaults apply.
    return {
      for (final e in after.entries)
        if (e.value != null) e.key: e.value,
    };
  }
  final out = <String, dynamic>{};
  for (final e in after.entries) {
    final was = before[e.key];
    final same = e.value is List && was is List
        ? listEquals(e.value as List, was)
        : e.value == was;
    if (!same) out[e.key] = e.value;
  }
  return out;
}

/// One automation rule (EE-179/EE-308).
@immutable
class EeAutomationRule {
  const EeAutomationRule({
    this.id = '',
    required this.name,
    required this.trigger,
    required this.action,
    this.serviceId,
    this.targetServiceId,
    this.priority = 'high',
    this.subjectTemplate = '',
    this.bodyTemplate,
    this.enabled = true,
    this.condPriority,
    this.condSource,
    this.condUnitId,
    this.actionUserId,
    this.actionAssignStrategy = 'user',
    this.actionPriority,
    this.actionWebhookId,
    this.actionEmailTo,
    this.actionTagId,
    this.idleDays,
    this.dailyCap = 0,
    this.pausedAt,
    this.pauseReason,
    this.position = 0,
    this.createdAt,
    this.lastFiredAt,
    this.lastFailedAt,
    this.lastError,
  });

  final String id;
  final String name;
  final String trigger;
  final String action;
  final String? serviceId;
  final String? targetServiceId;
  final String priority;
  final String subjectTemplate;
  final String? bodyTemplate;
  final bool enabled;
  final String? condPriority;
  final String? condSource;
  final String? condUnitId;
  final String? actionUserId;
  final String actionAssignStrategy;
  final String? actionPriority;
  final String? actionWebhookId;
  final String? actionEmailTo;
  final String? actionTagId;
  final int? idleDays;
  final int dailyCap;
  final DateTime? pausedAt;
  final String? pauseReason;
  final int position;
  final DateTime? createdAt;
  final DateTime? lastFiredAt;
  final DateTime? lastFailedAt;
  final String? lastError;

  factory EeAutomationRule.fromJson(Map<String, dynamic> j) {
    final cond = (j['conditions'] as Map?)?.cast<String, dynamic>() ?? const {};
    return EeAutomationRule(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      trigger: j['trigger'] as String? ?? '',
      action: j['action'] as String? ?? '',
      serviceId: _str(j['serviceId']),
      targetServiceId: _str(j['targetServiceId']),
      priority: j['priority'] as String? ?? 'high',
      subjectTemplate: j['subjectTemplate'] as String? ?? '',
      bodyTemplate: _str(j['bodyTemplate']),
      enabled: j['enabled'] as bool? ?? true,
      condPriority: _str(cond['priority']),
      condSource: _str(cond['source']),
      condUnitId: _str(cond['unitId']),
      actionUserId: _str(j['actionUserId']),
      actionAssignStrategy: j['actionAssignStrategy'] as String? ?? 'user',
      actionPriority: _str(j['actionPriority']),
      actionWebhookId: _str(j['actionWebhookId']),
      actionEmailTo: _str(j['actionEmailTo']),
      actionTagId: _str(j['actionTagId']),
      idleDays: _int(j['idleDays']),
      dailyCap: _int(j['dailyCap']) ?? 0,
      pausedAt: _date(j['pausedAt']),
      pauseReason: _str(j['pauseReason']),
      position: _int(j['position']) ?? 0,
      createdAt: _date(j['createdAt']),
      lastFiredAt: _date(j['lastFiredAt']),
      lastFailedAt: _date(j['lastFailedAt']),
      lastError: _str(j['lastError']),
    );
  }

  /// The response shape, so a fixture round-trips through [fromJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trigger': trigger,
    'action': action,
    'serviceId': serviceId,
    'targetServiceId': targetServiceId,
    'priority': priority,
    'subjectTemplate': subjectTemplate,
    'bodyTemplate': bodyTemplate,
    'enabled': enabled,
    'conditions': {
      'priority': condPriority,
      'source': condSource,
      'unitId': condUnitId,
    },
    'actionUserId': actionUserId,
    'actionAssignStrategy': actionAssignStrategy,
    'actionPriority': actionPriority,
    'actionWebhookId': actionWebhookId,
    'actionEmailTo': actionEmailTo,
    'actionTagId': actionTagId,
    'idleDays': idleDays,
    'dailyCap': dailyCap,
    'pausedAt': pausedAt?.toUtc().toIso8601String(),
    'pauseReason': pauseReason,
    'position': position,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'lastFiredAt': lastFiredAt?.toUtc().toIso8601String(),
    'lastFailedAt': lastFailedAt?.toUtc().toIso8601String(),
    'lastError': lastError,
  };

  /// Every field the write doors accept, under their wire names.
  Map<String, dynamic> toBody() => {
    'name': name,
    'trigger': trigger,
    'action': action,
    'serviceId': serviceId,
    'targetServiceId': targetServiceId,
    'priority': priority,
    'subjectTemplate': subjectTemplate,
    'bodyTemplate': bodyTemplate,
    'enabled': enabled,
    'condPriority': condPriority,
    'condSource': condSource,
    'condUnitId': condUnitId,
    'actionUserId': actionUserId,
    'actionAssignStrategy': actionAssignStrategy,
    'actionPriority': actionPriority,
    'actionWebhookId': actionWebhookId,
    'actionEmailTo': actionEmailTo,
    'actionTagId': actionTagId,
    'idleDays': idleDays,
    'dailyCap': dailyCap,
  };

  /// A create's body (no [before]) or a PATCH's: only what moved.
  Map<String, dynamic> changesFrom(EeAutomationRule? before) =>
      _diff(toBody(), before?.toBody());

  bool get paused => pausedAt != null;

  /// A failure is news only when it is newer than the last success.
  bool get failingNow =>
      lastFailedAt != null &&
      (lastFiredAt == null || lastFailedAt!.isAfter(lastFiredAt!));

  /// The condition fields, by the condition keys the server's vocabulary uses.
  Map<String, String?> get conditions => {
    'service': serviceId,
    'priority': condPriority,
    'source': condSource,
    'unit': condUnitId,
  };
}

/// One trigger's vocabulary — what the engine can see and do for it.
@immutable
class EeTriggerSpec {
  const EeTriggerSpec({
    required this.id,
    this.conditions = const [],
    this.actions = const [],
    this.needsIdleDays = false,
    this.aboutRequest = true,
    this.templateKeys = const [],
  });

  final String id;
  final List<String> conditions;
  final List<String> actions;
  final bool needsIdleDays;
  final bool aboutRequest;
  final List<String> templateKeys;

  factory EeTriggerSpec.fromJson(Map<String, dynamic> j) => EeTriggerSpec(
    id: j['id'] as String? ?? '',
    conditions: _strings(j['conditions']),
    actions: _strings(j['actions']),
    needsIdleDays: j['needsIdleDays'] as bool? ?? false,
    aboutRequest: j['aboutRequest'] as bool? ?? true,
    templateKeys: _strings(j['templateKeys']),
  );
}

/// An id and the name a person reads.
@immutable
class EeNamedOption {
  const EeNamedOption({required this.id, required this.name, this.enabled});

  final String id;
  final String name;

  /// Webhooks only: a paused endpoint is offered but marked.
  final bool? enabled;
}

/// What the rule editors may offer (`GET /team/sla/rules/options`).
@immutable
class EeRuleOptions {
  const EeRuleOptions({
    this.triggers = const [],
    this.assignStrategies = const [
      'user',
      'round_robin',
      'least_loaded',
      'on_call',
    ],
    this.priorities = const ['low', 'normal', 'high', 'urgent'],
    this.sources = const [],
    this.classificationSources = const ['internal', 'public', 'email'],
    this.maxKeywords = 20,
    this.maxKeywordLength = 60,
    this.services = const [],
    this.units = const [],
    this.members = const [],
    this.webhooks = const [],
    this.tags = const [],
  });

  final List<EeTriggerSpec> triggers;
  final List<String> assignStrategies;
  final List<String> priorities;
  final List<String> sources;
  final List<String> classificationSources;
  final int maxKeywords;
  final int maxKeywordLength;
  final List<EeNamedOption> services;
  final List<EeNamedOption> units;
  final List<EeNamedOption> members;
  final List<EeNamedOption> webhooks;
  final List<EeNamedOption> tags;

  factory EeRuleOptions.fromJson(Map<String, dynamic> j) {
    List<EeNamedOption> named(Object? v, {String idKey = 'id'}) => v is List
        ? v
              .whereType<Map>()
              .map(
                (m) => EeNamedOption(
                  id: m[idKey] as String? ?? '',
                  name: m['name'] as String? ?? '',
                  enabled: m['enabled'] as bool?,
                ),
              )
              .toList()
        : const [];
    final cls = (j['classification'] as Map?)?.cast<String, dynamic>() ?? {};
    return EeRuleOptions(
      triggers: (j['triggers'] as List? ?? const [])
          .whereType<Map>()
          .map((t) => EeTriggerSpec.fromJson(t.cast<String, dynamic>()))
          .toList(),
      assignStrategies: _strings(j['assignStrategies']),
      priorities: _strings(j['priorities']),
      sources: _strings(j['sources']),
      classificationSources: _strings(cls['sources']),
      maxKeywords: _int(cls['maxKeywords']) ?? 20,
      maxKeywordLength: _int(cls['maxKeywordLength']) ?? 60,
      services: named(j['services']),
      units: named(j['units']),
      members: named(j['members'], idKey: 'userId'),
      webhooks: named(j['webhooks']),
      tags: named(j['tags']),
    );
  }

  EeTriggerSpec? trigger(String id) {
    for (final t in triggers) {
      if (t.id == id) return t;
    }
    return null;
  }

  static String? nameIn(List<EeNamedOption> list, String? id) {
    if (id == null) return null;
    for (final o in list) {
      if (o.id == id) return o.name;
    }
    return null;
  }
}

/// One line of a test: what a condition expected and what it found.
@immutable
class EeRuleCheck {
  const EeRuleCheck({
    required this.key,
    required this.pass,
    this.group = 'match',
    this.expected,
    this.actual,
  });

  final String key;
  final String group;
  final bool pass;
  final String? expected;
  final String? actual;

  factory EeRuleCheck.fromJson(Map<String, dynamic> j) => EeRuleCheck(
    key: j['key'] as String? ?? '',
    group: j['group'] as String? ?? 'match',
    pass: j['pass'] as bool? ?? false,
    expected: _str(j['expected']),
    actual: _str(j['actual']),
  );
}

/// What the action WOULD do, never done.
@immutable
class EeRuleActionPreview {
  const EeRuleActionPreview({
    required this.kind,
    required this.outcome,
    this.reason,
    this.detail = const {},
  });

  final String kind;

  /// `would_run`, `would_fail` or `no_change`.
  final String outcome;
  final String? reason;
  final Map<String, String?> detail;

  factory EeRuleActionPreview.fromJson(Map<String, dynamic> j) =>
      EeRuleActionPreview(
        kind: j['kind'] as String? ?? '',
        outcome: j['outcome'] as String? ?? 'would_fail',
        reason: _str(j['reason']),
        detail: ((j['detail'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, _str(v)),
        ),
      );
}

/// `POST /team/sla/rules/test`.
@immutable
class EeRuleTestResult {
  const EeRuleTestResult({
    required this.ticketRef,
    required this.ticketNumber,
    required this.matches,
    required this.fires,
    this.checks = const [],
    required this.action,
  });

  final String ticketRef;
  final int ticketNumber;
  final bool matches;
  final bool fires;
  final List<EeRuleCheck> checks;
  final EeRuleActionPreview action;

  factory EeRuleTestResult.fromJson(Map<String, dynamic> j) {
    final ticket = (j['ticket'] as Map?)?.cast<String, dynamic>() ?? {};
    return EeRuleTestResult(
      ticketRef: ticket['ref'] as String? ?? '',
      ticketNumber: _int(ticket['number']) ?? 0,
      matches: j['matches'] as bool? ?? false,
      fires: j['fires'] as bool? ?? false,
      checks: (j['checks'] as List? ?? const [])
          .whereType<Map>()
          .map((c) => EeRuleCheck.fromJson(c.cast<String, dynamic>()))
          .toList(),
      action: EeRuleActionPreview.fromJson(
        (j['action'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// One routing (classification) rule (EE-202). First match wins.
@immutable
class EeClassificationRule {
  const EeClassificationRule({
    this.id = '',
    required this.name,
    this.position = 0,
    this.enabled = true,
    this.condSource,
    this.condServiceId,
    this.condKeywords = const [],
    this.condFrom,
    this.actionServiceId,
    this.actionUnitId,
    this.actionPriority,
    this.actionTagId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int position;
  final bool enabled;
  final String? condSource;
  final String? condServiceId;
  final List<String> condKeywords;
  final String? condFrom;
  final String? actionServiceId;
  final String? actionUnitId;
  final String? actionPriority;
  final String? actionTagId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory EeClassificationRule.fromJson(Map<String, dynamic> j) =>
      EeClassificationRule(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        position: _int(j['position']) ?? 0,
        enabled: j['enabled'] as bool? ?? true,
        condSource: _str(j['condSource']),
        condServiceId: _str(j['condServiceId']),
        condKeywords: _strings(j['condKeywords']),
        condFrom: _str(j['condFrom']),
        actionServiceId: _str(j['actionServiceId']),
        actionUnitId: _str(j['actionUnitId']),
        actionPriority: _str(j['actionPriority']),
        actionTagId: _str(j['actionTagId']),
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    ...toBody(),
    'position': position,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  /// What the write doors accept. `position` is left to the order door.
  Map<String, dynamic> toBody() => {
    'name': name,
    'enabled': enabled,
    'condSource': condSource,
    'condServiceId': condServiceId,
    'condKeywords': condKeywords,
    'condFrom': condFrom,
    'actionServiceId': actionServiceId,
    'actionUnitId': actionUnitId,
    'actionPriority': actionPriority,
    'actionTagId': actionTagId,
  };

  Map<String, dynamic> changesFrom(EeClassificationRule? before) =>
      _diff(toBody(), before?.toBody());

  bool get acts =>
      actionServiceId != null ||
      actionUnitId != null ||
      actionPriority != null ||
      actionTagId != null;
}

/// A request a dry run looked at.
@immutable
class EeDryRunHit {
  const EeDryRunHit({
    required this.ticketId,
    this.number,
    this.subject = '',
    this.byRuleName,
  });

  final String ticketId;
  final int? number;
  final String subject;
  final String? byRuleName;

  factory EeDryRunHit.fromJson(Map<String, dynamic> j) => EeDryRunHit(
    ticketId: j['ticketId'] as String? ?? '',
    number: _int(j['number']),
    subject: j['subject'] as String? ?? '',
    byRuleName: _str(j['byRuleName']),
  );
}

/// `POST /team/classification/dry-run` — the last hundred requests.
@immutable
class EeClassificationDryRun {
  const EeClassificationDryRun({
    this.sampled = 0,
    this.wouldApply = const {},
    this.matched = const [],
    this.shadowed = const [],
    this.unmatched = 0,
  });

  final int sampled;
  final Map<String, String?> wouldApply;
  final List<EeDryRunHit> matched;
  final List<EeDryRunHit> shadowed;
  final int unmatched;

  factory EeClassificationDryRun.fromJson(Map<String, dynamic> j) {
    List<EeDryRunHit> hits(Object? v) => (v as List? ?? const [])
        .whereType<Map>()
        .map((m) => EeDryRunHit.fromJson(m.cast<String, dynamic>()))
        .toList();
    return EeClassificationDryRun(
      sampled: _int(j['sampled']) ?? 0,
      wouldApply: ((j['wouldApply'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k as String, _str(v)),
      ),
      matched: hits(j['matched']),
      shadowed: hits(j['shadowed']),
      unmatched: _int(j['unmatched']) ?? 0,
    );
  }
}
