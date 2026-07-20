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

/// OPH-165 — the tag system's UI: chip-input with auto-create, fold-matched
/// suggestions, manage sheet, and inline row tags (DESIGN §13 T1…T4).
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

/// Home in the wide two-pane layout so seeded tasks stay visible.
Future<void> wideSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String isoAt(DateTime local) => local.toUtc().toIso8601String();

void main() {
  final today = DateTime.now();
  final soon = isoAt(today.add(const Duration(days: 2, hours: 12)));

  testWidgets('create sheet: Enter and comma commit chips, missing tags are '
      'created, the task carries them (T1/T2)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Etiketli iş',
    );

    // Enter commits; a typed leading '#' is swallowed (T3).
    await tester.enterText(find.byKey(const Key('tag-input')), '#acil');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('#acil'), findsOneWidget); // the chip

    // Comma commits mid-typing (mobile path).
    await tester.enterText(find.byKey(const Key('tag-input')), 'ev,');
    await tester.pumpAndSettle();
    expect(find.text('#ev'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    expect(api.tags, hasLength(2)); // both were auto-created…
    final task = api.tasks.single;
    expect(task['tagIds'], hasLength(2)); // …and ride the task
    expect(
      api.tags.map((t) => t['name']),
      containsAll(<String>['acil', 'ev']),
    );
  });

  testWidgets('typing an existing tag fold-matches instead of duplicating '
      '(cay ↔ Çay)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTag(name: 'Çay');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Çay molası',
    );
    await tester.enterText(find.byKey(const Key('tag-input')), 'cay');
    await tester.pumpAndSettle();
    // Exact fold match exists → no "Create:" suggestion offered (T2).
    expect(find.byKey(const Key('tag-create-suggestion')), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('#Çay'), findsOneWidget); // the EXISTING tag's chip

    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    expect(api.tags, hasLength(1)); // no duplicate was created
    expect(api.tasks.single['tagIds'], [api.tags.single['id']]);
  });

  testWidgets('detail: assign via input, manage sheet deletes with the blast '
      'radius named (T3)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTag(name: 'rapor');
    api.seedTask(title: 'Yönetilecek iş', dueAt: soon);
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yönetilecek iş'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tag-input')));
    await tester.enterText(find.byKey(const Key('tag-input')), 'rapor');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      api.tasks.single['tagIds'],
      [api.tags.single['id']],
      reason: 'assigning replaces the set through store.setTags',
    );

    // Manage: delete confirms with how many tasks lose the tag.
    await tester.tap(find.byKey(const Key('tag-manage')));
    await tester.pumpAndSettle();
    final tagId = api.tags.single['id'] as String;
    await tester.tap(find.byKey(Key('tag-delete-$tagId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 '), findsOneWidget); // "…1 task(s)…"
    await tester.tap(find.byKey(const Key('tag-delete-confirm')));
    await tester.pumpAndSettle();

    expect(api.tags, isEmpty); // pushed delete reached the server
  });

  testWidgets('task rows show at most two inline tags plus +N (T4)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final a = api.seedTag(name: 'birinci');
    final b = api.seedTag(name: 'ikinci');
    final c = api.seedTag(name: 'üçüncü');
    api.seedTask(
      title: 'Çok etiketli iş',
      dueAt: soon,
      tagIds: [a['id'] as String, b['id'] as String, c['id'] as String],
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    expect(find.text('#birinci'), findsOneWidget);
    expect(find.text('#ikinci'), findsOneWidget);
    expect(find.text('#üçüncü'), findsNothing); // overflowed…
    expect(find.text('+1'), findsOneWidget); // …into the +N marker
  });
}
