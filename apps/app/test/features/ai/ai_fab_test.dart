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
import '../../support/fake_stt.dart';
import '../../support/sync_overrides.dart';

/// OPH-223 — the AI FAB is present when AI is enabled, sits alongside the
/// create FAB, and a tap opens the bubble in text/mic mode.
Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(stt: FakeSttController()),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  testWidgets('the AI FAB shows next to the create FAB on Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-fab')), findsOneWidget);
    // The create FAB is still there, alongside the AI FAB.
    expect(
      find.widgetWithIcon(FloatingActionButton, Icons.add),
      findsOneWidget,
    );
  });

  testWidgets('no AI FAB when AI is disabled on the server', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..aiEnabled = false;
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-fab')), findsNothing);
  });

  testWidgets('a tap opens the bubble in composing mode', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    // The bubble's text input is up (composing / text+mic mode).
    expect(find.byKey(const Key('ai-input')), findsOneWidget);
  });
}
