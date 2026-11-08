import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/home/month_calendar.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/ui/task_tile.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../../design_screenshots_test.dart'
    show loadRealFontsForStore, seededStoreApi, signedInStoreApp;
import '../projects/fake_api.dart';
import '../shell/shell_harness.dart';

/// OPH-401 (U-04, U-13, C-06, R-11; DESIGN §47) — Home's first screen on a
/// phone: the week strip in place of the month grid, section headers you can
/// fold, and a quick add that says what it did and can take it back.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  final capsule = find.byKey(const Key('tab-capsule'));
  final toggle = find.byKey(const Key('calendar-mode-toggle'));

  int dayCells() => find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('calendar-day-'),
      )
      .evaluate()
      .length;

  String iso(DateTime d) => d.toUtc().toIso8601String();
  DateTime at(int addDays, int h, int m) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + addDays, h, m);
  }

  /// The store set's Home (`design_screenshots_test._seededApi`), without
  /// projects and tags: one overdue, two today, two undated, two this week,
  /// two later.
  FakeApi demoApi() => FakeApi()
    ..seedTask(
      title: 'Review contrast report',
      priority: 'urgent',
      isUrgent: true,
      dueAt: iso(DateTime.now().subtract(const Duration(days: 1))),
    )
    ..seedTask(title: 'Sketch onboarding ideas')
    ..seedTask(title: 'Call the plumber about the leak')
    ..seedTask(
      title: 'Ship the new Liquid Glass theme',
      priority: 'high',
      dueAt: iso(at(0, 23, 58)),
    )
    ..seedTask(
      title: 'Evening 5k run',
      priority: 'low',
      dueAt: iso(at(0, 23, 59)),
    )
    ..seedTask(title: 'Water the plants', dueAt: iso(at(2, 9, 0)))
    ..seedTask(title: 'Book dentist appointment', dueAt: iso(at(3, 10, 0)))
    ..seedTask(title: 'Draft the Q3 planning doc', dueAt: iso(at(8, 12, 0)))
    ..seedTask(title: 'Read “Shape Up”, chapter 4', dueAt: iso(at(15, 20, 0)));

  Future<void> pump(
    WidgetTester tester,
    FakeApi api, {
    Size size = const Size(393, 852),
  }) async {
    sizeTo(tester, size);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPadding);
    await localKv.remove('alliswell_home_calendar_mode');
    await localKv.remove('alliswell_home_calendar_visible');
    await tester.pumpWidget(await teamApp(api));
    await tester.pumpAndSettle();
  }

  group('W1/W2: the week strip', () {
    testWidgets('a phone opens on the week strip; one tap gives the month, '
        'and the choice is kept', (tester) async {
      await pump(tester, FakeApi());
      expect(find.byType(MonthCalendar), findsOneWidget);
      expect(dayCells(), 7);
      expect(find.byTooltip('Show month'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(dayCells(), 42);
      expect(await localKv.get('alliswell_home_calendar_mode'), 'month');

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(dayCells(), 7);
      expect(await localKv.get('alliswell_home_calendar_mode'), 'week');
    });

    testWidgets('from 600 pt the grid stays the default', (tester) async {
      await pump(tester, FakeApi(), size: const Size(700, 1000));
      expect(dayCells(), 42);
      expect(await localKv.get('alliswell_home_calendar_mode'), isNull);
    });

    testWidgets('a stored "month" wins on a phone', (tester) async {
      sizeTo(tester, const Size(393, 852));
      await localKv.set('alliswell_home_calendar_mode', 'month');
      addTearDown(() => localKv.remove('alliswell_home_calendar_mode'));
      await tester.pumpWidget(await teamApp(FakeApi()));
      await tester.pumpAndSettle();
      expect(dayCells(), 42);
    });
  });

  group('S1–S3: section headers', () {
    Finder header(HomeBucket bucket) =>
        find.byKey(Key('home-section-${bucket.name}'));

    testWidgets('label and count are two texts: 15/20 w700, the count in '
        'onSurfaceVariant; Overdue keeps the page red, Today takes onSurface', (
      tester,
    ) async {
      await pump(tester, demoApi());
      final theme = buildAwTheme(Brightness.light);
      final scheme = Theme.of(tester.element(capsule)).colorScheme;
      final tokens = Theme.of(tester.element(capsule)).extension<AwTokens>()!;

      final overdue = tester.widget<Text>(
        find.descendant(
          of: header(HomeBucket.overdue),
          matching: find.text(HomeBucket.overdue.label),
        ),
      );
      expect(overdue.style!.fontSize, 15);
      expect(overdue.style!.fontWeight, FontWeight.w700);
      expect(overdue.style!.color, tokens.errorOnPage);
      final count = tester.widget<Text>(
        find.descendant(
          of: header(HomeBucket.overdue),
          matching: find.text('1'),
        ),
      );
      expect(count.style!.color, scheme.onSurfaceVariant);
      expect(
        count.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      final today = tester.widget<Text>(
        find.descendant(
          of: header(HomeBucket.today),
          matching: find.text(HomeBucket.today.label),
        ),
      );
      expect(today.style!.color, scheme.onSurface);
      expect(theme.brightness, Brightness.light);
      expect(
        tester.getSize(header(HomeBucket.today)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('a tap folds the section and says so; a second tap opens it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, demoApi());
      final run = find.text('Evening 5k run');
      expect(run.hitTestable(), findsOneWidget);
      expect(
        tester.getSemantics(header(HomeBucket.today)).label,
        'Collapse Today (2)',
      );

      await tester.tap(header(HomeBucket.today));
      await tester.pumpAndSettle();
      expect(run.hitTestable(), findsNothing);
      expect(
        tester.getSemantics(header(HomeBucket.today)).label,
        'Expand Today (2)',
      );
      // The other sections are untouched.
      expect(find.text('Review contrast report').hitTestable(), findsOne);

      await tester.tap(header(HomeBucket.today));
      await tester.pumpAndSettle();
      expect(run.hitTestable(), findsOneWidget);
      handle.dispose();
    });
  });

  group('Q6/Q7: what quick add says after a submit', () {
    testWidgets('"Added: {title} · {when}" with Undo; Undo takes it back', (
      tester,
    ) async {
      final api = FakeApi();
      await pump(tester, api);
      await tester.enterText(
        find.byKey(const Key('home-quick-add')),
        'Buy milk tomorrow 9am',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final toast = find.byKey(const Key('quick-add-added'));
      expect(toast, findsOneWidget);
      expect(find.textContaining('Added: Buy milk · '), findsOneWidget);
      expect(find.textContaining('9:00'), findsWidgets);
      expect(api.tasks.single['title'], 'Buy milk');

      // The new row is lit for a moment.
      final id = api.tasks.single['id'] as String;
      expect(find.byKey(Key('home-flash-$id')), findsOneWidget);
      // The field kept focus for the next one; its examples hint +Project.
      expect(
        find.descendant(
          of: find.byKey(const Key('quick-add-hints')),
          matching: find.text('+Work'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsNothing);
      expect(
        api.pushedMutations.any(
          (m) => m['operation'] == 'delete' && m['entityId'] == id,
        ),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a dateless task lands at the end of the list, and the list '
        'goes to it', (tester) async {
      final api = demoApi();
      for (var i = 0; i < 16; i++) {
        api.seedTask(
          title: 'Later ${i.toString().padLeft(2, '0')}',
          dueAt: iso(at(10 + i, 12, 0)),
        );
      }
      await pump(tester, api);
      await tester.enterText(
        find.byKey(const Key('home-quick-add')),
        'Kirayı öde',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Round 14's deadline ask; backing out keeps it dateless.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Added: Kirayı öde · No date'), findsOne);
      final row = find.ancestor(
        of: find.text('Kirayı öde'),
        matching: find.byType(TaskTile),
      );
      expect(row, findsOneWidget);
      final rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(tester.getRect(capsule).top));
      await tester.pump(const Duration(seconds: 6));
    });

    // P-04: the reveal only ever moved down, so a row that landed above a
    // list scrolled to its end was never built and never brought back.
    testWidgets('a task that lands above a list scrolled to its end — the '
        'list goes back up to it', (tester) async {
      final api = demoApi();
      for (var i = 0; i < 40; i++) {
        api.seedTask(
          title: 'Later ${i.toString().padLeft(2, '0')}',
          dueAt: iso(at(10 + i, 12, 0)),
        );
      }
      // Wide: the quick add is pinned above its own list, so it stays in
      // reach while the list sits at its end.
      await pump(tester, api, size: const Size(1200, 800));
      final list = find
          .byType(Scrollable)
          .evaluate()
          .map((e) {
            return (e as StatefulElement).state as ScrollableState;
          })
          .reduce(
            (a, b) => a.position.maxScrollExtent >= b.position.maxScrollExtent
                ? a
                : b,
          );
      expect(list.position.maxScrollExtent, greaterThan(1000));
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Review contrast report'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('home-quick-add')),
        'Buy milk tomorrow 9am',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.textContaining('Added: Buy milk · '), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Buy milk'),
        matching: find.byType(TaskTile),
      );
      expect(row, findsOneWidget);
      final viewport = tester.getRect(
        find.byWidget(list.widget).hitTestable().first,
      );
      final rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('Kabul', () {
    // The test font draws every glyph a full em wide ("Review contrast
    // report" takes two lines there, one on a phone), so the first screen is
    // measured as the store screenshots are: the repo's Roboto, the store
    // set's workspace.
    setUpAll(loadRealFontsForStore);

    Future<Rect> pumpStore(
      WidgetTester tester,
      Size size, {
      bool dateless = true,
    }) async {
      sizeTo(tester, size);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      for (final key in const [
        'alliswell_home_calendar_mode',
        'alliswell_home_calendar_visible',
        'alliswell_home_view',
      ]) {
        await localKv.remove(key);
      }
      final api = seededStoreApi();
      if (!dateless) api.tasks.removeWhere((t) => t['dueAt'] == null);
      await tester.pumpWidget(await signedInStoreApp(api));
      await tester.pumpAndSettle();
      final appBar = tester.getRect(find.byType(AppBar).first);
      // The bottom fade starts 24 above the capsule (DESIGN §44 F4).
      return Rect.fromLTRB(
        0,
        appBar.bottom,
        size.width,
        tester.getRect(capsule).top - 24,
      );
    }

    bool onFirstScreen(WidgetTester tester, Rect screen, Finder row) {
      if (row.evaluate().isEmpty) return false;
      final rect = tester.getRect(row);
      return rect.top >= screen.top && rect.bottom <= screen.bottom;
    }

    Finder rowOf(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(TaskTile));

    for (final size in const [Size(393, 852), Size(390, 844)]) {
      final name = '${size.width.toInt()}×${size.height.toInt()}';

      testWidgets('$name: Overdue + Today give at least three rows on the '
          'first screen', (tester) async {
        // The store set without its dateless rows: "No date" sits between
        // Overdue and Today by design (OPH-102), so this is the case where
        // the calendar alone decided whether Today was in sight.
        final screen = await pumpStore(tester, size, dateless: false);
        const urgent = [
          'Review contrast report',
          'Ship the new Liquid Glass theme',
          'Evening 5k run',
        ];
        final shown = urgent
            .where((t) => onFirstScreen(tester, screen, rowOf(t)))
            .length;
        expect(shown, 3);
      });

      testWidgets('$name: with the whole store set the list starts on the '
          'first screen: Overdue and at least two more rows', (tester) async {
        final screen = await pumpStore(tester, size);
        expect(
          onFirstScreen(tester, screen, rowOf('Review contrast report')),
          isTrue,
        );
        final rows = find.byType(TaskTile).evaluate().where((e) {
          final box = e.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          return rect.top >= screen.top && rect.bottom <= screen.bottom;
        });
        expect(rows.length, greaterThanOrEqualTo(3));
      });
    }
  });
}
