import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/share_intent.dart';
import 'package:alliswell/src/features/ai/data/share_log.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';
import 'settings_nav.dart';

/// OPH-242 — the share log is reachable from Settings, states its scope, and
/// shows what actually arrived. The `alarm_log_screen_test.dart` twin.
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

Future<void> openShareLog(WidgetTester tester) async {
  await openSettingsGroup(tester, kSettingsData);
  final row = find.byKey(const Key('settings-share-log'));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Settings opens the log; it lists what arrived, without content',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await signedInApp(FakeApi()));
      await tester.pumpAndSettle();

      // Seed through the app's OWN log instance (same database).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AllisWellApp)),
      );
      await container
          .read(shareLogProvider)
          .record(
            event: ShareLogEvent.initialShare,
            payloadKind: ShareLogKind.url,
            bytes: 91,
          );
      await tester.pumpAndSettle();

      await openShareLog(tester);

      expect(find.text('Text arrived at launch'), findsOneWidget);
      expect(find.textContaining('91 B'), findsOneWidget);
      expect(find.textContaining(ShareLogKind.url), findsOneWidget);
    },
  );

  testWidgets('an empty log names the finding instead of looking broken', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await signedInApp(FakeApi()));
    await tester.pumpAndSettle();
    await openShareLog(tester);

    expect(find.text('Nothing shared yet'), findsOneWidget);
    // The scope sentence has to carry the diagnosis: an empty list after a
    // share attempt means the payload never reached the app. That sentence is
    // the whole reason this screen exists (OPH-242).
    expect(
      find.textContaining('never reached the app'),
      findsOneWidget,
      reason:
          'an empty log is the FINDING, not a missing feature — the screen '
          'must say so or the next report is unfalsifiable again',
    );
  });
}
