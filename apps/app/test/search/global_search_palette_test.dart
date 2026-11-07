import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tags/tags.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/search/search_recents.dart';
import 'package:alliswell/src/search/ui/global_search_entry.dart';
import 'package:alliswell/src/search/ui/global_search_palette.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../features/auth/test_support.dart';
import '../features/projects/fake_api.dart';
import '../support/sync_overrides.dart';

/// OPH-374 — search everywhere (ADR-0055, DESIGN §40), driven through the
/// whole app: the root shortcut, the rail and phone entries, keyboard
/// navigation, every kind's way out, recents and the create row.
late ProviderContainer _container;

Future<Widget> app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await localKv.remove(kSearchRecentsKey);
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
    child: Consumer(
      builder: (context, ref, _) {
        _container = ProviderScope.containerOf(context);
        return const AllisWellApp();
      },
    ),
  );
}

Future<void> surface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> ctrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('global-search-field')), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

/// `state`, not `currentConfiguration.uri`: a pushed task detail keeps the
/// configuration's address on the shell.
String location() =>
    _container.read(routerProvider).routerDelegate.state.uri.path;

final _field = find.byKey(const Key('global-search-field'));

void main() {
  const desktop = Size(1280, 900);
  const phone = Size(390, 844);

  testWidgets('Ctrl+K opens the palette with nothing focused; arrows and '
      'Enter open a task; groups come out in order', (tester) async {
    await surface(tester, desktop);
    final api = FakeApi();
    final first = api.seedTask(title: 'Fatura öde');
    final second = api.seedTask(title: 'Faturayı dosyala');
    api.seedProject(name: 'Fatura arşivi');
    api.seedFile(
      name: 'fatura-ekim.pdf',
      targetType: 'workspace',
      targetId: api.workspaceId,
      mime: 'application/pdf',
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await ctrlK(tester);
    expect(_field, findsOneWidget);
    final field = tester.widget<TextField>(_field);
    expect(field.focusNode!.hasFocus, isTrue);

    await type(tester, 'fatura');
    // A-18 (OPH-394): a header carries its group's total.
    expect(find.text('Tasks · 2'), findsOneWidget);
    expect(find.text('Projects · 1'), findsOneWidget);
    expect(find.text('Files · 1'), findsOneWidget);
    final tasksY = tester.getTopLeft(find.text('Tasks · 2')).dy;
    final projectsY = tester.getTopLeft(find.text('Projects · 1')).dy;
    final filesY = tester.getTopLeft(find.text('Files · 1')).dy;
    expect(tasksY, lessThan(projectsY));
    expect(projectsY, lessThan(filesY));
    expect(find.byKey(const Key('global-search-count')), findsOneWidget);

    // The first row is active; ArrowDown moves to the second task.
    final rows = [
      first['id'],
      second['id'],
    ].map((id) => find.byKey(Key('global-search-task-$id'))).toList();
    expect(rows.every((f) => f.evaluate().isNotEmpty), isTrue);
    final firstY = tester.getTopLeft(rows[0]).dy;
    final secondY = tester.getTopLeft(rows[1]).dy;
    final lower = firstY < secondY ? rows[1] : rows[0];
    final lowerId = firstY < secondY ? second['id'] : first['id'];
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      find.descendant(of: lower, matching: find.byIcon(Icons.keyboard_return)),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_field, findsNothing);
    expect(location(), '/tasks/$lowerId');
  });

  testWidgets('Esc closes it, and a second Ctrl+K closes instead of stacking', (
    tester,
  ) async {
    await surface(tester, desktop);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();

    await ctrlK(tester);
    expect(_field, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_field, findsNothing);

    await ctrlK(tester);
    expect(_field, findsOneWidget);
    await ctrlK(tester);
    expect(_field, findsNothing);
    expect(isGlobalSearchOpen, isFalse);
  });

  testWidgets('a tag result lands on Home filtered, switching board to list', (
    tester,
  ) async {
    await surface(tester, desktop);
    final api = FakeApi();
    final tag = api.seedTag(name: 'Çay');
    api.seedTask(title: 'Demle', tagIds: [tag['id'] as String]);
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await _container.read(homeViewProvider.notifier).set('board');
    await tester.pumpAndSettle();

    await ctrlK(tester);
    await type(tester, 'cay');
    expect(find.byKey(Key('global-search-tag-${tag['id']}')), findsOneWidget);
    await tester.tap(find.byKey(Key('global-search-tag-${tag['id']}')));
    await tester.pumpAndSettle();

    expect(location(), '/home');
    expect(_container.read(tagFilterProvider), tag['id']);
    expect(_container.read(homeViewProvider), 'list');
    expect(find.byKey(const Key('tag-filter-bar')), findsOneWidget);
    // …and the tag is a recent now (tags have no address to track).
    expect(
      _container.read(searchRecentsProvider).first.id,
      tag['id'] as String,
    );
  });

  testWidgets('a file result opens its actions sheet', (tester) async {
    await surface(tester, desktop);
    final api = FakeApi();
    final file = api.seedFile(
      name: 'Işık faturası.pdf',
      targetType: 'workspace',
      targetId: api.workspaceId,
      mime: 'application/pdf',
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await ctrlK(tester);
    await type(tester, 'isik');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_field, findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Işık faturası.pdf'), findsWidgets);
    expect(
      _container.read(searchRecentsProvider).first.id,
      file['id'] as String,
    );
  });

  testWidgets('no hits: an honest empty state and a create row that opens '
      'the sheet prefilled, writing nothing', (tester) async {
    await surface(tester, desktop);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();

    await ctrlK(tester);
    await type(tester, 'Kira öde');
    expect(find.byKey(const Key('global-search-empty')), findsOneWidget);
    expect(find.byKey(const Key('global-search-create')), findsOneWidget);
    expect(find.text('Create task “Kira öde”'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_field, findsNothing);
    final sheetTitle = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    expect(sheetTitle, findsWidgets);
    expect(
      tester.widget<TextField>(sheetTitle.first).controller!.text,
      'Kira öde',
    );
    final db = _container.read(databaseProvider);
    expect(await db.select(db.pendingMutations).get(), isEmpty);
    expect(await db.select(db.tasks).get(), isEmpty);
  });

  testWidgets('an empty field shows the tasks opened last', (tester) async {
    await surface(tester, desktop);
    final api = FakeApi();
    final task = api.seedTask(title: 'Raporu gönder');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    // Opened from anywhere — here by its address — is a recent.
    GoRouter.of(
      awRootNavigatorKey.currentContext!,
    ).push('/tasks/${task['id']}');
    await tester.pumpAndSettle();
    awRootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    await ctrlK(tester);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.byKey(Key('global-search-task-${task['id']}')), findsOneWidget);
  });

  testWidgets('the rail entry opens it, and the semantics say what is active', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await surface(tester, desktop);
    final api = FakeApi();
    api.seedTask(title: 'Bütçe');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('global-search-rail')));
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);

    await type(tester, 'butce');
    expect(find.bySemanticsLabel('Task: Bütçe'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Task: Bütçe'));
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    final header = tester.getSemantics(find.text('Tasks · 1').last);
    expect(header.flagsCollection.isHeader, isTrue);
    semantics.dispose();
  });

  testWidgets('phone: the search button beside the bar opens the full-screen '
      'palette, and a project result goes to the project', (tester) async {
    await surface(tester, phone);
    final api = FakeApi();
    final project = api.seedProject(name: 'Mutfak yenileme');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('global-search-orb')), findsOneWidget);
    final bar = tester.getRect(find.byType(NavigationBar));
    final orb = tester.getRect(find.byKey(const Key('global-search-orb')));
    expect(orb.left, greaterThanOrEqualTo(bar.right));
    expect((orb.center.dy - bar.center.dy).abs(), lessThan(8));
    // The selected label stays on one line in a slot narrower than the
    // word (TR "Ana Sayfa" wrapped under the pill and was clipped).
    final label = tester.widget<RichText>(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text('Home'),
            ),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(label.softWrap, isFalse);
    expect(label.maxLines, 1);

    await tester.tap(find.byKey(const Key('global-search-orb')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(_field, findsOneWidget);

    await type(tester, 'mutfak');
    await tester.tap(find.byKey(Key('global-search-project-${project['id']}')));
    await tester.pumpAndSettle();
    expect(location(), '/projects/${project['id']}');
  });

  test('the shortcut is Ctrl+K off Apple and ⌘K on it, never both', () {
    expect(globalSearchActivators(), hasLength(1));
    final off = globalSearchActivators().single as SingleActivator;
    expect(off.control, isTrue);
    expect(off.meta, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final apple = globalSearchActivators().single as SingleActivator;
      expect(apple.meta, isTrue);
      expect(apple.control, isFalse);
      expect(globalSearchShortcutLabel(), '⌘K');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // OPH-394 (E-12): the count sits under the field, every group opens with
  // three rows and a "Show N more" row that expands it — notes included.
  for (final size in [desktop, phone]) {
    testWidgets('the count is under the field and a long group expands '
        '(${size.width.toInt()} px)', (tester) async {
      await surface(tester, size);
      final api = FakeApi();
      for (var i = 1; i <= 6; i++) {
        api.seedTask(title: 'Invoice task $i');
      }
      for (var i = 1; i <= 9; i++) {
        api.seedNote(title: 'Invoice note $i');
      }
      await tester.pumpWidget(await app(api));
      await tester.pumpAndSettle();

      if (size == desktop) {
        await ctrlK(tester);
      } else {
        await tester.tap(find.byKey(const Key('global-search-orb')));
        await tester.pumpAndSettle();
      }
      await type(tester, 'invoice');

      final count = find.byKey(const Key('global-search-count'));
      expect(find.text('15 results'), findsOneWidget);
      final fieldBottom = tester.getBottomLeft(_field).dy;
      final countTop = tester.getTopLeft(count).dy;
      final firstHeader = find.text('Tasks · 6');
      expect(firstHeader, findsOneWidget);
      expect(countTop, greaterThanOrEqualTo(fieldBottom));
      expect(countTop, lessThan(tester.getTopLeft(firstHeader).dy));

      // Three of each, and the way to the rest.
      expect(find.text('Notes · 9'), findsOneWidget);
      expect(find.textContaining('Invoice note'), findsNWidgets(3));
      final more = find.byKey(const Key('global-search-more-note'));
      expect(find.text('Show 6 more'), findsOneWidget);
      expect(find.text('Show 3 more'), findsOneWidget);
      await tester.scrollUntilVisible(
        more,
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('global-search-results')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(
        find.descendant(of: more, matching: find.byType(TextButton)),
      );
      await tester.pumpAndSettle();
      expect(more, findsNothing);
      for (var i = 1; i <= 9; i++) {
        expect(
          find.text('Invoice note $i', skipOffstage: false),
          findsOneWidget,
        );
      }
    });
  }
}
