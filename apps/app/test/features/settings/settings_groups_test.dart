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

/// OPH-260 — Settings became an index of five places (DESIGN §32).
///
/// The risk in a re-home is not that it looks wrong; it is that a row quietly
/// fails to arrive anywhere. So the load-bearing test is a census: every row
/// that existed before is found on exactly one of the new pages, by the key it
/// already had. §22 in its plainest form — a setting nobody can reach is not a
/// setting.
Future<Widget> app(FakeApi api) async {
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

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined).first);
  await tester.pumpAndSettle();
}

Future<void> openGroup(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the root names five places and keeps sign out', (tester) async {
    wide(tester);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();
    await openSettings(tester);

    for (final key in [
      'settings-group-account',
      'settings-group-general',
      'settings-group-notifications',
      'settings-group-integrations',
      'settings-group-data',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key is the index');
    }
    // S4: the one action people arrive stressed for stays on the root.
    expect(find.text('Sign out'), findsOneWidget);
    // S1: the root is an index — the settings themselves moved down a level.
    expect(find.byKey(const Key('settings-language')), findsNothing);
    expect(find.byKey(const Key('notification-privacy')), findsNothing);
    // EE-042: the sixth row exists only where there is a team AND the caller
    // runs it. On a plain instance — which is what this fixture is — the
    // capability does not exist, so neither does the row. (The house idiom:
    // no entitlement, no surface. Its presence is covered where the feature
    // lives, in test/features/ee.)
    expect(find.byKey(const Key('settings-group-team')), findsNothing);
  });

  testWidgets('every row that existed still exists, on exactly one page', (
    tester,
  ) async {
    wide(tester);
    // group key -> the row keys that must live behind it (§32 S2's mapping).
    const census = <String, List<String>>{
      'settings-group-general': [
        'settings-language',
        'settings-date-format',
        'settings-default-task-time',
        'quick-bubble-toggle',
        'replay-tour',
      ],
      'settings-group-notifications': [
        'alarm-status',
        'notification-privacy',
        'settings-reminder-system',
        'settings-alarm-log',
      ],
      'settings-group-data': ['settings-completed', 'settings-share-log'],
    };

    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();

    for (final entry in census.entries) {
      await openSettings(tester);
      await openGroup(tester, entry.key);
      for (final row in entry.value) {
        expect(
          find.byKey(Key(row)),
          findsOneWidget,
          reason: '$row went missing when settings were regrouped',
        );
      }
      // Back to the root for the next group.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Account holds the server row and the way out of the app', (
    tester,
  ) async {
    wide(tester);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    await openGroup(tester, 'settings-group-account');

    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('Integrations carries the calendars', (tester) async {
    wide(tester);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    await openGroup(tester, 'settings-group-integrations');

    // The Google card is always there; Apple hides itself off Apple platforms
    // and AI hides itself when the server has it disabled, so neither is
    // asserted here — that is their own behaviour, not this task's.
    expect(find.text('Google Calendar'), findsOneWidget);
  });

  testWidgets('a settings URL still works — the deep routes did not move', (
    tester,
  ) async {
    wide(tester);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    await openGroup(tester, 'settings-group-notifications');
    await tester.tap(find.byKey(const Key('settings-alarm-log')));
    await tester.pumpAndSettle();

    expect(find.text('Alarm log'), findsWidgets);
  });
}
