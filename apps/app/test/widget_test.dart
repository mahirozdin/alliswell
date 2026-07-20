import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import 'features/auth/test_support.dart';
import 'features/projects/fake_api.dart';
import 'support/sync_overrides.dart';

/// Boots the app with a persisted session (shell instead of /login) and an
/// empty in-memory API — session restore itself is covered in test/features/.
Future<ProviderScope> signedInApp() async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(FakeApi().handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}


/// Wide two-pane surface: these shell tests assert CONTENT presence, not
/// phone sliver economics (the narrow Home keeps search+calendar in the
/// scroll — OPH-167/168).
Future<void> wideSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('app shell renders Home for a restored session', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(await signedInApp());
    await tester.pumpAndSettle();

    // Initial route is /home: title in the app bar + nav destination, and the
    // empty state shows since the fake workspace has no tasks.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('navigating to another section swaps the screen', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(await signedInApp());
    await tester.pumpAndSettle();

    // Every section is a real screen now — Notes shows its empty state.
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    expect(find.text('No notes here'), findsOneWidget);
    expect(find.byKey(const Key('notes-search')), findsOneWidget);
  });
}
