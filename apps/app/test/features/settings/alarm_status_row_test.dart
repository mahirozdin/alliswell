import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/notifications/gateway.dart';

import '../../support/fake_notifications.dart';
import '../../support/sync_overrides.dart';
import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import 'settings_nav.dart';

/// A browser that has not been asked yet, and says yes when the test lets it.
///
/// Not "yes on the first ask": the scheduler asks once at start-up, and that
/// ask must not be the one that fixes it.
class _AskableBrowser extends FakeNotificationsGateway {
  bool grantOnAsk = false;
  bool allowed = false;

  @override
  Future<bool> requestPermissions() async {
    if (grantOnAsk) allowed = true;
    return allowed;
  }

  @override
  Future<AlarmSupport> alarmSupport() async => allowed
      ? const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          webPushReady: true,
        )
      : const AlarmSupport(
          notificationsEnabled: false,
          criticalAlertsEnabled: false,
          webPushReady: false,
          webPermission: WebPermissionState.prompt,
        );
}

void main() {
  // #19 — the row probes on its own rather than through the provider the fix
  // sheet invalidates, so after "Allow notifications" it went on naming the
  // problem the sheet had just fixed.
  testWidgets('after the sheet fixes it, the Settings row says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());
    final browser = _AskableBrowser();
    final api = FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(notificationsGateway: browser),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();
    await openSettingsGroup(tester, kSettingsNotifications);

    final row = find.byKey(const Key('alarm-status'));
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('allowed in this browser yet'),
      ),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();
    browser.grantOnAsk = true;
    await tester.tap(find.byKey(const Key('alarm-fix-open')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: row, matching: find.textContaining('Ready')),
      findsOneWidget,
    );
  });
}
