import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/rules_models.dart';
import 'package:alliswell/src/features/ee/ui/routing_rule_editor.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import 'support/rules_fixtures.dart';

/// EE-308 — the routing editor: the server's limits said inline, the
/// priority claim respected, and the dry run's shadowing named.
late FakeRulesApi _api;

Future<void> _pump(
  WidgetTester tester, {
  String? ruleId,
  FakeRulesApi? api,
  bool mayOverridePriority = true,
  Brightness brightness = Brightness.light,
}) async {
  _api = api ?? FakeRulesApi();
  tester.view.physicalSize = const Size(900, 5000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: rulesOverrides(_api, mayOverridePriority: mayOverridePriority),
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: EeRoutingRuleEditor(ruleId: ruleId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(Key(k));

Future<void> _addWord(WidgetTester tester, String word) async {
  await tester.enterText(_key('routing-keyword'), word);
  await tester.tap(_key('routing-keyword-add'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(_key('routing-save'));
  await tester.tap(_key('routing-save'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('the 21st word is refused inline', (tester) async {
    await _pump(tester);
    for (var i = 0; i < 20; i++) {
      await _addWord(tester, 'w$i');
    }
    expect(find.byType(InputChip), findsNWidgets(20));
    await _addWord(tester, 'w20');
    expect(find.text('At most 20 words'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(20));
  });

  testWidgets('a 61-character word is refused inline', (tester) async {
    await _pump(tester);
    await _addWord(tester, 'x' * 61);
    expect(find.text('At most 60 characters'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('a rule that does nothing is refused before sending', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_key('routing-name'), 'Boş');
    await _addWord(tester, 'kablo');
    await _save(tester);
    expect(
      find.text('Choose at least one thing for the rule to do'),
      findsOneWidget,
    );
    expect(_api.calls, isEmpty);
  });

  testWidgets('without tickets.override_priority the priority is locked and '
      'says why', (tester) async {
    await _pump(tester, mayOverridePriority: false);
    expect(
      find.text(
        'Setting a priority needs the permission to override priorities.',
      ),
      findsOneWidget,
    );
    await tester.tap(_key('routing-priority'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('an edit leaves an unchanged priority out of the PATCH', (
    tester,
  ) async {
    // C3 carries a priority somebody else set; this admin may not set one.
    await _pump(tester, ruleId: 'C3', mayOverridePriority: false);
    await tester.enterText(_key('routing-name'), 'Acil kelimesi (yeni)');
    await _save(tester);
    expect(_api.calls, ['patchRouting C3']);
    expect(_api.bodies.single, {'name': 'Acil kelimesi (yeni)'});
  });

  testWidgets('a new rule goes last', (tester) async {
    await _pump(tester);
    await tester.enterText(_key('routing-name'), 'Yeni');
    await tester.tap(_key('routing-service'));
    await tester.pumpAndSettle();
    await tester.tap(_key('rule-choice-S1'));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(_api.calls, ['createRouting']);
    expect(_api.bodies.single['position'], 3);
    expect(_api.bodies.single['actionServiceId'], 'S1');
  });

  testWidgets('a taken name is said under the name', (tester) async {
    final api = FakeRulesApi()
      ..refuse = apiError('CLASSIFICATION_RULE_NAME_TAKEN', status: 409);
    await _pump(tester, api: api, ruleId: 'C1');
    await tester.enterText(_key('routing-name'), 'Tedarikçi e-postası');
    await _save(tester);
    expect(
      tester.widget<TextField>(_key('routing-name')).decoration?.errorText,
      'A rule with this name already exists.',
    );
  });

  testWidgets('the dry run shows matched, shadowed by name, and unmatched', (
    tester,
  ) async {
    final api = FakeRulesApi()
      ..dryRun = const EeClassificationDryRun(
        sampled: 100,
        matched: [
          EeDryRunHit(ticketId: 'T1', number: 1042, subject: 'Kablo yandı'),
        ],
        shadowed: [
          EeDryRunHit(
            ticketId: 'T2',
            number: 1043,
            subject: 'Priz çalışmıyor',
            byRuleName: 'Elektrik',
          ),
        ],
        unmatched: 98,
      );
    await _pump(tester, api: api, ruleId: 'C3');
    await tester.ensureVisible(_key('routing-try-run'));
    await tester.tap(_key('routing-try-run'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['dryRun']);
    expect(_api.bodies.single['position'], 2);
    expect(
      find.text('100 requests checked · 1 would change · 98 not touched'),
      findsOneWidget,
    );
    expect(find.text('#1042 Kablo yandı'), findsOneWidget);
    expect(
      find.textContaining('Taken by “Elektrik”', findRichText: true),
      findsOneWidget,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow (${brightness.name})', (tester) async {
      await _pump(tester, ruleId: 'C1', brightness: brightness);
      expect(tester.takeException(), isNull);
    });
  }
}
