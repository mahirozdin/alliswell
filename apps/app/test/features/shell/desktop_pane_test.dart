import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/home/home_board.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/search/search_recents.dart';

import '../projects/fake_api.dart';
import 'shell_harness.dart';

/// OPH-405 (U-08, DESIGN §51) — the desktop at 1440: the rail on every
/// signed-in page, a task opened beside its list (Esc closes, ↑/↓ walk the
/// list), N and "/" as shortcuts, and a board whose columns fit the window
/// and scroll sideways past four.
void main() {
  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.remove(kSearchRecentsKey);
  });

  const desktop = Size(1440, 900);
  final pane = find.byKey(const Key('list-detail-pane'));
  final railFrame = find.byKey(const Key('rail-frame'));

  /// A personal account (the hosted address: no service desk), three open
  /// tasks due one after the other so Home lists them Alpha, Beta, Gamma.
  Future<FakeApi> pumpApp(
    WidgetTester tester, {
    Size size = desktop,
    void Function(FakeApi api)? seed,
  }) async {
    sizeTo(tester, size);
    final api = FakeApi();
    if (seed != null) {
      seed(api);
    } else {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      for (final (i, title) in const ['Alpha', 'Beta', 'Gamma'].indexed) {
        api.seedTask(
          title: title,
          dueAt: DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            9 + i,
          ).toUtc().toIso8601String(),
        );
      }
    }
    await tester.pumpWidget(
      await teamApp(api, serverUrl: 'https://api.example.com'),
    );
    await tester.pumpAndSettle();
    return api;
  }

  /// The title the pane is showing (its editable title field).
  String? paneTitle(WidgetTester tester) {
    final fields = find.descendant(of: pane, matching: find.byType(TextField));
    if (fields.evaluate().isEmpty) return null;
    return tester.widget<TextField>(fields.first).controller?.text;
  }

  Finder listRow(String title) => find
      .descendant(
        of: find.byKey(const Key('shell-content')),
        matching: find.text(title),
      )
      .first;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('a task opens in a 480 px pane beside the list: the rail and '
      'the list stay, the address stays Home', (tester) async {
    await pumpApp(tester);
    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();

    expect(pane, findsOneWidget);
    expect(tester.getSize(pane).width, 480);
    expect(paneTitle(tester), 'Alpha');
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(listRow('Beta'), findsOneWidget);
    expect(appRouter().state.uri.path, '/home');
    // The pane sits at the window's right edge, the list left of it.
    expect(tester.getTopRight(pane).dx, lessThanOrEqualTo(desktop.width));
    expect(
      tester.getTopRight(listRow('Beta')).dx,
      lessThan(tester.getTopLeft(pane).dx),
    );
    // The floating "+" stands left of the pane, not on it.
    final fab = find.byKey(const Key('shell-fab-cluster'));
    final plus = fab.evaluate().isEmpty
        ? find.byType(FloatingActionButton)
        : fab;
    expect(
      tester.getTopRight(plus.first).dx,
      lessThanOrEqualTo(tester.getTopLeft(pane).dx),
    );
  });

  testWidgets('↓ and ↑ open the next and previous task of the list; Esc '
      'closes the pane', (tester) async {
    await pumpApp(tester);
    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(paneTitle(tester), 'Beta');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(paneTitle(tester), 'Gamma');
    // At the end it stays.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(paneTitle(tester), 'Gamma');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(paneTitle(tester), 'Beta');

    await press(tester, LogicalKeyboardKey.escape);
    expect(pane, findsNothing);
    expect(appRouter().state.uri.path, '/home');
  });

  testWidgets('completing the open task from the pane, ↓ still opens the '
      'one after it', (tester) async {
    await pumpApp(tester);
    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: pane, matching: find.byTooltip('task.complete'.tr())),
    );
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(paneTitle(tester), 'Beta');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('in the title field the arrows are the caret\'s and the first '
      'Esc only leaves the field', (tester) async {
    await pumpApp(tester);
    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();
    final title = find.descendant(of: pane, matching: find.byType(TextField));
    await tester.tap(title.first);
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(paneTitle(tester), 'Alpha');
    await press(tester, LogicalKeyboardKey.escape);
    expect(pane, findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );
    await press(tester, LogicalKeyboardKey.escape);
    expect(pane, findsNothing);
  });

  testWidgets('a title typed just before another task opens, or the pane '
      'closes, is saved', (tester) async {
    // E35 G-C review r1: the autosave waits 1.5 s; switching tasks inside
    // that pause disposed the detail and dropped the edit.
    await pumpApp(tester);
    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();
    final title = find.descendant(of: pane, matching: find.byType(TextField));
    await tester.enterText(title.first, 'Alpha renamed');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(listRow('Beta'));
    await tester.pumpAndSettle();
    expect(paneTitle(tester), 'Beta');

    await tester.tap(listRow('Alpha renamed'));
    await tester.pumpAndSettle();
    expect(paneTitle(tester), 'Alpha renamed');

    await tester.enterText(title.first, 'Alpha again');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('task-pane-close')));
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
    expect(listRow('Alpha again'), findsOneWidget);
  });

  testWidgets('the pane\'s close button and a delete both close it; a '
      'section switch does too', (tester) async {
    await pumpApp(tester);
    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-pane-close')));
    await tester.pumpAndSettle();
    expect(pane, findsNothing);

    await tester.tap(listRow('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-delete')));
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
    expect(appRouter().state.uri.path, '/home');
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(listRow('Gamma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('nav.projects'.tr()).last);
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
  });

  testWidgets('a task opened in the pane, by a tap or by ↓, is a recent '
      'item in search (P-07)', (tester) async {
    final api = await pumpApp(tester);
    String idOf(String title) =>
        api.tasks.firstWhere((t) => t['title'] == title)['id'] as String;

    await tester.tap(listRow('Alpha'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(paneTitle(tester), 'Beta');
    await press(tester, LogicalKeyboardKey.escape);
    expect(pane, findsNothing);
    // The address never left Home — the visits are the pane's own.
    expect(appRouter().state.uri.path, '/home');

    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pumpAndSettle();
    final beta = find.byKey(Key('global-search-task-${idOf('Beta')}'));
    final alpha = find.byKey(Key('global-search-task-${idOf('Alpha')}'));
    expect(beta, findsOneWidget);
    expect(alpha, findsOneWidget);
    // Most recent first.
    expect(tester.getTopLeft(beta).dy, lessThan(tester.getTopLeft(alpha).dy));
    expect(
      find.byKey(Key('global-search-task-${idOf('Gamma')}')),
      findsNothing,
    );
    await press(tester, LogicalKeyboardKey.escape);
  });

  testWidgets('below the desktop width a task still opens as its own page', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1000, 900));
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
    expect(appRouter().state.uri.path, startsWith('/tasks/'));
    // …and that page has no second rail.
    expect(railFrame, findsNothing);
  });

  testWidgets('Settings and a task opened by its address keep the rail at '
      '1440; a destination goes to its section', (tester) async {
    final api = await pumpApp(tester);
    appRouter().push('/settings');
    await tester.pumpAndSettle();
    expect(railFrame, findsOneWidget);
    expect(
      find.descendant(of: railFrame, matching: find.byType(NavigationRail)),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: railFrame, matching: find.text('nav.notes'.tr())),
    );
    await tester.pumpAndSettle();
    expect(appRouter().state.uri.path, '/notes');

    appRouter().push('/tasks/${api.tasks.first['id']}');
    await tester.pumpAndSettle();
    expect(railFrame, findsOneWidget);
  });

  testWidgets('N opens the new-task form, "/" opens search — and neither '
      'fires while typing', (tester) async {
    await pumpApp(tester);
    final form = find.byKey(const Key('task-sheet-title'));
    final palette = find.byKey(const Key('global-search-field'));

    await press(tester, LogicalKeyboardKey.keyN);
    expect(form, findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(form, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pumpAndSettle();
    expect(palette, findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(palette, findsNothing);

    // In Home's quick-add field both are characters.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('home-quick-add')),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pumpAndSettle();
    expect(form, findsNothing);
    expect(palette, findsNothing);
  });

  group('board', () {
    setUp(() async {
      await localKv.set('alliswell_home_view', 'board');
    });
    tearDown(() async {
      await localKv.remove('alliswell_home_view');
      await localKv.remove('alliswell_board_columns');
    });

    Finder column(String status) => find.byKey(Key('board-column-$status'));
    final fade = find.byKey(const Key('board-edge-fade'));

    void seed(FakeApi api) {
      api.seedTask(title: 'Open one');
      api.seedTask(title: 'Going', status: 'in_progress');
      api.seedTask(title: 'Parked', status: 'waiting');
      api.seedTask(title: 'Done one', status: 'completed');
      api.seedTask(title: 'Dropped', status: 'cancelled');
    }

    testWidgets('four columns share the width at 1440 — the fourth is not '
        'cut — and none is narrower than 260', (tester) async {
      await pumpApp(tester, seed: seed);
      expect(column('completed'), findsOneWidget);
      expect(
        tester.getTopRight(column('completed')).dx,
        lessThanOrEqualTo(desktop.width),
      );
      expect(
        tester.getSize(column('open')).width,
        greaterThanOrEqualTo(kBoardMinColumnWidth - 2 * 4),
      );
      expect(fade, findsNothing);
      expect(boardColumnWidth(600), kBoardMinColumnWidth);
      expect(boardColumnWidth(1200), 300);
    });

    testWidgets('a fifth column scrolls sideways under a visible bar, the '
        'edge with more fades, and the fade goes at the end', (tester) async {
      await localKv.set(
        'alliswell_board_columns',
        'open,in_progress,waiting,completed,cancelled',
      );
      await pumpApp(tester, seed: seed);
      final scroller = find.byKey(const Key('board-columns'));
      expect(scroller, findsOneWidget);
      final bar = tester.widget<Scrollbar>(
        find.ancestor(of: scroller, matching: find.byType(Scrollbar)).first,
      );
      expect(bar.thumbVisibility, isTrue);
      expect(fade, findsOneWidget);

      await tester.drag(scroller, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(column('cancelled'), findsOneWidget);
      expect(
        tester.getTopRight(column('cancelled')).dx,
        lessThanOrEqualTo(desktop.width),
      );
      expect(fade, findsNothing);
    });

    testWidgets('a card opens in the pane and the board keeps its columns', (
      tester,
    ) async {
      await pumpApp(tester, seed: seed);
      await tester.tap(find.text('Going'));
      await tester.pumpAndSettle();
      expect(pane, findsOneWidget);
      expect(paneTitle(tester), 'Going');
      expect(find.byKey(const Key('board-columns')), findsOneWidget);
      expect(find.byKey(const Key('board-pager')), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(paneTitle(tester), 'Parked');
    });
  });
}
