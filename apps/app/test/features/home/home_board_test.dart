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

/// OPH-168 — the Pano (kanban) view: DESIGN §14 K1…K6.
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

Future<void> wideSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> openBoard(WidgetTester tester) async {
  await tester.tap(find.text('Board'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the toggle opens the board: status columns, counts, terminal '
      'statuses included (K1/K2)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedTask(title: 'Açık iş');
    api.seedTask(title: 'Süren iş', status: 'in_progress');
    api.seedTask(title: 'Biten iş', status: 'completed');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await openBoard(tester);

    // Default visible columns render…
    for (final status in ['open', 'in_progress', 'waiting', 'completed']) {
      expect(find.byKey(Key('board-column-$status')), findsOneWidget);
    }
    // …with their cards — including a COMPLETED one the list view hides.
    expect(find.text('Açık iş'), findsOneWidget);
    expect(find.text('Süren iş'), findsOneWidget);
    expect(find.text('Biten iş'), findsOneWidget);
  });

  testWidgets('the explicit move path changes status and offers undo (K3b/K5)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTask(title: 'Taşınacak iş');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openBoard(tester);

    final taskId = api.tasks.single['id'] as String;
    await tester.tap(find.byKey(Key('board-move-button-$taskId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('board-move-in_progress')));
    await tester.pumpAndSettle();

    expect(api.tasks.single['status'], 'in_progress');
    expect(find.text('Undo'), findsOneWidget); // the snackbar action

    // Undo restores the previous status through the same store path.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(api.tasks.single['status'], 'open');
  });

  testWidgets('long-press drag onto another column drops the card there '
      '(K3a)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTask(title: 'Sürüklenen iş');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openBoard(tester);

    final card = find.text('Sürüklenen iş');
    final target = find.byKey(const Key('board-column-waiting'));
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 300)); // long-press lift
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(api.tasks.single['status'], 'waiting');
  });

  testWidgets('hiding a column persists and its status stays reachable via '
      'the move sheet (K2)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTask(title: 'Bekleyen düzen');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openBoard(tester);

    await tester.tap(find.byKey(const Key('board-edit-columns')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('board-column-toggle-waiting')));
    await tester.pumpAndSettle();
    // Close the sheet explicitly (a corner tap can land on the barrier of a
    // re-opened route in this layout).
    Navigator.of(
      tester.element(find.byKey(const Key('board-column-toggle-open'))),
    ).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('board-column-waiting')), findsNothing);

    // Hidden ≠ unreachable: the move sheet still lists it (K3b).
    final taskId = api.tasks.single['id'] as String;
    await tester.tap(find.byKey(Key('board-move-button-$taskId')));
    await tester.pumpAndSettle();
    expect(find.text('Change status'), findsOneWidget); // the sheet opened
    expect(find.byKey(const Key('board-move-waiting')), findsOneWidget);
  });

  testWidgets('an empty column offers status-preset creation (K6)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openBoard(tester);

    await tester.tap(find.byKey(const Key('board-add-in_progress')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Panodan doğan iş',
    );
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    expect(api.tasks.single['status'], 'in_progress'); // born in its column
    expect(find.text('Panodan doğan iş'), findsOneWidget);
  });
}
