import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_panel.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/fab_clearance.dart';
import 'package:alliswell/src/widgets/glass.dart';
import 'package:alliswell/src/widgets/status_views.dart';
import 'package:alliswell/src/widgets/tab_capsule.dart';

import '../projects/fake_api.dart';
import 'shell_harness.dart';

/// OPH-397 (ADR-0062 §3–§5, DESIGN §44) — what floats over a phone screen,
/// and the one grid it floats on.
///
///   • R-06: four edge insets (8/12/16 and the bubble's dock) and two
///     diameters — the "+" and the search orb were two circles 8 pt apart.
///   • R-07 / E-10: the microphone sat bottom-LEFT, on the section headers
///     and the column of check circles; a tap meant for a task opened the
///     microphone.
///   • R-03: content ran under the bar with nothing between them.
///   • R-12: Home went two-column at 720 while the shell kept the phone
///     capsule up to 800; on the desktop the microphone sat on the rail.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  final plus = find.byTooltip('shell.fabNewTask'.tr());
  final mic = find.byKey(const Key('ai-fab'));
  final capsule = find.byKey(const Key('tab-capsule'));
  final orb = find.ancestor(
    of: find.byKey(const Key('global-search-orb')),
    matching: find.byType(GlassSurface),
  );

  FakeApi aiApi({int tasks = 0}) {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    for (var i = 0; i < tasks; i++) {
      api.seedTask(
        title: 'Görev ${i.toString().padLeft(2, '0')}',
        // Two kinds of group, so there is more than one header to cover.
        dueAt: i.isEven
            ? DateTime(
                tomorrow.year,
                tomorrow.month,
                tomorrow.day,
                12,
              ).toUtc().toIso8601String()
            : null,
      );
    }
    return api;
  }

  Future<void> pumpPhone(
    WidgetTester tester,
    FakeApi api, {
    double width = 393,
    double height = 852,
    double bottomInset = 34,
    bool bubble = false,
  }) async {
    sizeTo(tester, Size(width, height));
    tester.view.padding = FakeViewPadding(top: 47, bottom: bottomInset);
    addTearDown(tester.view.resetPadding);
    final app = await teamApp(api);
    if (bubble) {
      await localKv.set('alliswell_quick_bubble_enabled', 'true');
    }
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  group('ADR-0062 §3/§4: one action cluster on one grid', () {
    for (final width in const [360.0, 393.0, 430.0]) {
      testWidgets('${width.toInt()} pt: mic and "+" on the right, centres '
          'aligned, "+" over the orb, 16 above the capsule', (tester) async {
        await pumpPhone(tester, aiApi(), width: width);
        final gutter = width >= 430 ? 20.0 : 16.0;
        final bar = tester.getRect(capsule);
        final search = tester.getRect(orb);
        final create = tester.getRect(plus);
        final voice = tester.getRect(mic);

        // The bar's row: capsule and orb on the gutter, 8 apart, one centre.
        expect(bar.left, moreOrLessEquals(gutter));
        expect(search.right, moreOrLessEquals(width - gutter));
        expect(search.left - bar.right, moreOrLessEquals(8));
        expect(search.size, const Size(56, 56));
        expect(search.center.dy, moreOrLessEquals(bar.center.dy));

        // The cluster: "+" 56 on the gutter, mic 48 beside it, one centre.
        expect(create.size, const Size(56, 56));
        expect(voice.size, const Size(48, 48));
        expect(create.right, moreOrLessEquals(width - gutter));
        expect(create.center.dx, moreOrLessEquals(search.center.dx));
        expect(create.bottom, moreOrLessEquals(bar.top - 16));
        expect(voice.center.dy, moreOrLessEquals(create.center.dy));
        expect(create.left - voice.right, moreOrLessEquals(8));
        // The bottom-left corner is empty.
        expect(voice.left, greaterThan(width / 2));
      });
    }

    testWidgets('without AI the "+" keeps the same place', (tester) async {
      await pumpPhone(tester, FakeApi());
      expect(mic, findsNothing);
      final bar = tester.getRect(capsule);
      final create = tester.getRect(plus);
      expect(create.right, moreOrLessEquals(393 - 16));
      expect(create.bottom, moreOrLessEquals(bar.top - 16));
    });
  });

  group('ADR-0062 §3: scrolling down lowers the cluster 16 pt', () {
    Future<TestGesture> scrollDown(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('home-scroll'))),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return gesture;
    }

    testWidgets('in 150 ms, and back on the way up', (tester) async {
      await pumpPhone(tester, aiApi(tasks: 30));
      final rest = tester.getRect(plus);
      final micRest = tester.getRect(mic);

      final gesture = await scrollDown(tester);
      await tester.pump(AwMotion.fast);
      expect(tester.getRect(plus).top, moreOrLessEquals(rest.top + 16));
      expect(tester.getRect(mic).top, moreOrLessEquals(micRest.top + 16));

      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(AwMotion.fast);
      expect(tester.getRect(plus).top, moreOrLessEquals(rest.top));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('it comes back once the scrolling stops', (tester) async {
      await pumpPhone(tester, aiApi(tasks: 30));
      final rest = tester.getRect(plus);
      final gesture = await scrollDown(tester);
      await tester.pump(AwMotion.fast);
      expect(tester.getRect(plus).top, moreOrLessEquals(rest.top + 16));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(tester.getRect(plus).top, moreOrLessEquals(rest.top));
    });

    testWidgets('with reduced motion it moves at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpPhone(tester, aiApi(tasks: 30));
      final rest = tester.getRect(plus);
      final gesture = await scrollDown(tester);
      await tester.pump();
      expect(tester.getRect(plus).top, moreOrLessEquals(rest.top + 16));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('R-03: a solid page-colour fade under the bar, not glass, '
      'and it takes no touches', (tester) async {
    await pumpPhone(tester, aiApi());
    final scrim = find.byKey(const Key('shell-bottom-scrim'));
    expect(scrim, findsOneWidget);
    final rect = tester.getRect(scrim);
    final bar = tester.getRect(capsule);
    expect(rect.bottom, 852);
    expect(rect.top, moreOrLessEquals(bar.top - 24));
    expect(rect.left, 0);
    expect(rect.right, 393);
    expect(
      find.descendant(of: scrim, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.ancestor(of: scrim, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    final box = tester.widget<DecoratedBox>(scrim);
    final gradient =
        (box.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last.a, greaterThanOrEqualTo(0.9));
  });

  group('Kabul: no floating object covers a check circle or a header', () {
    for (final width in const [360.0, 393.0]) {
      for (final bubble in [false, true]) {
        testWidgets('${width.toInt()} pt, bubble ${bubble ? 'on' : 'off'}', (
          tester,
        ) async {
          final api = aiApi(tasks: 30)
            ..seedQuickLink(
              kind: 'url',
              url: 'https://alliswell.space',
              title: 'Site',
            );
          await pumpPhone(tester, api, width: width, bubble: bubble);
          if (bubble) {
            expect(find.byType(QuickAccessBubble), findsOneWidget);
          }

          void check(String when) {
            final floating = <Rect>[
              tester.getRect(plus),
              tester.getRect(mic),
              tester.getRect(orb),
              tester.getRect(capsule),
              if (bubble) tester.getRect(find.byType(QuickAccessBubble)),
            ];
            final list = find.byKey(const Key('home-scroll'));
            final circles = find.descendant(
              of: list,
              matching: find.byType(Checkbox),
            );
            final headers = find.descendant(
              of: list,
              matching: find.textContaining(' · '),
            );
            expect(circles, findsWidgets);
            expect(headers, findsWidgets);
            final top = tester.getRect(capsule).top;
            var seen = 0;
            for (final target in [
              ...circles.evaluate(),
              ...headers.evaluate(),
            ]) {
              final rect = tester.getRect(find.byWidget(target.widget).first);
              // What has scrolled under the bar itself is the bar's to
              // cover; everything above it must be free.
              if (rect.bottom > top || rect.top < 0) continue;
              seen++;
              for (final thing in floating) {
                expect(
                  rect.overlaps(thing),
                  isFalse,
                  reason: '$when: $thing covers $rect',
                );
              }
            }
            expect(seen, greaterThanOrEqualTo(3), reason: when);
          }

          check('at rest');
          // The first task's check circle, by name.
          final first = tester.getRect(find.byType(Checkbox).first);
          expect(first.overlaps(tester.getRect(mic)), isFalse);
          await tester.drag(
            find.byKey(const Key('home-scroll')),
            const Offset(0, -420),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          check('scrolled');
        });
      }
    }
  });

  testWidgets('the list ends 24 pt above the "+" — bar + FAB + 24', (
    tester,
  ) async {
    await pumpPhone(tester, aiApi(tasks: 30));
    final list = find.byKey(const Key('home-scroll'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    // A lazy list only estimates its end until it has laid it out.
    for (var i = 0; i < 5; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    final cards = find.descendant(of: list, matching: find.byType(Card));
    // The scroll lowered the cluster; stillness brings it back.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final last = tester.getRect(cards.last);
    // 24 to the "+", less the card's own 3 px row rhythm.
    expect(
      last.bottom,
      moreOrLessEquals(tester.getRect(plus).top - 24 - 3, epsilon: 0.5),
    );
  });

  testWidgets('a page without the bar ends at the safe area + 24', (
    tester,
  ) async {
    late EdgeInsets padding;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(bottom: 34),
        ),
        child: Builder(
          builder: (context) {
            padding = awListPadding(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(padding.bottom, 34 + 24);
    expect(AwFabClearance.lane, 16 + 56);
  });

  testWidgets('a long press on the Home tab opens Quick Access', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedQuickLink(
        kind: 'url',
        url: 'https://alliswell.space',
        title: 'Site',
      );
    await pumpPhone(tester, api);
    expect(find.byType(QuickAccessBubble), findsNothing);
    await tester.longPress(find.byKey(const Key('tab-slot-0')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessPanel), findsOneWidget);
    expect(find.text('Site'), findsOneWidget);
  });

  testWidgets('R-12: 744 pt is one layout — Home stays single-column under '
      'the phone capsule', (tester) async {
    sizeTo(tester, const Size(744, 1133));
    await tester.pumpWidget(await teamApp(FakeApi()));
    await tester.pumpAndSettle();
    expect(find.byType(AwTabCapsule), findsOneWidget);
    expect(find.byKey(const Key('home-scroll')), findsOneWidget);
  });

  testWidgets('R-12: on the desktop the microphone keeps off the rail', (
    tester,
  ) async {
    sizeTo(tester, const Size(1280, 900));
    await tester.pumpWidget(await teamApp(aiApi()));
    await tester.pumpAndSettle();
    final rail = tester.getRect(
      find
          .ancestor(
            of: find.byType(NavigationRail),
            matching: find.byType(GlassSurface),
          )
          .first,
    );
    final voice = tester.getRect(mic);
    expect(voice.overlaps(rail), isFalse);
    expect(voice.center.dy, moreOrLessEquals(tester.getRect(plus).center.dy));
  });
}
