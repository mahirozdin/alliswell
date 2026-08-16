import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';
import 'settings_nav.dart';

/// Deleting an account must be reachable from inside the app (App Store
/// 5.1.1(v), Google Play) — and the way back out of it must work. A
/// half-wired "delete" is worse than none.
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
  Future<void> openSettings(WidgetTester tester, FakeApi api) async {
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    // OPH-260: account rows live behind the Account group now.
    await openSettingsGroup(tester, kSettingsAccount);
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('requesting deletion shows the deadline and an undo', (
    tester,
  ) async {
    final api = FakeApi();
    await openSettings(tester, api);

    final entry = find.text('settings.deleteAccount.title'.tr());
    await scrollTo(tester, entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    // Destructive actions confirm first.
    expect(
      find.text('settings.deleteAccount.confirmBody'.tr()),
      findsOneWidget,
    );
    await tester.tap(find.text('settings.deleteAccount.confirm'.tr()));
    await tester.pumpAndSettle();

    // The server scheduled it; the row becomes the countdown + the way out.
    expect(api.deletionScheduledAt, isNotNull);
    expect(
      find.text('settings.deleteAccount.pendingTitle'.tr()),
      findsOneWidget,
    );

    final undo = find.text('settings.deleteAccount.keepAccount'.tr());
    await scrollTo(tester, undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(api.deletionScheduledAt, isNull);
    expect(find.text('settings.deleteAccount.pendingTitle'.tr()), findsNothing);
  });

  testWidgets('backing out of the confirmation deletes nothing', (
    tester,
  ) async {
    final api = FakeApi();
    await openSettings(tester, api);

    final entry = find.text('settings.deleteAccount.title'.tr());
    await scrollTo(tester, entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('common.cancel'.tr()));
    await tester.pumpAndSettle();

    expect(api.deletionScheduledAt, isNull);
  });

  testWidgets('an account already scheduled opens straight into the undo', (
    tester,
  ) async {
    final api = FakeApi()
      ..deletionScheduledAt = DateTime.utc(2026, 8, 1, 12).toIso8601String();
    await openSettings(tester, api);

    final pending = find.text('settings.deleteAccount.pendingTitle'.tr());
    await scrollTo(tester, pending);
    expect(pending, findsOneWidget);
    // The delete button is replaced, not shown alongside it.
    expect(find.text('settings.deleteAccount.title'.tr()), findsNothing);
  });
}
