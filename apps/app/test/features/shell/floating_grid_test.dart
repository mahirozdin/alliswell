import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_panel.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';
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

  // From 1200 the tooltip also names the N key (OPH-405).
  final plus = find.byWidgetPredicate(
    (w) =>
        w is Tooltip &&
        (w.message == 'shell.fabNewTask'.tr() ||
            w.message == 'shell.fabNewTaskShortcut'.tr()),
  );
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

  // OPH-397 (polish 4, T-01): the cluster no longer only steps down 16 pt —
  // it went on covering the right end of the rows a reader scrolls past and
  // the last visible title. While the list scrolls down it retracts, while
  // the keyboard is up it is gone; scrolling back up or 600 ms of stillness
  // brings it back.
  group('T-01: the cluster retracts while a list scrolls down', () {
    final veil = find.byKey(const Key('shell-fab-retract'));

    /// Retracted = takes no touch, says nothing — and, once its 150 ms are
    /// over, drawn at nothing (checked by every caller that has waited).
    bool retracting(WidgetTester tester) {
      final ignoring = tester.widget<IgnorePointer>(veil).ignoring;
      final silent = tester
          .widget<ExcludeSemantics>(
            find
                .descendant(of: veil, matching: find.byType(ExcludeSemantics))
                .first,
          )
          .excluding;
      if (ignoring != silent) fail('touch and semantics disagree');
      return ignoring;
    }

    bool retracted(WidgetTester tester) {
      final ignoring = retracting(tester);
      final drawn = tester.getRect(plus);
      if (ignoring) {
        expect(drawn.width, lessThan(0.5), reason: 'still drawn: $drawn');
      }
      return ignoring;
    }

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
      expect(retracted(tester), isFalse);

      // Step by step, so the motion is caught where it begins.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('home-scroll'))),
      );
      for (var i = 0; i < 8 && !retracting(tester); i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 1));
      }
      // Partway through it is still on its way out, not snapped.
      await tester.pump(const Duration(milliseconds: 30));
      final half = tester.getRect(plus).width;
      expect(half, greaterThan(1));
      expect(half, lessThan(56));
      await tester.pump(AwMotion.fast);
      expect(retracted(tester), isTrue);
      expect(tester.getRect(mic).width, lessThan(0.5));

      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(AwMotion.fast);
      expect(retracted(tester), isFalse);
      expect(tester.getRect(plus), rectMoreOrLessEquals(rest));
      expect(tester.getRect(mic), rectMoreOrLessEquals(micRest));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('it comes back once the scrolling stops', (tester) async {
      await pumpPhone(tester, aiApi(tasks: 30));
      final rest = tester.getRect(plus);
      final gesture = await scrollDown(tester);
      await tester.pump(AwMotion.fast);
      expect(retracted(tester), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(retracted(tester), isFalse);
      expect(tester.getRect(plus), rectMoreOrLessEquals(rest));
    });

    testWidgets('with reduced motion it goes and comes at once', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpPhone(tester, aiApi(tasks: 30));
      final gesture = await scrollDown(tester);
      await tester.pump();
      expect(retracted(tester), isTrue);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await tester.pump();
      expect(retracted(tester), isFalse);
      expect(tester.getRect(plus).width, moreOrLessEquals(56));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('while the keyboard is up the cluster is gone, and it '
        'returns when the keyboard closes', (tester) async {
      await pumpPhone(tester, aiApi(tasks: 4));
      final rest = tester.getRect(plus);
      expect(retracted(tester), isFalse);

      // ios/24 (polish 4): the quick add focused, the keyboard up — the
      // microphone and "+" stood on the calendar and "Geciken 11"'s arrow.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(AwMotion.fast);
      expect(retracted(tester), isTrue);
      // A pause while typing does not bring it back.
      await tester.pump(const Duration(seconds: 1));
      expect(retracted(tester), isTrue);

      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump(AwMotion.fast);
      expect(retracted(tester), isFalse);
      expect(tester.getRect(plus), rectMoreOrLessEquals(rest));
    });

    testWidgets('a retracted "+" takes no tap', (tester) async {
      await pumpPhone(tester, aiApi(tasks: 4));
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(AwMotion.fast);
      // The "+" ends the cluster: its centre is 28 in from the slot's
      // corner, wherever the keyboard put the slot.
      await tester.tapAt(
        tester.getRect(veil).bottomRight - const Offset(28, 28),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskCreateSheet), findsNothing);
      // The control: back in place, the same tap opens the sheet.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getRect(veil).bottomRight - const Offset(28, 28),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskCreateSheet), findsOneWidget);
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
            // OPH-401: a header is a name + a count, keyed by section.
            final headers = find.descendant(
              of: list,
              matching: find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'home-section-',
                    ),
              ),
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
