// EE-308 — a fake rules client and the fixtures the rules tests and the
// rules screenshots share. The fake records every call so a test asserts the
// exact wire body (a PATCH carries only what moved).
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/data/rules_api.dart';
import 'package:alliswell/src/features/ee/data/rules_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/rules_providers.dart';

const kTicketSpec = ['service', 'priority', 'source', 'unit'];
const kAllActions = [
  'open_ticket',
  'open_task',
  'assign',
  'set_priority',
  'call_webhook',
  'send_email',
  'add_tag',
];
const kTicketKeys = ['ticketRef', 'subject', 'priority', 'status', 'source'];

const kOptions = EeRuleOptions(
  triggers: [
    EeTriggerSpec(
      id: 'ticket_created',
      conditions: kTicketSpec,
      actions: kAllActions,
      templateKeys: kTicketKeys,
    ),
    EeTriggerSpec(
      id: 'ticket_updated',
      conditions: kTicketSpec,
      actions: kAllActions,
      templateKeys: kTicketKeys,
    ),
    EeTriggerSpec(
      id: 'ticket_commented',
      conditions: kTicketSpec,
      actions: kAllActions,
      templateKeys: kTicketKeys,
    ),
    EeTriggerSpec(
      id: 'ticket_idle',
      conditions: ['service', 'priority', 'source'],
      actions: kAllActions,
      needsIdleDays: true,
      templateKeys: kTicketKeys,
    ),
    EeTriggerSpec(
      id: 'sla_breached',
      conditions: ['service', 'priority'],
      actions: kAllActions,
      templateKeys: ['subject', 'priority', 'kind', 'targetMinutes'],
    ),
    EeTriggerSpec(
      id: 'health_down',
      conditions: ['service'],
      actions: ['open_ticket', 'open_task'],
      aboutRequest: false,
      templateKeys: ['checkName', 'url', 'reason', 'subject'],
    ),
    EeTriggerSpec(
      id: 'health_recovered',
      conditions: ['service'],
      actions: ['open_ticket', 'open_task'],
      aboutRequest: false,
      templateKeys: ['checkName', 'url', 'subject'],
    ),
  ],
  sources: ['internal', 'public', 'health', 'sla', 'email'],
  services: [
    EeNamedOption(id: 'S1', name: 'Hat kontrol'),
    EeNamedOption(id: 'S2', name: 'Elektrik arızası'),
  ],
  units: [
    EeNamedOption(id: 'N1', name: 'Bakım'),
    EeNamedOption(id: 'N2', name: 'Yardım Masası'),
  ],
  members: [
    EeNamedOption(id: 'U1', name: 'Ayşe Demir'),
    EeNamedOption(id: 'U2', name: 'Çağrı Öztürk'),
    EeNamedOption(id: 'U3', name: 'Barış Kaya'),
  ],
  webhooks: [
    EeNamedOption(id: 'W1', name: 'hooks.fabrika.example.com', enabled: true),
    EeNamedOption(id: 'W2', name: 'eski.example.com', enabled: false),
  ],
  tags: [
    EeNamedOption(id: 'G1', name: 'acil'),
    EeNamedOption(id: 'G2', name: 'garanti'),
  ],
);

final kNow = DateTime.now();

List<EeAutomationRule> automationFixture() => [
  EeAutomationRule(
    id: 'R1',
    name: 'Acil talepler nöbetçiye',
    trigger: 'ticket_created',
    action: 'assign',
    actionAssignStrategy: 'on_call',
    condPriority: 'urgent',
    subjectTemplate: 'x',
    position: 0,
    lastFiredAt: kNow.subtract(const Duration(hours: 2)),
  ),
  EeAutomationRule(
    id: 'R2',
    name: 'Bekleyen talebi yükselt',
    trigger: 'ticket_idle',
    action: 'set_priority',
    actionPriority: 'high',
    idleDays: 3,
    subjectTemplate: 'x',
    position: 1,
    pausedAt: kNow.subtract(const Duration(minutes: 30)),
    pauseReason: 'Reached 5 runs on one request in 24 hours.',
    lastFiredAt: kNow.subtract(const Duration(hours: 1)),
  ),
  EeAutomationRule(
    id: 'R3',
    name: 'SLA aşımında müdüre e-posta',
    trigger: 'sla_breached',
    action: 'send_email',
    actionEmailTo: 'mudur@fabrika.example.com',
    subjectTemplate: 'SLA aşıldı: {{subject}}',
    position: 2,
    lastFiredAt: kNow.subtract(const Duration(days: 2)),
    lastFailedAt: kNow.subtract(const Duration(hours: 5)),
    lastError: 'the mail relay refused the address',
  ),
  const EeAutomationRule(
    id: 'R4',
    name: 'Yorumda garanti etiketi',
    trigger: 'ticket_commented',
    action: 'add_tag',
    actionTagId: 'G2',
    subjectTemplate: 'x',
    enabled: false,
    position: 3,
  ),
  const EeAutomationRule(
    id: 'R5',
    name: 'Hat 3 çökünce iş aç',
    trigger: 'health_down',
    action: 'open_task',
    serviceId: 'S1',
    subjectTemplate: '{{checkName}} yanıt vermiyor',
    position: 4,
  ),
];

List<EeClassificationRule> routingFixture() => const [
  EeClassificationRule(
    id: 'C1',
    name: 'Elektrik',
    position: 0,
    condKeywords: ['kablo', 'priz', 'sigorta', 'şalter'],
    actionServiceId: 'S2',
    actionUnitId: 'N1',
  ),
  EeClassificationRule(
    id: 'C2',
    name: 'Tedarikçi e-postası',
    position: 1,
    condSource: 'email',
    condFrom: '@tedarik.example.com',
    actionTagId: 'G2',
  ),
  EeClassificationRule(
    id: 'C3',
    name: 'Acil kelimesi',
    position: 2,
    enabled: false,
    condKeywords: ['acil'],
    actionPriority: 'urgent',
  ),
];

/// Records every call; answers from in-memory lists.
class FakeRulesApi extends EeRulesApi {
  FakeRulesApi({
    List<EeAutomationRule>? automation,
    List<EeClassificationRule>? routing,
    this.opts = kOptions,
  }) : automation = automation ?? automationFixture(),
       routing = routing ?? routingFixture(),
       super(Dio());

  List<EeAutomationRule>? automation;
  List<EeClassificationRule>? routing;
  EeRuleOptions? opts;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  Object? refuse;
  EeRuleTestResult? testResult;
  EeClassificationDryRun? dryRun;

  Future<void> _maybeRefuse() async {
    if (refuse != null) throw refuse!;
  }

  @override
  Future<List<EeAutomationRule>?> loadAutomation() async => automation;

  @override
  Future<EeRuleOptions?> options() async => opts;

  @override
  Future<String> createAutomation(Map<String, dynamic> body) async {
    calls.add('create');
    bodies.add(body);
    await _maybeRefuse();
    return 'NEW';
  }

  @override
  Future<void> patchAutomation(String id, Map<String, dynamic> body) async {
    calls.add('patch $id');
    bodies.add(body);
    await _maybeRefuse();
  }

  @override
  Future<void> deleteAutomation(String id) async => calls.add('delete $id');

  @override
  Future<String> duplicateAutomation(String id) async {
    calls.add('duplicate $id');
    return 'COPY';
  }

  @override
  Future<void> reorderAutomation(List<String> ids) async {
    calls.add('reorder ${ids.join(',')}');
    await _maybeRefuse();
  }

  @override
  Future<EeRuleTestResult> testAutomation({
    String? id,
    required Map<String, dynamic> draft,
    required int ticketNumber,
  }) async {
    calls.add('test $ticketNumber');
    bodies.add(draft);
    await _maybeRefuse();
    return testResult!;
  }

  @override
  Future<List<EeClassificationRule>?> loadRouting() async => routing;

  @override
  Future<String> createRouting(Map<String, dynamic> body) async {
    calls.add('createRouting');
    bodies.add(body);
    await _maybeRefuse();
    return 'NEWR';
  }

  @override
  Future<void> patchRouting(String id, Map<String, dynamic> body) async {
    calls.add('patchRouting $id');
    bodies.add(body);
    await _maybeRefuse();
  }

  @override
  Future<void> deleteRouting(String id) async => calls.add('deleteRouting $id');

  @override
  Future<String> duplicateRouting(String id) async {
    calls.add('duplicateRouting $id');
    return 'COPYR';
  }

  @override
  Future<void> reorderRouting(List<String> ids) async {
    calls.add('reorderRouting ${ids.join(',')}');
  }

  @override
  Future<EeClassificationDryRun> dryRunRouting({
    String? id,
    required Map<String, dynamic> draft,
  }) async {
    calls.add('dryRun');
    bodies.add(draft);
    return dryRun!;
  }
}

List<Override> rulesOverrides(
  FakeRulesApi api, {
  bool mayOverridePriority = true,
}) => [
  eeRulesApiProvider.overrideWithValue(api),
  eeFeatureProvider.overrideWith((ref, name) => true),
  canProvider.overrideWith(
    (ref, id) => id == 'tickets.override_priority' ? mayOverridePriority : true,
  ),
];

ApiException apiError(String code, {int status = 400}) =>
    ApiException(code, code, statusCode: status);

const kTestResult = EeRuleTestResult(
  ticketRef: '#1042',
  ticketNumber: 1042,
  matches: false,
  fires: false,
  checks: [
    EeRuleCheck(
      key: 'priority',
      pass: true,
      expected: 'urgent',
      actual: 'urgent',
    ),
    EeRuleCheck(key: 'unit', pass: false, expected: 'N1', actual: 'N2'),
    EeRuleCheck(
      key: 'enabled',
      group: 'state',
      pass: true,
      expected: 'true',
      actual: 'true',
    ),
  ],
  action: EeRuleActionPreview(
    kind: 'assign',
    outcome: 'would_run',
    detail: {'userId': 'U2'},
  ),
);
