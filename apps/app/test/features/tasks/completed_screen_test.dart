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

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-186 — Settings ▸ Completed, the archive of finished work
/// (DESIGN §20 C4). Reached the way a user reaches it, from Settings.
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

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> openCompleted(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined).last);
  await tester.pumpAndSettle();
  // Settings grows over time (OPH-200 added the quick-access toggle), so the
  // archive row is not necessarily on screen: scroll to it rather than tapping
  // where it used to be.
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings-completed')),
    240,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings-completed')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_home_view');
  });

  testWidgets('Settings opens the archive and it lists finished work', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi()
      ..seedTask(
        title: 'Bitmiş iş',
        status: 'completed',
        dueAt: DateTime.utc(2026, 7, 20, 9).toIso8601String(),
      )
      ..seedTask(title: 'Duran iş');

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    // Home shows the open one and (this task's whole point) NOT the archive.
    expect(find.text('Duran iş'), findsOneWidget);

    await openCompleted(tester);
    expect(find.text('Bitmiş iş'), findsOneWidget);
    // Its scope is stated above the data, the way the alarm log states its own.
    expect(find.textContaining('Completed tasks'), findsOneWidget);
    // The archive is the archive: open work does not leak into it.
    expect(find.text('Duran iş'), findsNothing);
  });

  testWidgets('empty archive says so instead of showing a blank list', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi()..seedTask(title: 'Hiç bitmedi');

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openCompleted(tester);

    expect(find.text('Nothing completed yet'), findsOneWidget);
  });

  testWidgets('Reopen puts the task back on Home and out of the archive', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(
      title: 'Geri açılacak',
      status: 'completed',
      dueAt: DateTime.utc(2026, 7, 20, 9).toIso8601String(),
    );

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openCompleted(tester);
    expect(find.text('Geri açılacak'), findsOneWidget);

    await tester.tap(find.byKey(Key('reopen-${task['id']}')));
    await tester.pumpAndSettle();

    // Leaving the screen is the contract here, not a bug: this list is
    // "completed", and the task no longer is.
    expect(find.text('Geri açılacak'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Geri açılacak'), findsOneWidget);
  });

  testWidgets('rows can be deleted from the archive too (OPH-184 reused)', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(
      title: 'Arşivden sil',
      status: 'completed',
      dueAt: DateTime.utc(2026, 7, 20, 9).toIso8601String(),
    );

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openCompleted(tester);

    await tester.drag(
      find.byKey(Key('swipe-${task['id']}')),
      const Offset(-250, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('swipe-delete-${task['id']}')));
    await tester.pumpAndSettle();

    expect(find.text('Arşivden sil'), findsNothing);
  });

  testWidgets('a task completed TODAY is on Home and in the archive', (
    tester,
  ) async {
    phone(tester);
    // The two rules meet here: §20 C1 keeps it on the planning list for the
    // rest of the day, C4 says the archive holds everything ever finished.
    // A row that vanished from Home the moment it was completed would make
    // this test impossible to write — which is why it exists.
    final api = FakeApi()
      ..seedTask(
        title: 'Bugün bitti',
        status: 'completed',
        dueAt: DateTime.now().toUtc().toIso8601String(),
        completedAt: DateTime.now().toUtc().toIso8601String(),
      );

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    expect(find.text('Bugün bitti'), findsOneWidget);

    await openCompleted(tester);
    expect(find.text('Bugün bitti'), findsOneWidget);
  });
}
