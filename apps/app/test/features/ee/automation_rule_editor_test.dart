import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/rules_models.dart';
import 'package:alliswell/src/features/ee/ui/automation_rule_editor.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import 'support/rules_fixtures.dart';

/// EE-308 — the automation editor offers exactly what the engine can do,
/// refuses inline before sending, and sends only what moved.
late FakeRulesApi _api;

Future<void> _pump(
  WidgetTester tester, {
  String? ruleId,
  FakeRulesApi? api,
  Brightness brightness = Brightness.light,
}) async {
  _api = api ?? FakeRulesApi();
  tester.view.physicalSize = const Size(900, 6000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: rulesOverrides(_api),
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: EeAutomationRuleEditor(ruleId: ruleId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(Key(k));

Future<void> _pick(WidgetTester tester, String field, String? value) async {
  await tester.ensureVisible(_key(field));
  await tester.tap(_key(field));
  await tester.pumpAndSettle();
  await tester.tap(_key('rule-choice-${value ?? 'none'}'));
  await tester.pumpAndSettle();
}

Future<List<String>> _menuValues(WidgetTester tester, String field) async {
  await tester.ensureVisible(_key(field));
  await tester.tap(_key(field));
  await tester.pumpAndSettle();
  final keys = find
      .byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('rule-choice-'),
      )
      .evaluate()
      .map(
        (e) => ((e.widget as ListTile).key! as ValueKey<String>).value
            .substring('rule-choice-'.length),
      )
      .toList();
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();
  return keys;
}

Future<List<String>> _addConditionChoices(WidgetTester tester) async {
  if (_key('rule-add-condition').evaluate().isEmpty) return const [];
  await tester.ensureVisible(_key('rule-add-condition'));
  await tester.tap(_key('rule-add-condition'));
  await tester.pumpAndSettle();
  final out = [
    for (final c in ['service', 'priority', 'source', 'unit'])
      if (_key('rule-add-condition-$c').evaluate().isNotEmpty) c,
  ];
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
  return out;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets(
    'the trigger menu offers what the server offers — no sla_warned',
    (tester) async {
      await _pump(tester);
      final triggers = await _menuValues(tester, 'rule-trigger');
      expect(triggers, kTriggerOrder);
      expect(triggers, isNot(contains('sla_warned')));
    },
  );

  testWidgets('an existing sla_warned rule says it never runs, and cannot be '
      'saved until the trigger changes', (tester) async {
    final api = FakeRulesApi(
      automation: const [
        EeAutomationRule(
          id: 'L1',
          name: 'Eski uyarı',
          trigger: 'sla_warned',
          action: 'open_ticket',
          subjectTemplate: 'x',
        ),
      ],
    );
    await _pump(tester, api: api, ruleId: 'L1');
    expect(_key('rule-not-raised'), findsOneWidget);
    await tester.tap(_key('rule-save'));
    await tester.pumpAndSettle();
    expect(_api.calls, isEmpty);
    await _pick(tester, 'rule-trigger', 'ticket_created');
    expect(_key('rule-not-raised'), findsNothing);
  });

  testWidgets('Add condition offers exactly the trigger\'s conditions', (
    tester,
  ) async {
    await _pump(tester);
    expect(await _addConditionChoices(tester), [
      'service',
      'priority',
      'source',
      'unit',
    ]);
    await _pick(tester, 'rule-trigger', 'ticket_idle');
    expect(await _addConditionChoices(tester), [
      'service',
      'priority',
      'source',
    ]);
    await _pick(tester, 'rule-trigger', 'health_down');
    expect(await _addConditionChoices(tester), ['service']);
    expect(await _menuValues(tester, 'rule-action'), [
      'open_ticket',
      'open_task',
    ]);
  });

  testWidgets('switching to a monitor trigger removes the unit condition and '
      'the assign action, and SAYS so', (tester) async {
    await _pump(tester, ruleId: 'R1');
    // R1: ticket_created, priority=urgent, assign/on_call. Add a unit.
    await tester.ensureVisible(_key('rule-add-condition'));
    await tester.tap(_key('rule-add-condition'));
    await tester.pumpAndSettle();
    await tester.tap(_key('rule-add-condition-unit'));
    await tester.pumpAndSettle();
    await _pick(tester, 'rule-cond-value-unit', 'N1');
    await _pick(tester, 'rule-trigger', 'health_down');
    expect(_key('rule-cond-priority'), findsNothing);
    expect(_key('rule-cond-unit'), findsNothing);
    expect(
      find.text(
        'Removed because this trigger cannot use them: Priority, Unit '
        'The action was reset because this trigger cannot take it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('assign to a person with nobody chosen: inline, and no request', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_key('rule-name'), 'Atama');
    await _pick(tester, 'rule-action', 'assign');
    await tester.ensureVisible(_key('rule-save'));
    await tester.tap(_key('rule-save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose who gets the request'), findsOneWidget);
    expect(_api.calls, isEmpty);
  });

  testWidgets('a taken name comes back under the name field', (tester) async {
    final api = FakeRulesApi()
      ..refuse = apiError('SLA_RULE_NAME_TAKEN', status: 409);
    await _pump(tester, api: api);
    await tester.enterText(_key('rule-name'), 'Aynı');
    await _pick(tester, 'rule-action', 'set_priority');
    await _pick(tester, 'rule-action-priority', 'urgent');
    await tester.ensureVisible(_key('rule-save'));
    await tester.tap(_key('rule-save'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['create']);
    final field = tester.widget<TextField>(_key('rule-name'));
    expect(
      field.decoration?.errorText,
      'A rule with this name already exists.',
    );
  });

  testWidgets('an edit PATCHes only the keys that moved', (tester) async {
    await _pump(tester, ruleId: 'R1');
    await tester.enterText(_key('rule-name'), 'Acil talepler nöbetçiye!');
    await tester.ensureVisible(_key('rule-save'));
    await tester.tap(_key('rule-save'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['patch R1']);
    expect(_api.bodies.single, {'name': 'Acil talepler nöbetçiye!'});
  });

  testWidgets('idle days outside 1–365 are refused inline', (tester) async {
    await _pump(tester, ruleId: 'R2');
    await tester.enterText(_key('rule-idle-days'), '400');
    await tester.ensureVisible(_key('rule-save'));
    await tester.tap(_key('rule-save'));
    await tester.pumpAndSettle();
    expect(find.text('Between 1 and 365 days'), findsOneWidget);
    expect(_api.calls, isEmpty);
  });

  testWidgets('a template chip inserts {{ticketRef}} into the subject', (
    tester,
  ) async {
    await _pump(tester);
    await _pick(tester, 'rule-action', 'open_ticket');
    await tester.enterText(_key('rule-subject'), 'Talep ');
    await tester.ensureVisible(_key('rule-template-ticketRef'));
    await tester.tap(_key('rule-template-ticketRef'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_key('rule-subject')).controller!.text,
      'Talep {{ticketRef}}',
    );
  });

  testWidgets('the test card: checks with icons AND words, the action preview; '
      'an unknown number is said under the field', (tester) async {
    final api = FakeRulesApi()..testResult = kTestResult;
    await _pump(tester, api: api, ruleId: 'R1');
    await tester.ensureVisible(_key('rule-test-number'));
    await tester.enterText(_key('rule-test-number'), '1042');
    await tester.tap(_key('rule-test-run'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['test 1042']);
    expect(find.text('Would not run on #1042'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('rule-check-unit'),
        matching: find.byIcon(Icons.close),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'expected Bakım, found Yardım Masası',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Assign: Would run'), findsOneWidget);
    expect(find.text('Çağrı Öztürk'), findsOneWidget);

    api.refuse = apiError('SLA_RULE_TEST_TICKET_NOT_FOUND', status: 404);
    await tester.tap(_key('rule-test-run'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(_key('rule-test-number'));
    expect(
      field.decoration?.errorText,
      'There is no request with that number in this team.',
    );
  });

  testWidgets('a person who left reads "Unavailable (removed)", not an id', (
    tester,
  ) async {
    final api = FakeRulesApi(
      automation: const [
        EeAutomationRule(
          id: 'G1',
          name: 'Gidenin kuralı',
          trigger: 'ticket_created',
          action: 'assign',
          actionUserId: '01GONEGONEGONEGONEGONEGONE',
          subjectTemplate: 'x',
        ),
      ],
    );
    await _pump(tester, api: api, ruleId: 'G1');
    expect(find.text('Unavailable (removed)'), findsOneWidget);
    expect(find.textContaining('01GONE'), findsNothing);
  });

  testWidgets('a paused rule says why and that saving resumes it', (
    tester,
  ) async {
    await _pump(tester, ruleId: 'R2');
    expect(_key('rule-paused-banner'), findsOneWidget);
    // Saving with nothing changed still resumes it (any PATCH clears it).
    await tester.ensureVisible(_key('rule-save'));
    await tester.tap(_key('rule-save'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['patch R2']);
    expect(_api.bodies.single, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow (${brightness.name})', (tester) async {
      await _pump(tester, ruleId: 'R3', brightness: brightness);
      expect(tester.takeException(), isNull);
    });
  }
}
