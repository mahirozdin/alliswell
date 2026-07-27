import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/tasks/ui/task_tile.dart';

import 'auth/test_support.dart';
import 'projects/fake_api.dart';
import '../support/sync_overrides.dart';

/// OPH-171 — pull to refresh in all five sections (DESIGN §15).
///
/// The gesture's job is one thing: run a sync round. So every test here counts
/// `/sync/pull` calls on the fake server before and after the drag — the same
/// evidence the user has ("did it actually go and look?").
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

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

int pulls(FakeApi api) =>
    api.requests.where((r) => r.contains('/sync/pull')).length;

Future<void> openSection(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// One pull-down over [finder], settled (the indicator holds for
/// [kAwRefreshMinDuration], so this needs the settle).
Future<void> pullDown(WidgetTester tester, Finder finder) async {
  await tester.drag(finder, const Offset(0, 320), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    // localKv is a GLOBAL singleton whose cache outlives a test: without this
    // the board test's 'board' choice leaks into the next test and Home opens
    // on the wrong view.
    await localKv.remove('alliswell_home_view');
  });

  testWidgets('Home: pulling the list runs a sync round', (tester) async {
    phone(tester);
    final api = FakeApi();
    for (var i = 0; i < 12; i++) {
      api.seedTask(title: 'İş ${i.toString().padLeft(2, '0')}');
    }
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    final before = pulls(api);
    await pullDown(tester, find.byKey(const Key('home-scroll')));
    expect(pulls(api), greaterThan(before));
    // R3: the data is still there — a refresh never blanks the list.
    expect(find.byType(TaskTile), findsWidgets);
  });

  testWidgets('Ideas: the EMPTY capture box is pullable too', (tester) async {
    phone(tester);
    final api = FakeApi();
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openSection(tester, 'Inbox');

    // Nothing captured yet — the empty state itself must accept the gesture,
    // or a fresh install could never refresh (the classic trap).
    expect(find.text('Inbox is for capturing'), findsOneWidget);
    final before = pulls(api);
    await pullDown(tester, find.byKey(const Key('inbox-refresh')));
    expect(pulls(api), greaterThan(before));
  });

  testWidgets('Projects and Notes pull independently', (tester) async {
    phone(tester);
    final api = FakeApi();
    api.seedProject(name: 'Ev');
    api.seedNote(title: 'Alışveriş');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await openSection(tester, 'Projects');
    var before = pulls(api);
    await pullDown(tester, find.byKey(const Key('projects-refresh')));
    expect(pulls(api), greaterThan(before), reason: 'Projects must refresh');

    await openSection(tester, 'Notes');
    before = pulls(api);
    await pullDown(tester, find.byKey(const Key('notes-refresh')));
    expect(pulls(api), greaterThan(before), reason: 'Notes must refresh');
  });

  testWidgets('Files: both layers pull (Klasörlerim and Kaynaklar)', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Fatura öde');
    api.seedFile(
      name: 'kök.txt',
      targetType: 'workspace',
      targetId: api.workspaceId,
    );
    api.seedFile(
      name: 'ekli.txt',
      targetType: 'task',
      targetId: task['id'] as String,
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openSection(tester, 'Files');

    var before = pulls(api);
    await pullDown(tester, find.byKey(const Key('files-refresh')));
    expect(pulls(api), greaterThan(before), reason: 'Klasörlerim must refresh');

    await tester.tap(find.text('Sources').last);
    await tester.pumpAndSettle();
    before = pulls(api);
    await pullDown(tester, find.byKey(const Key('sources-refresh')));
    expect(pulls(api), greaterThan(before), reason: 'Kaynaklar must refresh');
  });

  testWidgets('Board: a column pulls, and long-press drag still moves a card', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    api.seedTask(title: 'Taşınacak');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();

    final before = pulls(api);
    await pullDown(tester, find.byKey(const Key('board-refresh-open')));
    expect(pulls(api), greaterThan(before));

    // The pull must not have cost the board its drag gesture (K3a): a
    // long-press lift + move onto another column still changes the status.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Taşınacak')),
    );
    await tester.pump(const Duration(milliseconds: 300)); // long-press lift
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('board-column-waiting'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(api.tasks.single['status'], 'waiting');
  });

  testWidgets('a failed refresh says so and keeps the data', (tester) async {
    phone(tester);
    final api = FakeApi();
    api.seedTask(title: 'Yerinde kalsın');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    api.offline = true; // the server goes away between rounds
    await pullDown(tester, find.byKey(const Key('home-scroll')));

    expect(
      find.text("Couldn't refresh — you're seeing the last synced data."),
      findsOneWidget,
    );
    // R4: the visible data is exactly what it was.
    expect(find.text('Yerinde kalsın'), findsOneWidget);

    // Let the engine's armed backoff retry fire against a healthy server, so
    // the test leaves no pending timer behind.
    api.offline = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('wide layouts get a refresh button (a wheel cannot overscroll)', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    final before = pulls(api);
    await tester.tap(find.byKey(const Key('section-refresh')));
    await tester.pumpAndSettle();
    expect(pulls(api), greaterThan(before));
  });

  testWidgets('phones do NOT get the button (the gesture is the way)', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('section-refresh')), findsNothing);
  });
}
