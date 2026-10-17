// EE-308 — the rules screen and the automation editor, shot in both themes.
//
// Run locally with (from apps/app):
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       --dart-define=shotLocale=tr test/features/ee/rules_screenshot_test.dart
//   …and again with shotLocale=en, then `npm run shots:ee` at the root.
//
// Inert without the dart-define, like every other shot file here.
//
// WHAT THE PICTURES ARE FOR. The list carries state in words beside icons —
// paused (with the server's reason), off, a failure newer than the last
// success, "last ran", "never ran" — and the editor's test card pairs every
// ✓/✗ with a sentence. Contrast of the warning mark and the error text in
// BOTH themes is reviewed on these, not in a test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/rules_models.dart';
import 'package:alliswell/src/features/ee/ui/automation_rule_editor.dart';
import 'package:alliswell/src/features/ee/ui/rules_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/rules_fixtures.dart';
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

const _editorRule = EeAutomationRule(
  id: 'E1',
  name: 'Acil arızalar sırayla',
  trigger: 'ticket_created',
  action: 'assign',
  actionAssignStrategy: 'round_robin',
  condPriority: 'urgent',
  condUnitId: 'N1',
  subjectTemplate: 'x',
  dailyCap: 5,
);

const _editorResult = EeRuleTestResult(
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
    EeRuleCheck(key: 'paused', group: 'state', pass: true),
    EeRuleCheck(
      key: 'daily_cap',
      group: 'state',
      pass: true,
      expected: '5',
      actual: '0',
    ),
  ],
  action: EeRuleActionPreview(
    kind: 'assign',
    outcome: 'would_run',
    detail: {'userId': 'U2'},
  ),
);

/// Scrolls the editor so [key]'s card is at the top of the viewport.
Future<void> _scrollTo(WidgetTester tester, String key) async {
  await Scrollable.ensureVisible(
    tester.element(find.byKey(Key(key))),
    alignment: 0,
  );
  await tester.pumpAndSettle();
}

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('rules: automation list (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-rules-automation',
        size: const Size(900, 1500),
        overrides: rulesOverrides(FakeRulesApi()),
        screen: const EeRulesScreen(),
      );
    });

    testWidgets('rules: routing list (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-rules-routing',
        size: const Size(900, 1200),
        overrides: rulesOverrides(FakeRulesApi()),
        screen: const EeRulesScreen(initialTab: 1),
      );
    });

    testWidgets('rules: automation editor with a test (${brightness.name})', (
      tester,
    ) async {
      final api = FakeRulesApi(automation: [_editorRule])
        ..testResult = _editorResult;
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-rules-automation-editor',
        size: const Size(900, 2600),
        overrides: rulesOverrides(api),
        screen: const EeAutomationRuleEditor(ruleId: 'E1'),
        afterPump: (tester) async {
          await _scrollTo(tester, 'rule-test');
          await tester.enterText(
            find.byKey(const Key('rule-test-number')),
            '1042',
          );
          await tester.tap(find.byKey(const Key('rule-test-run')));
          await tester.pumpAndSettle();
          await _scrollTo(tester, 'rule-if');
        },
      );
    });

    testWidgets('rules: editor inline errors (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-rules-automation-editor-error',
        size: const Size(900, 1800),
        overrides: rulesOverrides(FakeRulesApi()),
        screen: const EeAutomationRuleEditor(),
        afterPump: (tester) async {
          await tester.tap(find.byKey(const Key('rule-action')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('rule-choice-assign')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('rule-save-top')));
          await tester.pumpAndSettle();
        },
      );
    });
  }
}
