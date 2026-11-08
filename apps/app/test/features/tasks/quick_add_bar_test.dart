import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/features/tasks/data/quick_add_apply.dart';
import 'package:alliswell/src/features/tasks/ui/quick_add_bar.dart';
import 'package:alliswell/src/theme/theme.dart';

/// The bar on its own: what typing does to focus and to dismissed chips.

Future<void> _pumpBar(
  WidgetTester tester, {
  Future<void> Function(String text)? onParse,
  Future<void> Function(QuickAddSubmission submission)? onAdd,
  bool parseProject = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 16, 10)),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          body: QuickAddBar(
            hintText: 'Add',
            onAdd: onAdd ?? (_) async {},
            onParse: onParse,
            parseProject: parseProject,
          ),
        ),
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('OPH-384: with semantics on, the field keeps its semantics node '
      'and focus while chips appear one by one', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpBar(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final first = tester.getSemantics(find.byType(EditableText));
    final firstId = first.id;
    final firstParent = first.parent?.id;
    const text = "Yarın 9'da kira #ev";
    var maxChips = 0;
    for (var i = 1; i <= text.length; i++) {
      await _type(tester, text.substring(0, i));
      final node = tester.getSemantics(find.byType(EditableText));
      // A new node — or the same node under a new parent — is a new DOM
      // input on the web, and the browser's focus does not follow it.
      expect(node.id, firstId, reason: 'after "${text.substring(0, i)}"');
      expect(node.parent?.id, firstParent);
      expect(
        node.getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );
      final chips = find.byType(InputChip).evaluate().length;
      if (chips > maxChips) maxChips = chips;
    }
    expect(maxChips, 2, reason: 'the deadline chip, then the tag chip');
    expect(find.byKey(const Key('quick-add-token-tag-0')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('OPH-385: a dismissed chip comes back after the field is '
      'cleared by hand', (tester) async {
    await _pumpBar(tester);
    await _type(tester, 'yarın kira');
    expect(find.byKey(const Key('quick-add-token-due')), findsOneWidget);

    // ✕ keeps "yarın" as title text.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('quick-add-token-due')),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('quick-add-token-due')), findsNothing);

    // Select-all + delete, then a new line with the same word.
    await _type(tester, '');
    await _type(tester, 'yarın süt');
    expect(find.byKey(const Key('quick-add-token-due')), findsOneWidget);
  });

  testWidgets('OPH-385: editing a line without emptying it keeps the ✕', (
    tester,
  ) async {
    await _pumpBar(tester);
    await _type(tester, 'yarın kira');
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('quick-add-token-due')),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _type(tester, 'yarın kir');
    await _type(tester, 'yarın kira öde');
    expect(find.byKey(const Key('quick-add-token-due')), findsNothing);
  });

  // ── OPH-401 (C-06, R-11, U-30; DESIGN §47 W5) ────────────────────────────
  // The bar used to carry four controls — a decorative "+", "?", ✨ and ↑ —
  // and two of them did nothing while it was empty.

  final submit = find.byKey(const Key('quick-add-submit'));
  final parse = find.byKey(const Key('quick-add-parse'));
  final hints = find.byKey(const Key('quick-add-hints'));

  testWidgets('empty: no control on the right and no decorative "+"', (
    tester,
  ) async {
    await _pumpBar(tester, onParse: (_) async {});
    expect(submit, findsNothing);
    expect(parse, findsNothing);
    expect(find.byKey(const Key('quick-add-help')), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.help_outline), findsNothing);
  });

  testWidgets('typing brings ✨ and ↑; clearing takes them away', (
    tester,
  ) async {
    await _pumpBar(tester, onParse: (_) async {});
    await tester.tap(find.byType(TextField));
    await _type(tester, 'süt al');
    expect(submit, findsOneWidget);
    expect(parse, findsOneWidget);
    // ↑ is the primary: a 32 pt filled circle inside a 48 pt target.
    expect(tester.getSize(submit), const Size(48, 48));
    final dot = tester.widget<Container>(
      find.descendant(
        of: submit,
        matching: find.byKey(const Key('quick-add-submit-dot')),
      ),
    );
    final deco = dot.decoration! as BoxDecoration;
    expect(deco.shape, BoxShape.circle);
    expect(dot.constraints!.maxWidth, 32);
    await _type(tester, '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(submit, findsNothing);
    expect(parse, findsNothing);
  });

  testWidgets('E35 G-B review r1: a screen reader can activate ↑ — its one '
      'button node carries the tap action and adds the task', (tester) async {
    final semantics = tester.ensureSemantics();
    final added = <String>[];
    await _pumpBar(tester, onAdd: (s) async => added.add(s.raw));
    await tester.tap(find.byType(TextField));
    await _type(tester, 'süt al');
    final node = tester.getSemantics(submit);
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'VoiceOver/TalkBack activate a button through its tap action',
    );
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(added, ['süt al']);
    semantics.dispose();
  });

  testWidgets('without AI, typing brings ↑ alone', (tester) async {
    await _pumpBar(tester);
    await tester.tap(find.byType(TextField));
    await _type(tester, 'süt al');
    expect(submit, findsOneWidget);
    expect(parse, findsNothing);
  });

  testWidgets('focus shows the hint strip with "More"; it opens the sheet', (
    tester,
  ) async {
    // The project tab's bar does not read +Project, so it does not hint it;
    // Home's does (home_first_screen_test).
    await _pumpBar(tester);
    expect(hints, findsNothing, reason: 'not before the field is focused');
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 300));
    expect(hints, findsOneWidget);
    for (final example in const ['tomorrow 9am', '#home', 'p1']) {
      expect(
        find.descendant(of: hints, matching: find.text(example)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: hints, matching: find.text('+Work')),
      findsNothing,
    );
    // Once typing, the recognized chips take the row (§39 Q2).
    await _type(tester, 'yarın kira');
    expect(hints, findsNothing);
    expect(find.byKey(const Key('quick-add-help-inline')), findsOneWidget);
    await _type(tester, '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(hints, findsOneWidget);
    final more = find.byKey(const Key('quick-add-help'));
    expect(tester.getSize(more).height, greaterThanOrEqualTo(48));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-help-sheet')), findsOneWidget);
  });
}
