import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/rules_models.dart';
import 'package:alliswell/src/features/ee/ui/rules_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart' show eeRuleRoutes;
import 'package:go_router/go_router.dart';
import 'package:alliswell/src/theme/theme.dart';

import 'support/rules_fixtures.dart';

/// EE-308 — the rules list: order, state in words, and both reorder doors.
late FakeRulesApi _api;

Future<void> _pump(
  WidgetTester tester, {
  FakeRulesApi? api,
  Brightness brightness = Brightness.light,
  int tab = 0,
}) async {
  _api = api ?? FakeRulesApi();
  tester.view.physicalSize = const Size(900, 3000);
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
        home: EeRulesScreen(initialTab: tab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(Key(k));

Future<void> _menu(WidgetTester tester, String id, String item) async {
  await tester.tap(_key('rule-menu-$id'));
  await tester.pumpAndSettle();
  await tester.tap(_key('rule-$item-$id'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets(
    'rows come in server order, with the sentence and the explainer',
    (tester) async {
      await _pump(tester);
      expect(
        find.text('Every matching rule runs, top to bottom.'),
        findsOneWidget,
      );
      final names = [
        for (final r in automationFixture())
          tester.getTopLeft(_key('rule-name-${r.id}')).dy,
      ];
      expect(names, [...names]..sort());
      expect(
        tester.widget<Text>(_key('rule-sentence-R1')).data,
        'Request created · Assign: Whoever is on call · Conditions: 1',
      );
      expect(
        tester.widget<Text>(_key('rule-sentence-R4')).data,
        'Comment added · Add a tag: garanti',
      );
    },
  );

  testWidgets('a paused rule says why, and Resume patches enabled', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.text('Paused: Reached 5 runs on one request in 24 hours.'),
      findsOneWidget,
    );
    await tester.tap(_key('rule-resume-R2'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['patch R2']);
    expect(_api.bodies.single, {'enabled': true});
  });

  testWidgets('last ran / never ran / a failure newer than the last success', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Last ran 2 h ago'), findsOneWidget);
    expect(
      find.text('Last run failed: the mail relay refused the address'),
      findsOneWidget,
    );
    // R4 and R5 never ran.
    expect(find.text('Never ran'), findsNWidgets(2));
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('the switch patches enabled', (tester) async {
    await _pump(tester);
    await tester.tap(_key('rule-switch-R4'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['patch R4']);
    expect(_api.bodies.single, {'enabled': true});
  });

  testWidgets('Move down sends the whole new order; Move up too', (
    tester,
  ) async {
    await _pump(tester);
    await _menu(tester, 'R1', 'down');
    expect(_api.calls.last, 'reorder R2,R1,R3,R4,R5');
    await _menu(tester, 'R5', 'up');
    // Optimistic: the first move stands, so this one builds on it.
    expect(_api.calls.last, 'reorder R2,R1,R3,R5,R4');
  });

  testWidgets('a stale order is said, and the list is re-read', (tester) async {
    final api = FakeRulesApi()
      ..refuse = apiError('SLA_RULE_ORDER_STALE', status: 409);
    await _pump(tester, api: api);
    await _menu(tester, 'R1', 'down');
    expect(
      find.text(
        'The rules changed while you were looking. The list was reloaded; try again.',
      ),
      findsOneWidget,
    );
    // Re-read: the server's order is back.
    expect(
      tester.getTopLeft(_key('rule-name-R1')).dy,
      lessThan(tester.getTopLeft(_key('rule-name-R2')).dy),
    );
  });

  testWidgets('Duplicate calls the server; Delete asks first', (tester) async {
    await _pump(tester);
    await _menu(tester, 'R3', 'duplicate');
    expect(_api.calls, ['duplicate R3']);
    expect(
      find.text('A copy was added at the bottom, switched off.'),
      findsOneWidget,
    );

    await _menu(tester, 'R3', 'delete');
    expect(find.text('Delete this rule?'), findsOneWidget);
    expect(_api.calls, ['duplicate R3']);
    await tester.tap(_key('confirm-delete'));
    await tester.pumpAndSettle();
    expect(_api.calls, ['duplicate R3', 'delete R3']);
  });

  testWidgets('empty', (tester) async {
    await _pump(tester, api: FakeRulesApi(automation: const []));
    expect(_key('rules-automation-empty'), findsOneWidget);
  });

  testWidgets('unavailable (403/404 → null)', (tester) async {
    await _pump(tester, api: FakeRulesApi()..automation = null);
    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('the Routing tab: first match explainer, rows, routing calls', (
    tester,
  ) async {
    await _pump(tester, tab: 1);
    expect(
      find.text('The first matching rule decides where a new request goes.'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(_key('rule-sentence-C1')).data,
      'kablo, priz, sigorta… » Elektrik arızası, Bakım',
    );
    // No ledger, no "last ran".
    expect(find.text('Never ran'), findsNothing);
    await _menu(tester, 'C1', 'down');
    expect(_api.calls.last, 'reorderRouting C2,C1,C3');
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow and 44 px targets (${brightness.name})', (
      tester,
    ) async {
      await _pump(tester, brightness: brightness);
      expect(tester.takeException(), isNull);
      for (final k in ['rule-handle-R1', 'rule-switch-R1', 'rule-menu-R1']) {
        final size = tester.getSize(_key(k));
        expect(size.height, greaterThanOrEqualTo(44), reason: k);
        expect(size.width, greaterThanOrEqualTo(44), reason: k);
      }
    });
  }

  test('route order: each `new` comes before its `:ruleId`', () {
    final paths = [for (final r in eeRuleRoutes()) (r as GoRoute).path];
    expect(paths, [
      '/settings/team/rules',
      '/settings/team/rules/automation/new',
      '/settings/team/rules/automation/:ruleId',
      '/settings/team/rules/routing/new',
      '/settings/team/rules/routing/:ruleId',
    ]);
  });

  test('fixture rules are well formed', () {
    expect(automationFixture().where((r) => r.paused), hasLength(1));
    expect(
      automationFixture().where((EeAutomationRule r) => r.failingNow),
      hasLength(1),
    );
  });
}
