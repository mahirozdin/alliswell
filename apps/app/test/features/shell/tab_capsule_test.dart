import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sections.dart';
import 'package:alliswell/src/widgets/tab_capsule.dart';

import '../projects/fake_api.dart';
import 'shell_harness.dart';

/// OPH-396 (ADR-0062, DESIGN §43) — the phone's bottom navigation.
///
/// The measurement matrix the shell never had (R-01, R-02, R-04, R-13):
/// every phone width the probes used × text scale × language × theme ×
/// five or six sections. In every cell the capsule has at most five equal
/// slots ≥ 48 dp, every slot is labelled, every label stays inside the
/// capsule's curve, every glyph sits on one centre line, and the label's
/// text scaling stops at 1.3.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  Finder slot(int i) => find.byKey(Key('tab-slot-$i'));
  Finder labelIn(int i) => find.descendant(
    of: slot(i),
    matching: find.byKey(const Key('tab-label')),
  );
  Finder iconIn(int i) =>
      find.descendant(of: slot(i), matching: find.byType(Icon));

  const widths = [360.0, 375.0, 393.0, 412.0, 430.0];
  const scales = [1.0, 1.3, 2.0];

  for (final team in [false, true]) {
    for (final language in ['tr', 'en']) {
      final sections = team ? 6 : 5;
      testWidgets('matrix: $sections sections, $language — five equal '
          'slots ≥ 48, every label inside the capsule, one glyph line', (
        tester,
      ) async {
        AwI18n.instance.setActiveCached(Locale(language));
        sizeTo(tester, const Size(393, 852));
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(await teamApp(team ? teamApi() : FakeApi()));
        await tester.pumpAndSettle();

        for (final brightness in Brightness.values) {
          for (final width in widths) {
            for (final scale in scales) {
              final cell = '${width.toInt()} × $scale × ${brightness.name}';
              tester.view.physicalSize = Size(width, 852);
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              tester.platformDispatcher.platformBrightnessTestValue =
                  brightness;
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: cell);

              final capsule = tester.getRect(
                find.byKey(const Key('tab-capsule')),
              );
              expect(capsule.height, kAwTabCapsuleHeight, reason: cell);
              final curve = RRect.fromRectAndRadius(
                capsule,
                const Radius.circular(32),
              ).deflate(2);

              expect(slot(4), findsOneWidget, reason: cell);
              expect(slot(5), findsNothing, reason: '$cell: ≤ 5 slots');
              final first = tester.getRect(slot(0));
              final glyphLine = tester.getCenter(iconIn(0)).dy;
              for (var i = 0; i < 5; i++) {
                final box = tester.getRect(slot(i));
                expect(
                  box.width,
                  greaterThanOrEqualTo(kAwMinTabSlot - 0.01),
                  reason: '$cell: slot $i under 48 dp (G4)',
                );
                expect(box.width, moreOrLessEquals(first.width), reason: cell);
                expect(box.height, greaterThanOrEqualTo(48), reason: cell);

                expect(labelIn(i), findsOneWidget, reason: '$cell: label $i');
                final label = tester.getRect(labelIn(i));
                for (final corner in [
                  label.topLeft,
                  label.topRight,
                  label.bottomLeft,
                  label.bottomRight,
                ]) {
                  expect(
                    curve.contains(corner),
                    isTrue,
                    reason: '$cell: label $i leaves the capsule at $corner',
                  );
                }
                expect(
                  label.left >= box.left - 0.01 &&
                      label.right <= box.right + 0.01,
                  isTrue,
                  reason: '$cell: label $i runs into its neighbour',
                );

                expect(
                  tester.getCenter(iconIn(i)).dy,
                  moreOrLessEquals(glyphLine, epsilon: 0.5),
                  reason: '$cell: glyph $i is off the line (R-01)',
                );

                final text = tester.widget<Text>(labelIn(i));
                expect(text.maxLines, 1, reason: cell);
                expect(
                  text.textScaler!.scale(kAwTabLabelSize),
                  lessThanOrEqualTo(
                    kAwTabLabelSize * kAwTabLabelMaxScale + 0.01,
                  ),
                  reason: '$cell: the label scale is clamped at 1.3',
                );
              }
              final selection = tester.getRect(
                find.byKey(const Key('tab-selection')),
              );
              expect(selection.height, kAwTabSelectionHeight, reason: cell);
              expect(
                selection.left >= first.left - 0.01 &&
                    selection.right <= first.right + 0.01 &&
                    selection.top >= capsule.top &&
                    selection.bottom <= capsule.bottom,
                isTrue,
                reason: '$cell: the selection leaves its slot',
              );
            }
          }
        }
      });
    }
  }

  testWidgets('selecting a tab moves nothing — not the glyphs, not the '
      'labels', (tester) async {
    sizeTo(tester, const Size(393, 852));
    await tester.pumpWidget(await teamApp(FakeApi()));
    await tester.pumpAndSettle();

    List<Rect> geometry() => [
      for (var i = 0; i < 5; i++) ...[
        tester.getRect(iconIn(i)),
        tester.getRect(labelIn(i)),
      ],
    ];
    final before = geometry();
    await tester.tap(slot(2));
    await tester.pumpAndSettle();
    expect(appRouter().state.uri.path, '/projects');
    final after = geometry();
    for (var i = 0; i < before.length; i++) {
      expect(after[i], before[i]);
    }
  });

  testWidgets('semantics: one button per tab, selected, "Tab 2 of 5"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    sizeTo(tester, const Size(393, 852));
    await tester.pumpWidget(await teamApp(FakeApi()));
    await tester.pumpAndSettle();

    final home = tester.getSemantics(slot(0));
    expect(home.label, 'Home\nTab 1 of 5');
    expect(home.flagsCollection.isSelected, Tristate.isTrue);
    expect(home.flagsCollection.isButton, isTrue);
    final inbox = tester.getSemantics(slot(1));
    expect(inbox.label, 'Inbox\nTab 2 of 5');
    expect(inbox.flagsCollection.isSelected, Tristate.isFalse);

    await tester.tap(slot(1));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(slot(1)).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('a sixth section makes the fifth slot "More", which opens '
      'the rest and marks itself while one of them is open', (tester) async {
    sizeTo(tester, const Size(360, 800));
    await tester.pumpWidget(await teamApp(teamApi()));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: slot(4), matching: find.text('More')),
      findsOneWidget,
    );
    await tester.tap(slot(4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-more-sheet')), findsOneWidget);
    expect(find.byKey(const Key('nav-more-files')), findsOneWidget);
    expect(find.byKey(const Key('nav-more-tickets')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-more-tickets')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-more-sheet')), findsNothing);
    expect(appRouter().state.uri.path, '/tickets');
    expect(
      find.descendant(
        of: slot(4),
        matching: find.byKey(const Key('tab-selection')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('above 1.3× text a long press names the tab in a large '
      'bubble, and lifting the finger selects it', (tester) async {
    sizeTo(tester, const Size(393, 852));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(await teamApp(FakeApi()));
    await tester.pumpAndSettle();

    final bubble = find.byKey(const Key('tab-capsule-large-label'));
    final gesture = await tester.startGesture(tester.getCenter(slot(3)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(of: bubble, matching: find.text('Notes')),
      findsOneWidget,
    );
    final box = tester.getRect(bubble);
    expect(
      box.bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('tab-capsule'))).top,
      ),
      reason: 'the bubble sits above the capsule, not over the finger',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bubble, findsNothing);
    expect(appRouter().state.uri.path, '/notes');
  });

  testWidgets('at 1.0× a long press shows no bubble', (tester) async {
    sizeTo(tester, const Size(393, 852));
    await tester.pumpWidget(await teamApp(FakeApi()));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(slot(3)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.byKey(const Key('tab-capsule-large-label')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('phoneTabLayout', () {
    test('five or fewer sections: every one is a slot', () {
      final visible = visibleAppSections(itsm: false);
      final layout = phoneTabLayout(visible);
      expect(layout.direct, visible);
      expect(layout.overflow, isEmpty);
    });

    test('six: the first four keep a slot, the rest go behind "More"', () {
      final layout = phoneTabLayout(visibleAppSections(itsm: true));
      expect(layout.direct, hasLength(kAwMaxPhoneTabs - 1));
      expect(layout.overflow, [AppSection.files, AppSection.tickets]);
    });
  });
}
