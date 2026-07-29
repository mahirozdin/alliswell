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
}
