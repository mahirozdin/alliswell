import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/search/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-398 (ADR-0062 §6, R-05, C-03): the phone's Home app bar carries at
/// most three targets — ⚡, "View ⌄", Settings. The local search magnifier
/// is gone from the bar (one glyph, one meaning: the orb is the search); the
/// local filter is a field the list reveals when pulled down.
Future<Widget> _app(FakeApi api) async {
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

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Finder get _appBar => find.byType(AppBar);

/// The tappable things in the app bar's action row. A PopupMenuButton draws
/// an IconButton inside itself — count the outermost control only.
List<Element> _targets(WidgetTester tester) {
  final all = find
      .descendant(
        of: _appBar,
        matching: find.byWidgetPredicate(
          (w) => w is IconButton || w is PopupMenuButton,
        ),
      )
      .evaluate()
      .toList();
  bool nested(Element e) {
    var inside = false;
    e.visitAncestorElements((a) {
      if (all.contains(a)) inside = true;
      return !inside;
    });
    return inside;
  }

  return [
    for (final e in all)
      if (!nested(e)) e,
  ];
}

Future<void> _openViewMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-view-menu')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.remove('alliswell_home_view');
    await localKv.remove('alliswell_home_calendar_visible');
  });
  tearDown(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.remove('alliswell_home_view');
    await localKv.remove('alliswell_home_calendar_visible');
  });

  const widths = [360.0, 375.0, 393.0, 430.0];
  const scales = [1.0, 1.3, 2.0];

  for (final language in ['tr', 'en']) {
    testWidgets('matrix ($language): ≤ 3 targets, no magnifier in the bar, '
        'the title is never cut — list and board', (tester) async {
      AwI18n.instance.setActiveCached(Locale(language));
      _size(tester, const Size(393, 852));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(await _app(FakeApi()..seedTask(title: 'Bir')));
      await tester.pumpAndSettle();
      final title = language == 'tr' ? 'Ana Sayfa' : 'Home';

      for (final board in [false, true]) {
        if (board) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.0;
          tester.view.physicalSize = const Size(393, 852);
          await tester.pumpAndSettle();
          await _openViewMenu(tester);
          await tester.tap(find.byKey(const Key('home-view-board')));
          await tester.pumpAndSettle();
        }
        for (final width in widths) {
          for (final scale in scales) {
            final cell =
                '${board ? 'board' : 'list'} ${width.toInt()} × $scale';
            tester.view.physicalSize = Size(width, 852);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: cell);

            final targets = _targets(tester);
            expect(targets.length, lessThanOrEqualTo(3), reason: cell);
            for (final t in targets) {
              final size = (t.renderObject! as RenderBox).size;
              expect(size.width, greaterThanOrEqualTo(48), reason: cell);
              expect(size.height, greaterThanOrEqualTo(48), reason: cell);
            }
            expect(
              find.descendant(of: _appBar, matching: find.byIcon(Icons.search)),
              findsNothing,
              reason: '$cell: the orb is the one magnifier (ADR-0055)',
            );
            expect(find.byKey(const Key('search-open')), findsNothing);

            final titleText = find.descendant(
              of: _appBar,
              matching: find.text(title),
            );
            expect(titleText, findsOneWidget, reason: cell);
            final paragraph = tester.renderObject<RenderParagraph>(titleText);
            expect(paragraph.didExceedMaxLines, isFalse, reason: cell);
            final titleRect = tester.getRect(titleText);
            for (final t in targets) {
              final r = (t.renderObject! as RenderBox);
              final left = r.localToGlobal(Offset.zero).dx;
              expect(
                titleRect.right,
                lessThanOrEqualTo(left + 0.5),
                reason: '$cell: the title runs under an action',
              );
            }
          }
        }
      }
    });
  }

  testWidgets('the View menu carries list/board, the calendar and the order', (
    tester,
  ) async {
    _size(tester, const Size(393, 852));
    await tester.pumpWidget(await _app(FakeApi()..seedTask(title: 'Bir')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AllisWellApp)),
    );

    // Labelled for a screen reader and a long press.
    expect(
      find.byTooltip('View'),
      findsOneWidget,
      reason: 'the View button says what it is',
    );

    await _openViewMenu(tester);
    expect(find.byKey(const Key('home-view-list')), findsOneWidget);
    expect(find.byKey(const Key('home-view-board')), findsOneWidget);
    expect(find.byKey(const Key('toggle-calendar')), findsOneWidget);
    expect(find.byKey(const Key('sort-option-priority')), findsOneWidget);
    expect(find.byKey(const Key('sort-reverse')), findsOneWidget);

    // Calendar off — and the selection goes with it, as before (§16).
    expect(find.byType(MonthCalendar), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-calendar')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsNothing);

    // Order by priority.
    await _openViewMenu(tester);
    await tester.tap(find.byKey(const Key('sort-option-priority')));
    await tester.pumpAndSettle();
    expect(container.read(tasksSortProvider), startsWith('priority'));

    // Board: the menu now offers the columns editor, not the order.
    await _openViewMenu(tester);
    await tester.tap(find.byKey(const Key('home-view-board')));
    await tester.pumpAndSettle();
    await _openViewMenu(tester);
    expect(find.byKey(const Key('board-edit-columns')), findsOneWidget);
    expect(find.byKey(const Key('sort-option-priority')), findsNothing);
    await tester.tap(find.byKey(const Key('home-view-list')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsNothing);
    expect(find.byKey(const Key('home-quick-add')), findsOneWidget);
  });

  testWidgets('the filter field waits above the list; a pull reveals it', (
    tester,
  ) async {
    _size(tester, const Size(393, 852));
    final api = FakeApi()..seedTask(title: 'Çay siparişi');
    for (var i = 0; i < 3; i++) {
      api.seedTask(title: 'İş $i');
    }
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AllisWellApp)),
    );

    final field = find.byKey(const Key('home-search'));
    // At rest the list starts at the quick add; the field is scrolled away.
    expect(field.hitTestable(), findsNothing);
    expect(find.byKey(const Key('home-quick-add')).hitTestable(), findsOne);

    // A short pull reveals it — and only reveals it (no refresh started).
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(field.hitTestable(), findsOneWidget);
    // Its glyph is a filter, not a second magnifier beside the orb.
    expect(
      find.descendant(of: field, matching: find.byIcon(Icons.filter_list)),
      findsOneWidget,
    );

    await tester.enterText(field, 'cay');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(container.read(homeSearchQueryProvider), 'cay');
    expect(find.byKey(const Key('home-search-results')), findsOneWidget);
    expect(find.text('Çay siparişi'), findsOneWidget);

    // Clearing restores the list exactly (S5).
    await tester.tap(find.byKey(const Key('home-search-clear')));
    await tester.pumpAndSettle();
    expect(container.read(homeSearchQueryProvider), isEmpty);
    expect(find.byKey(const Key('home-search-results')), findsNothing);
    expect(find.text('İş 0'), findsOneWidget);
  });

  testWidgets('the filter is hidden at rest even when the list is short', (
    tester,
  ) async {
    _size(tester, const Size(393, 852));
    await tester.pumpWidget(await _app(FakeApi()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-search')).hitTestable(), findsNothing);
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-search')).hitTestable(), findsOne);
  });

  testWidgets('focusing the quick add leaves the filter where it rests', (
    tester,
  ) async {
    _size(tester, const Size(393, 852));
    await tester.pumpWidget(await _app(FakeApi()..seedTask(title: 'Bir')));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byKey(const Key('home-quick-add')));
    await tester.tap(find.byKey(const Key('home-quick-add')));
    await tester.pumpAndSettle();
    // A full-view bar is not "kept visible" by scrolling: the list stays put
    // and the field above it stays out of sight.
    expect(tester.getRect(find.byKey(const Key('home-quick-add'))), before);
    expect(find.byKey(const Key('home-search')).hitTestable(), findsNothing);
  });

  testWidgets('wide layouts keep their bar as it was', (tester) async {
    _size(tester, const Size(1280, 900));
    await tester.pumpWidget(await _app(FakeApi()..seedTask(title: 'Bir')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-view-menu')), findsNothing);
    expect(find.byKey(const Key('search-open')), findsOneWidget);
    expect(find.byKey(const Key('home-view-toggle')), findsOneWidget);
  });
}
