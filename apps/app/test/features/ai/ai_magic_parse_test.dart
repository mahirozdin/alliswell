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

/// OPH-222 — the quick-add ✨ rider runs pasted text through extraction into
/// the same confirm card, and only appears when AI is configured.
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
  testWidgets('no ✨ affordance when AI is unconfigured', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()
      ..aiEnabled = true; // AI enabled, no connection → unconfigured
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-parse')), findsNothing);
  });

  testWidgets('✨ parses text into the confirm card', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'create_tasks',
      'tasks': [
        {'title': 'Faturayı öde', 'confidence': 0.9},
        {'title': 'Raporu gönder', 'confidence': 0.8},
      ],
    };
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-add-parse')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'faturayı öde ve raporu gönder',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-parse')));
    await tester.pumpAndSettle();

    // The confirm card opened with both proposed tasks.
    expect(find.byKey(const Key('ai-confirm-accept')), findsOneWidget);
    expect(find.byKey(const Key('ai-confirm-row-0')), findsOneWidget);
    expect(find.byKey(const Key('ai-confirm-row-1')), findsOneWidget);
    expect(api.requests.any((r) => r.contains('/ai/extract')), isTrue);
  });
}
