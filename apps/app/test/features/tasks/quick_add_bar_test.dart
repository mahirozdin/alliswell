import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/features/tasks/ui/quick_add_bar.dart';
import 'package:alliswell/src/theme/theme.dart';

/// The bar on its own: what typing does to focus and to dismissed chips.

Future<void> _pumpBar(WidgetTester tester) async {
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
            onAdd: (_) async {},
            parseProject: false,
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
}
