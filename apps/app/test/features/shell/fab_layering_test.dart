import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  // OPH-101: on phones the shell's glass NavigationBar (extendBody: true) was
  // painted over each section's nested-Scaffold FAB, so the FAB could not be
  // tapped. The FAB must sit fully above the bar AND fire its action.
  testWidgets('section FABs clear the glass bottom bar and stay tappable on phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844); // a phone → bottom bar
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = FakeApi();
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    // Narrow layout confirmed: the bottom NavigationBar is what covers the FAB.
    expect(find.byType(NavigationBar), findsOneWidget);
    Rect fabRect() => tester.getRect(find.byType(FloatingActionButton));
    Rect navRect() => tester.getRect(find.byType(NavigationBar));

    // The shell renders exactly one FAB (for the current section).
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Home: above the bar, and tapping opens the create sheet.
    expect(
      fabRect().overlaps(navRect()),
      isFalse,
      reason: 'Home FAB overlaps the glass bar',
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-sheet-title')), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const Key('task-sheet-title'))),
    ).pop();
    await tester.pumpAndSettle();

    // Projects: above the bar, tap opens the project sheet.
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(
      fabRect().overlaps(navRect()),
      isFalse,
      reason: 'Projects FAB overlaps the glass bar',
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Create project'), findsOneWidget);
    Navigator.of(tester.element(find.text('Create project'))).pop();
    await tester.pumpAndSettle();

    // Notes: above the bar, tap opens the note editor.
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    expect(
      fabRect().overlaps(navRect()),
      isFalse,
      reason: 'Notes FAB overlaps the glass bar',
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-title')), findsOneWidget);
  });
}
