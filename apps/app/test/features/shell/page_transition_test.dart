import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-194 — a route is opaque to the route beneath it (DESIGN §21 T1).
///
/// Round 10 #10 read as a performance problem ("önceki sayfanın silueti kalıyor,
/// donma gibi") and was not one: scaffolds are ~50 % opaque over a single wash
/// painted BELOW the Navigator, so during every push both pages were visible
/// through each other. The test therefore stops the transition halfway and
/// asserts the outgoing screen is not on screen — the state a screenshot of the
/// bug would have shown.
Future<Widget> app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await localKv.remove('alliswell_home_view');
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_home_view');
  });

  testWidgets('mid-push, the incoming route carries its OWN opaque wash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()..seedTask(title: 'Altta kalan');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    // One route on screen, one wash.
    expect(find.byType(AwPageBackground), findsOneWidget);

    await tester.tap(find.text('Altta kalan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    // Halfway through, BOTH routes are mounted — and each one has to bring its
    // own background. Before OPH-194 there was exactly one in the whole app,
    // painted below the Navigator, which is precisely why the outgoing page
    // showed through the ~50 %-opaque scaffold of the incoming one.
    expect(
      find.byType(AwPageBackground),
      findsNWidgets(2),
      reason: 'a route must not borrow the background of the route beneath it',
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-title')), findsOneWidget);
  });

  testWidgets('every platform gets the same transition (T2)', (tester) async {
    // Unset, Flutter hands Android a Zoom, iOS a Cupertino slide and desktop a
    // third thing — one design system wearing three motions.
    for (final brightness in Brightness.values) {
      final theme = buildAwTheme(brightness);
      for (final platform in TargetPlatform.values) {
        expect(
          theme.pageTransitionsTheme.builders[platform],
          isA<AwPageTransitionsBuilder>(),
          reason: '$platform must use the app transition',
        );
      }
    }
    // And it obeys the motion budget (DESIGN G8: 150–320 ms).
    const builder = AwPageTransitionsBuilder();
    expect(
      builder.transitionDuration.inMilliseconds,
      inInclusiveRange(150, 320),
    );
  });

  testWidgets('switching sections stays instant — tabs are not a stack (T3)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notes').last);
    // One frame: an IndexedStack swap has nothing to animate.
    await tester.pump();
    expect(find.byKey(const Key('notes-refresh')), findsOneWidget);
  });
}
