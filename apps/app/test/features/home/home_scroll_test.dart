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
import 'package:alliswell/src/features/home/month_calendar.dart';
import 'package:alliswell/src/features/tasks/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

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

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

int _pulls(FakeApi api) =>
    api.requests.where((r) => r.contains('/sync/pull')).length;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  // OPH-103: on phones the month calendar used to be a fixed header eating half
  // the screen. It must now scroll away with the list.
  testWidgets('the month calendar scrolls off with the list, then returns', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    for (var i = 0; i < 25; i++) {
      api.seedTask(title: 'İş ${i.toString().padLeft(2, '0')}');
    }
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    // Visible by default, at the top of the scroll view.
    expect(find.byType(MonthCalendar).hitTestable(), findsOneWidget);

    // Scroll the list up — the calendar leaves the viewport (not pinned).
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(MonthCalendar).hitTestable(),
      findsNothing,
      reason: 'the calendar must scroll away, not stay fixed at the top',
    );

    // Scroll back to the top — it comes back.
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar).hitTestable(), findsOneWidget);
  });

  testWidgets('Hide calendar removes it; the quick-add still captures', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byType(MonthCalendar), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-calendar')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsNothing);

    // The quick-add bar rides the scroll view now (OPH-172) — it is still the
    // first thing under the app bar and still captures.
    await tester.enterText(find.byKey(const Key('home-quick-add')), 'Yeni iş');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.tasks.any((t) => t['title'] == 'Yeni iş'), isTrue);
  });

  testWidgets('hiding the calendar clears the day selection', (tester) async {
    _phone(tester);
    // localKv is a global singleton cache — the previous test's "Hide
    // calendar" tap persists across tests unless cleared here.
    await localKv.remove('alliswell_home_calendar_visible');
    final api = FakeApi();
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AllisWellApp)),
    );
    final today = DateTime.now();
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();
    expect(container.read(selectedDayProvider), isNotNull);

    // Hiding the calendar drops the selection — a filter you can no longer
    // see must not keep dimming Home (feedback round 6).
    await tester.tap(find.byKey(const Key('toggle-calendar')));
    await tester.pumpAndSettle();
    expect(container.read(selectedDayProvider), isNull);
  });

  // ── OPH-172: on phones ONLY the app bar is pinned (DESIGN §16 H1) ──────────

  testWidgets(
    'quick add scrolls away; the view toggle is pinned in the app bar (H1)',
    (tester) async {
      _phone(tester);
      final api = FakeApi();
      for (var i = 0; i < 25; i++) {
        api.seedTask(title: 'İş ${i.toString().padLeft(2, '0')}');
      }
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      // OPH-213 (DESIGN §16 H1, revised): the view toggle no longer scrolls —
      // it moved INTO the app bar, which is the one thing H1 always allowed to
      // stay pinned. So it is visible before AND after the scroll; what still
      // has to get out of the way is the quick-add bar.
      expect(find.byKey(const Key('home-view-toggle')).hitTestable(), findsOne);
      expect(find.byKey(const Key('home-quick-add')).hitTestable(), findsOne);

      await tester.drag(
        find.byKey(const Key('home-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      // Round 9 #2: chrome must not stay up there narrowing the list — and the
      // app bar earns its pin by carrying the controls that used to.
      expect(
        find.byKey(const Key('home-view-toggle')).hitTestable(),
        findsOne,
        reason: 'the view toggle lives in the pinned app bar now (OPH-213)',
      );
      expect(
        find.byKey(const Key('home-quick-add')).hitTestable(),
        findsNothing,
        reason: 'the quick-add bar has to scroll away on phones',
      );
      // The app bar is the one thing that stays.
      expect(find.text('Home').hitTestable(), findsWidgets);
    },
  );

  testWidgets('typed quick-add text survives scrolling it out of view (H4)', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    for (var i = 0; i < 25; i++) {
      api.seedTask(title: 'İş ${i.toString().padLeft(2, '0')}');
    }
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'Yarım kalan',
    );
    await tester.pumpAndSettle();

    // Scroll it past the cache extent and back.
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    // This is what gives the test teeth: the bar is GONE from the tree, so the
    // text below can only have survived in the hoisted controller.
    expect(find.byKey(const Key('home-quick-add')), findsNothing);
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, 1200),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Yarım kalan'),
      findsOneWidget,
      reason: 'hoisted state: a disposed bar must not eat what was typed',
    );
  });

  testWidgets('on the phone board the toggle stays pinned (H3)', (
    tester,
  ) async {
    _phone(tester);
    await localKv.remove('alliswell_home_view');
    final api = FakeApi();
    for (var i = 0; i < 20; i++) {
      api.seedTask(title: 'Kart ${i.toString().padLeft(2, '0')}');
    }
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    // OPH-213: the view switch is an app-bar ICON now, not a labelled
    // segment — one tap, showing the view it will switch to.
    await tester.tap(find.byKey(const Key('home-view-toggle')));
    await tester.pumpAndSettle();
    addTearDown(() => localKv.remove('alliswell_home_view'));

    // Scroll the column's cards…
    await tester.drag(
      find.byKey(const Key('board-refresh-open')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    // …the way back to Liste is still there: a horizontal pager cannot carry
    // the toggle away with it.
    expect(
      find.byKey(const Key('home-view-toggle')).hitTestable(),
      findsOne,
      reason: 'scrolling the board away from its toggle would strand the user',
    );
  });

  testWidgets('wide layouts keep their pinned chrome and side calendar (H2)', (
    tester,
  ) async {
    _wide(tester);
    final api = FakeApi();
    for (var i = 0; i < 25; i++) {
      api.seedTask(title: 'İş ${i.toString().padLeft(2, '0')}');
    }
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('home-refresh')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    // Nothing moved: there is room up there, so the phone rule does not apply.
    expect(find.byKey(const Key('home-view-toggle')).hitTestable(), findsOne);
    expect(find.byKey(const Key('home-quick-add')).hitTestable(), findsOne);
    expect(find.byType(MonthCalendar).hitTestable(), findsOne);
  });

  testWidgets('search results are part of the one scroll view — and pullable', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    api.seedTask(title: 'Çay siparişi');
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('home-search')), 'cay');
    await tester.pump(const Duration(milliseconds: 400)); // search debounce
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-search-results')), findsOneWidget);

    // OPH-171 left search mode un-pullable (nested scrollable); slivers fix it.
    final before = _pulls(api);
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();
    expect(_pulls(api), greaterThan(before));
    expect(find.text('Çay siparişi'), findsOneWidget);
  });
  testWidgets(
    'the calendar toggle lives in the app bar too, and remembers (OPH-213)',
    (tester) async {
      _phone(tester);
      await localKv.remove('alliswell_home_view');
      await localKv.remove('alliswell_home_calendar_visible');
      final api = FakeApi()..seedTask(title: 'Tek iş');
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      // The old floating "Takvimi gizle" button is gone — one control, one place.
      expect(find.text('Hide calendar'), findsNothing);
      expect(find.text('Show calendar'), findsNothing);

      final toggle = find.byKey(const Key('toggle-calendar'));
      expect(toggle.hitTestable(), findsOne);
      expect(find.byType(MonthCalendar), findsOne);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsNothing);

      // (Persistence itself is `PersistedToggle`'s own test — re-pumping a fresh
      // ProviderScope over a live one here fights the LayoutBuilder, and proving
      // the same thing twice is not worth a flaky test.)
      addTearDown(() => localKv.remove('alliswell_home_calendar_visible'));
    },
  );
}
