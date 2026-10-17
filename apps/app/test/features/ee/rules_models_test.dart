import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/data/rules_models.dart';

/// EE-308 — the rule models lose nothing, and a PATCH carries only what moved.
///
/// The round trips exist for LESSONS `ee-ui`: a client model that drops a
/// field deletes it on the next save. The `changesFrom` cases exist for the
/// routing door's guard: ANY body carrying `actionPriority` asks for
/// `tickets.override_priority`, so an unchanged priority must not travel.
void main() {
  final serverRule = <String, dynamic>{
    'id': 'R1',
    'name': 'Acil',
    'trigger': 'ticket_idle',
    'action': 'assign',
    'serviceId': 'S1',
    'targetServiceId': 'S2',
    'priority': 'urgent',
    'subjectTemplate': '{{ticketRef}} bekliyor',
    'bodyTemplate': 'Gövde',
    'enabled': false,
    'conditions': {'priority': 'high', 'source': 'email', 'unitId': null},
    'actionUserId': 'U1',
    'actionAssignStrategy': 'least_loaded',
    'actionPriority': 'low',
    'actionWebhookId': 'W1',
    'actionEmailTo': 'a@b.example.com',
    'actionTagId': 'G1',
    'idleDays': 4,
    'dailyCap': 7,
    'pausedAt': '2026-10-17T08:00:00.000Z',
    'pauseReason': 'Reached 7 runs',
    'position': 3,
    'createdAt': '2026-10-01T08:00:00.000Z',
    'lastFiredAt': '2026-10-16T08:00:00.000Z',
    'lastFailedAt': '2026-10-17T07:00:00.000Z',
    'lastError': 'could not assign',
  };

  test('an automation rule round-trips every field the server sends', () {
    final rule = EeAutomationRule.fromJson(serverRule);
    expect(rule.toJson(), serverRule);
    expect(rule.paused, isTrue);
    expect(rule.failingNow, isTrue);
  });

  test('a failure older than the last success is not "failing"', () {
    final rule = EeAutomationRule.fromJson({
      ...serverRule,
      'lastFailedAt': '2026-10-01T00:00:00.000Z',
    });
    expect(rule.failingNow, isFalse);
  });

  test('changesFrom: nothing for an unchanged rule, only the moved keys, '
      'null for a cleared value', () {
    final before = EeAutomationRule.fromJson(serverRule);
    final same = EeAutomationRule.fromJson(serverRule);
    expect(same.changesFrom(before), isEmpty);

    final after = EeAutomationRule.fromJson({
      ...serverRule,
      'name': 'Çok acil',
      'conditions': {'priority': null, 'source': 'email', 'unitId': null},
    });
    expect(after.changesFrom(before), {
      'name': 'Çok acil',
      'condPriority': null,
    });
  });

  test('a create leaves unset values to the server', () {
    const rule = EeAutomationRule(
      name: 'Yeni',
      trigger: 'ticket_created',
      action: 'set_priority',
      actionPriority: 'urgent',
      subjectTemplate: 'Yeni',
    );
    final body = rule.changesFrom(null);
    expect(body.containsKey('actionUserId'), isFalse);
    expect(body, containsPair('actionPriority', 'urgent'));
    expect(body, containsPair('trigger', 'ticket_created'));
  });

  final serverRouting = <String, dynamic>{
    'id': 'C1',
    'name': 'Elektrik',
    'enabled': true,
    'condSource': 'email',
    'condServiceId': 'S1',
    'condKeywords': ['kablo', 'priz'],
    'condFrom': '@fabrika.example.com',
    'actionServiceId': 'S2',
    'actionUnitId': 'N1',
    'actionPriority': 'urgent',
    'actionTagId': 'G1',
    'position': 4,
    'createdAt': '2026-10-01T08:00:00.000Z',
    'updatedAt': '2026-10-02T08:00:00.000Z',
  };

  test('a routing rule round-trips every field the server sends', () {
    expect(
      EeClassificationRule.fromJson(serverRouting).toJson(),
      serverRouting,
    );
  });

  test('a routing PATCH omits an unchanged priority', () {
    final before = EeClassificationRule.fromJson(serverRouting);
    final renamed = EeClassificationRule.fromJson({
      ...serverRouting,
      'name': 'Elektrik arızası',
    });
    final body = renamed.changesFrom(before);
    expect(body, {'name': 'Elektrik arızası'});
    expect(body.containsKey('actionPriority'), isFalse);

    final sameWords = EeClassificationRule.fromJson({
      ...serverRouting,
      'condKeywords': ['kablo', 'priz'],
    });
    expect(sameWords.changesFrom(before), isEmpty);
  });

  test('options and a test result parse what the server sends', () {
    final o = EeRuleOptions.fromJson({
      'triggers': [
        {
          'id': 'health_down',
          'conditions': ['service'],
          'actions': ['open_ticket', 'open_task'],
          'needsIdleDays': false,
          'aboutRequest': false,
          'templateKeys': ['checkName'],
        },
      ],
      'assignStrategies': ['user'],
      'priorities': ['low'],
      'sources': ['email'],
      'classification': {
        'sources': ['email'],
        'maxKeywords': 20,
        'maxKeywordLength': 60,
      },
      'services': [
        {'id': 'S1', 'name': 'Hat'},
      ],
      'units': [],
      'members': [
        {'userId': 'U1', 'name': 'Ayşe'},
      ],
      'webhooks': [
        {'id': 'W1', 'name': 'hooks.example.com', 'enabled': false},
      ],
      'tags': [],
    });
    expect(o.trigger('health_down')!.aboutRequest, isFalse);
    expect(EeRuleOptions.nameIn(o.members, 'U1'), 'Ayşe');
    expect(o.webhooks.single.enabled, isFalse);

    final r = EeRuleTestResult.fromJson({
      'ticket': {'ref': '#7', 'number': 7},
      'matches': true,
      'fires': false,
      'checks': [
        {
          'key': 'daily_cap',
          'group': 'state',
          'pass': false,
          'expected': '1',
          'actual': '1',
        },
      ],
      'action': {
        'kind': 'set_priority',
        'outcome': 'no_change',
        'reason': null,
        'detail': {'from': 'high', 'to': 'high'},
      },
    });
    expect(r.ticketRef, '#7');
    expect(r.checks.single.pass, isFalse);
    expect(r.action.detail['to'], 'high');
  });
}
