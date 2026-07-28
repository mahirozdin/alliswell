import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/pending_deletes.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-184 — swipe to delete, everywhere, with a real undo (DESIGN §19).
///
/// The engine (store delete → outbox → `DELETE /tasks/:id`) shipped in v1 and
/// had a button on exactly one screen. These tests are about the button, and
/// about the promise attached to it: **while you can still undo, nothing has
/// been written.**
Future<Widget> app(FakeApi api, {Duration? undoWindow}) async {
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
      if (undoWindow != null) undoWindowProvider.overrideWithValue(undoWindow),
    ],
    child: const AllisWellApp(),
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Deletes pushed to the fake server — the evidence that the undo window is
/// real. `PendingDeletes` hides the row instantly; only a commit gets here.
int deletes(FakeApi api) =>
    api.requests.where((r) => r.contains('/sync/push')).length;

bool pushedDelete(FakeApi api) =>
    api.pushedMutations.any((m) => m['operation'] == 'delete');

Future<void> openSection(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Swipe the row open, then TAP the revealed button — the two-step Apple idiom
/// the whole task is about. A single fling must never be enough.
Future<void> swipeAndDelete(WidgetTester tester, String id) async {
  await tester.drag(find.byKey(Key('swipe-$id')), const Offset(-250, 0));
  await tester.pumpAndSettle();
  expect(
    find.byKey(Key('swipe-delete-$id')),
    findsOneWidget,
    reason: 'the swipe should REVEAL a delete button, not delete by itself',
  );
  await tester.tap(find.byKey(Key('swipe-delete-$id')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_home_view');
  });

  testWidgets('a swipe reveals Delete; tapping it removes the row from Home', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Silinecek');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    expect(find.text('Silinecek'), findsOneWidget);

    // The drag alone must leave the task on screen.
    await tester.drag(
      find.byKey(Key('swipe-${task['id']}')),
      const Offset(-250, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Silinecek'), findsOneWidget);

    await tester.tap(find.byKey(Key('swipe-delete-${task['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('Silinecek'), findsNothing);
  });

  testWidgets('Undo brings the row back and writes NOTHING to the outbox', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Vazgeçtim');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await swipeAndDelete(tester, task['id'] as String);
    expect(find.text('Vazgeçtim'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Vazgeçtim'), findsOneWidget);
    // The heart of D4: an undo that has to re-create the record is not an undo.
    expect(
      pushedDelete(api),
      isFalse,
      reason: 'nothing may be deleted while the undo is still on screen',
    );
  });

  testWidgets('when the window closes the delete really is pushed', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Gerçekten gitsin');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await swipeAndDelete(tester, task['id'] as String);
    // `pumpAndSettle` only advances until frames stop (~the snackbar's entrance),
    // so the 5 s window is still open here. A SHORTER window would not test
    // anything — settle would jump straight past it and this line would fail.
    expect(pushedDelete(api), isFalse);

    // One jump past the window: the commit timer and the snackbar both expire.
    await tester.pump(kAwUndoWindow + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Gerçekten gitsin'), findsNothing);
    expect(
      pushedDelete(api),
      isTrue,
      reason: 'after the window the same store delete the Inbox always used',
    );
  });

  testWidgets('the task detail screen can delete, and pops back', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    api.seedTask(title: 'Detaydan sil');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Detaydan sil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-delete')));
    await tester.pumpAndSettle();

    // Back on the list, and the row is gone from it.
    expect(find.byKey(const Key('task-title')), findsNothing);
    expect(find.text('Detaydan sil'), findsNothing);
  });

  testWidgets('a note can be deleted from the LIST, not just its editor', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final note = api.seedNote(title: 'Liste notu');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openSection(tester, 'Notes');

    expect(find.text('Liste notu'), findsOneWidget);
    await swipeAndDelete(tester, note['id'] as String);
    expect(find.text('Liste notu'), findsNothing);
  });

  testWidgets('the note row menu offers Delete too — a mouse cannot swipe', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final note = api.seedNote(title: 'Menüden');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openSection(tester, 'Notes');

    await tester.tap(find.byKey(Key('note-menu-${note['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Menüden'), findsNothing);
  });

  testWidgets(
    'a project delete still asks first — cascades keep their dialog',
    (tester) async {
      phone(tester);
      final api = FakeApi();
      final project = api.seedProject(name: 'Kaskad');
      await tester.pumpWidget(await app(api));
      await tester.pumpAndSettle();
      await openSection(tester, 'Projects');

      await tester.drag(
        find.byKey(Key('swipe-${project['id']}')),
        const Offset(-250, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('swipe-delete-${project['id']}')));
      await tester.pumpAndSettle();

      // D3: the swipe is a shortcut TO the cascade question, never past it.
      expect(find.byKey(const Key('confirm-delete')), findsOneWidget);
      expect(find.text('Kaskad'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Kaskad'), findsNothing);
    },
  );

  testWidgets('the board has no swipe, but its move sheet can delete (D6)', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Panodan');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('Panodan'), findsOneWidget);
    // The pager owns the horizontal gesture, so the card is deliberately not
    // swipeable — asserting its absence is what keeps D6 a decision.
    expect(find.byKey(Key('swipe-${task['id']}')), findsNothing);

    await tester.tap(find.byKey(Key('board-move-button-${task['id']}')));
    await tester.pumpAndSettle();
    // The sheet lists every status before it; on a phone the delete row is
    // below the fold (the OPH-181 lesson — scroll, don't tap into the void).
    await tester.scrollUntilVisible(
      find.byKey(const Key('board-delete')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    // `scrollUntilVisible` stops as soon as the widget EXISTS; on a phone that
    // leaves it under the floating bottom bar, and the tap would silently miss
    // (flutter_test only warns). `ensureVisible` puts it where a finger could
    // actually reach it — this file's own idiom since OPH-181.
    await tester.ensureVisible(find.byKey(const Key('board-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('board-delete')));
    await tester.pumpAndSettle();

    expect(find.text('Panodan'), findsNothing);
  });

  testWidgets('deleting the only task of a group takes its header too', (
    tester,
  ) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(
      title: 'Tek görev',
      dueAt: DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
    );
    final widget = await app(api);
    // The month card would push the group header past a phone viewport, and a
    // lazy sliver never builds what it does not show. Collapsing the calendar
    // is the app's own switch, so this stays a real user state. Set AFTER
    // `app()` — it resets SharedPreferences, and `localKv` caches them.
    await localKv.set('alliswell_home_calendar_visible', 'false');
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // The header carries the group's COUNT ("Tomorrow · 1"), which is exactly
    // what would go stale if the pending row were only hidden by the row widget.
    expect(find.text('Tomorrow · 1'), findsOneWidget);
    await swipeAndDelete(tester, task['id'] as String);

    // The row hides itself, but the GROUPING is computed from the raw list —
    // without the pending filter this header would stand above nothing, still
    // claiming "· 1".
    expect(find.textContaining('Tomorrow'), findsNothing);
  });
}
