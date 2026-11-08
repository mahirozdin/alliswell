import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/projects/ui/project_detail_screen.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_rail_section.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-199 — the wide-layout Quick Access surfaces (DESIGN §23 Q1/Q6/Q9).
Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  // localKv caches SharedPreferences process-wide, so mock values alone do not
  // reset it — the collapse preference has to be cleared by hand (tour_test's
  // lesson).
  await localKv.remove('alliswell_quick_rail_collapsed');
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

void sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// The three layouts the rail section has to distinguish.
const phone = Size(390, 844);
const narrowRail = Size(900, 800); // 800 ≤ w < 1160 — icon rail + popover
const wide = Size(1400, 900); // ≥ 1160 — extended rail + section

void main() {
  testWidgets('the extended rail lists shortcuts; the phone shows none', (
    tester,
  ) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Ahmet');
    api.seedQuickLink(
      kind: 'project',
      targetId: project['id'] as String,
      title: 'Ahmet',
    );
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    sizeTo(tester, wide);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAccessRailSection), findsOneWidget);
    expect(find.text('Quick access'), findsOneWidget);
    expect(find.text('Ahmet'), findsWidgets);
    expect(find.text('Site'), findsOneWidget);
    // An external link always carries its glyph — colour alone never says
    // "this leaves the app" (G5).
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);

    // The phone has neither surface: the bubble (OPH-200) is its entry point.
    sizeTo(tester, phone);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessRailSection), findsNothing);
    expect(find.byType(QuickAccessRailButton), findsNothing);
  });

  testWidgets(
    'the narrow rail shows one bolt button that opens the same list',
    (tester) async {
      final api = FakeApi();
      api.seedQuickLink(
        kind: 'url',
        url: 'https://alliswell.space',
        title: 'Site',
      );

      sizeTo(tester, narrowRail);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAccessRailButton), findsOneWidget);
      expect(find.byType(QuickAccessRailSection), findsNothing);
      // Closed popover: the row is not on screen yet.
      expect(find.text('Site'), findsNothing);

      await tester.tap(find.byKey(const Key('quick-rail-button')));
      await tester.pumpAndSettle();
      expect(find.text('Site'), findsOneWidget);
    },
  );

  testWidgets('tapping a row navigates to its target', (tester) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Ahmet');
    api.seedQuickLink(
      kind: 'project',
      targetId: project['id'] as String,
      title: 'Ahmet kısayolu',
    );

    sizeTo(tester, wide);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ahmet kısayolu'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
  });

  testWidgets('the row menu reorders through move up/down, not only by drag', (
    tester,
  ) async {
    final api = FakeApi();
    final first = api.seedQuickLink(
      kind: 'url',
      url: 'https://x.dev/a',
      title: 'A',
    );
    api.seedQuickLink(kind: 'url', url: 'https://x.dev/b', title: 'B');

    sizeTo(tester, wide);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('quick-menu-${first['id']}')));
    await tester.pumpAndSettle();
    // The first row cannot move up — only the down action is offered.
    expect(find.text('Move up'), findsNothing);
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();

    // One mutation carrying the whole order (the store's contract), pushed as
    // an ordinary update on the head row.
    final reorder = api.pushedMutations.where(
      (m) => m['entityType'] == 'quick_link' && m['operation'] == 'update',
    );
    expect(reorder, hasLength(1));
    expect((reorder.single['patch'] as Map)['orderedIds'], hasLength(2));
  });

  testWidgets(
    'an empty rail shows a one-line hint, never an empty-state card',
    (tester) async {
      final api = FakeApi();
      sizeTo(tester, wide);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAccessRailSection), findsOneWidget);
      expect(
        find.text('Add a project, note or link from any ⚡ menu'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the section collapses and the choice sticks', (tester) async {
    final api = FakeApi();
    api.seedQuickLink(kind: 'url', url: 'https://x.dev', title: 'Site');

    sizeTo(tester, wide);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    expect(find.text('Site'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quick-rail-header')));
    await tester.pumpAndSettle();
    expect(find.text('Site'), findsNothing);
    expect(find.text('Quick access'), findsOneWidget);

    // Device-local, so the next launch opens collapsed. (Asserted through the
    // store rather than by remounting the app: a second `pumpWidget` of a new
    // ProviderScope tears the router's Navigator down mid-frame.)
    expect(await localKv.get('alliswell_quick_rail_collapsed'), 'true');
  });

  group('OPH-405 — the menu and the drag handle are two columns', () {
    // Desktop only: on Android/iOS the row itself is long-pressed to drag and
    // there is no handle (Flutter's own split, kept).
    final desktop = TargetPlatformVariant.desktop();

    Future<List<String>> seedRows(FakeApi api) async {
      final project = api.seedProject(name: 'Launch v1.0');
      final rows = [
        api.seedQuickLink(
          kind: 'project',
          targetId: project['id'] as String,
          title: 'Launch v1.0',
          emoji: '🚀',
          colorRgb: '8B5CF6',
        ),
        api.seedQuickLink(kind: 'url', url: 'https://x.dev/a', title: 'Repo'),
        api.seedQuickLink(kind: 'url', url: 'https://x.dev/b', title: 'Docs'),
      ];
      return [for (final r in rows) r['id'] as String];
    }

    Rect menuRect(WidgetTester t, String id) =>
        t.getRect(find.byKey(Key('quick-menu-$id')));
    Rect handleRect(WidgetTester t, String id) =>
        t.getRect(find.byKey(Key('quick-drag-$id')));
    Rect menuGlyph(WidgetTester t, String id) => t.getRect(
      find.descendant(
        of: find.byKey(Key('quick-menu-$id')),
        matching: find.byIcon(Icons.more_horiz),
      ),
    );
    Rect handleGlyph(WidgetTester t, String id) => t.getRect(
      find.descendant(
        of: find.byKey(Key('quick-drag-$id')),
        matching: find.byIcon(Icons.drag_indicator),
      ),
    );
    bool handleShown(WidgetTester t, String id) =>
        t.widget<Visibility>(find.byKey(Key('quick-drag-reveal-$id'))).visible;

    /// T-05: the ⋯ column never moves (at rest, on hover, on focus) and sits
    /// at the row's trailing padding, so no empty column is held for a handle
    /// that is not there.
    void expectMenuColumn(WidgetTester tester, List<String> ids) {
      final menuLeft = menuRect(tester, ids.first).left;
      for (final id in ids) {
        final menu = menuRect(tester, id);
        final tile = tester.getRect(find.byKey(Key('quick-row-$id')));
        expect(menu.width, greaterThanOrEqualTo(32), reason: 'menu $id');
        expect(menu.height, greaterThanOrEqualTo(32), reason: 'menu $id');
        expect(menu.left, moreOrLessEquals(menuLeft), reason: id);
        expect(tile.right - menu.right, lessThanOrEqualTo(16), reason: id);
      }
    }

    /// A shown handle is its own 32×32 target, 8 px before the menu, and the
    /// painted glyphs never touch.
    void expectHandleApart(WidgetTester tester, String id) {
      final menu = menuRect(tester, id);
      final handle = handleRect(tester, id);
      expect(handle.width, greaterThanOrEqualTo(32), reason: 'drag $id');
      expect(handle.height, greaterThanOrEqualTo(32), reason: 'drag $id');
      expect(menu.overlaps(handle), isFalse, reason: id);
      expect(menu.left - handle.right, greaterThanOrEqualTo(8), reason: id);
      expect(menuGlyph(tester, id).overlaps(handleGlyph(tester, id)), isFalse);
    }

    testWidgets('separate targets; the handle shows on hover and the menu '
        'column stays put', (tester) async {
      final api = FakeApi();
      final ids = await seedRows(api);
      sizeTo(tester, wide);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      // Flutter's default desktop handle was painted over the menu.
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      expectMenuColumn(tester, ids);
      for (final id in ids) {
        expect(handleShown(tester, id), isFalse, reason: 'rest $id');
        // T-05: a hidden handle takes no room at all.
        expect(find.byKey(Key('quick-drag-$id')), findsNothing);
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Repo')));
      await tester.pump();
      expect(handleShown(tester, ids[1]), isTrue);
      expect(handleShown(tester, ids[0]), isFalse);
      expectMenuColumn(tester, ids);
      expectHandleApart(tester, ids[1]);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(handleShown(tester, ids[1]), isFalse);
    }, variant: desktop);

    testWidgets('T-05: a resting row gives its name the handle column back', (
      tester,
    ) async {
      final api = FakeApi();
      // Six glyphs: in the test font (1 em per glyph) the name fits only
      // when no 40 px handle column is held at rest (the "Design Sys…" bug).
      final id =
          api.seedQuickLink(
                kind: 'url',
                url: 'https://x.dev/ds',
                title: 'Design',
                emoji: '🎨',
                colorRgb: '3B82F6',
              )['id']
              as String;
      sizeTo(tester, wide);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      final title = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(Key('quick-row-$id')),
          matching: find.text('Design'),
        ),
      );
      expect(title.didExceedMaxLines, isFalse);
    }, variant: desktop);

    testWidgets('keyboard focus on a row reveals its handle, apart from the '
        'focused menu', (tester) async {
      final api = FakeApi();
      final ids = await seedRows(api);
      sizeTo(tester, wide);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      Focus.of(
        tester.element(
          find.descendant(
            of: find.byKey(Key('quick-menu-${ids[2]}')),
            matching: find.byIcon(Icons.more_horiz),
          ),
        ),
      ).requestFocus();
      await tester.pumpAndSettle();

      expect(handleShown(tester, ids[2]), isTrue);
      expect(handleShown(tester, ids[1]), isFalse);
      expectMenuColumn(tester, ids);
      expectHandleApart(tester, ids[2]);
    }, variant: desktop);

    testWidgets('dragging by the handle reorders', (tester) async {
      final api = FakeApi();
      final ids = await seedRows(api);
      sizeTo(tester, wide);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump();
      final from = tester.getCenter(find.byKey(Key('quick-drag-${ids[2]}')));
      await mouse.moveTo(from);
      await tester.pump();
      await mouse.down(from);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 12; i++) {
        await mouse.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await mouse.up();
      await tester.pumpAndSettle();

      final reorder = api.pushedMutations.where(
        (m) => m['entityType'] == 'quick_link' && m['operation'] == 'update',
      );
      expect(reorder, hasLength(1));
      final order = (reorder.single['patch'] as Map)['orderedIds'] as List;
      expect(order.indexOf(ids[2]), lessThan(2));
    }, variant: desktop);
  });
}
