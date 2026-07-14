import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import 'features/auth/test_support.dart';

/// Boots the app with a persisted session so the shell (not /login) renders —
/// session restore itself is covered in test/features/auth/.
Future<ProviderScope> signedInApp() async {
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    overrides: [secretStoreProvider.overrideWithValue(store)],
    child: const AllisWellApp(),
  );
}

void main() {
  testWidgets('app shell renders the Today section for a restored session', (
    tester,
  ) async {
    await tester.pumpWidget(await signedInApp());
    await tester.pumpAndSettle();

    // Initial route is /today: the section title appears in the page body
    // and in the navigation destinations.
    expect(find.text('Today'), findsWidgets);
    expect(
      find.text('Everything due, scheduled or urgent today.'),
      findsOneWidget,
    );
  });

  testWidgets('navigating to another section swaps the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(await signedInApp());
    await tester.pumpAndSettle();

    // Notes is still a placeholder (Epic 05); Projects became real in OPH-036.
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Rich notes, linkable to tasks and projects.'),
      findsOneWidget,
    );
  });
}
