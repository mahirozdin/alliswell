import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';
import 'settings_nav.dart';

/// OPH-176 — the alarm log is reachable, honest about its scope, and shows what
/// the device actually did (DESIGN §11 A6).
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
  testWidgets('Settings opens the log; it states its scope and lists rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await signedInApp(FakeApi()));
    await tester.pumpAndSettle();

    // Seed a row through the app's OWN log instance (same database).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AllisWellApp)),
    );
    await container
        .read(alarmLogProvider)
        .record(
          event: AlarmLogEvent.scheduled,
          lane: AlarmLogLane.notification,
          urgent: true,
          kind: 'due',
          slotIndex: 0,
          sound: kAwAlarmSoundName,
          level: 'timeSensitive',
          fireAt: DateTime.utc(2026, 7, 15, 21, 45),
          reminderId: 'R1'.padRight(26, '0'),
        );
    await tester.pumpAndSettle();

    await openSettingsGroup(tester, kSettingsNotifications);

    final row = find.byKey(const Key('settings-alarm-log'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();

    // The honest scope comes BEFORE the data: we never claim delivery.
    expect(
      find.textContaining('iOS reports nothing about a notification'),
      findsOneWidget,
    );
    // …and the row carries what a bug report needs.
    expect(find.textContaining('sound=$kAwAlarmSoundName'), findsOneWidget);
    expect(find.textContaining('slot 0'), findsOneWidget);
    expect(find.textContaining('level=timeSensitive'), findsOneWidget);
    expect(find.text('Scheduled · notification'), findsOneWidget);
  });

  testWidgets('an empty log says so instead of looking broken', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await signedInApp(FakeApi()));
    await tester.pumpAndSettle();
    await openSettingsGroup(tester, kSettingsNotifications);

    final row = find.byKey(const Key('settings-alarm-log'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Nothing logged yet'), findsOneWidget);
    // Copy is disabled with nothing to copy.
    final copy = tester.widget<IconButton>(
      find.byKey(const Key('alarm-log-copy')),
    );
    expect(copy.onPressed, isNull);
  });
}
