import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_scroll_test.dart' show signedInApp;
import '../projects/fake_api.dart';

/// OPH-401 (polish 3 J-05): every Home section header spans the card column,
/// its chevron's 48 pt target ends on the cards' trailing edge — one control
/// axis for every section — the whole header is the one disclosure target,
/// and it announces expanded / collapsed.
void main() {
  String iso(DateTime d) => d.toUtc().toIso8601String();

  FakeApi seeded() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return FakeApi()
      ..seedTask(
        title: 'Gecikmiş iş',
        dueAt: iso(today.subtract(const Duration(days: 2, hours: -9))),
      )
      ..seedTask(
        title: 'Bugünkü iş',
        dueAt: iso(today.add(const Duration(hours: 23, minutes: 59))),
      )
      ..seedTask(title: 'Tarihsiz iş');
  }

  Finder headers() => find.byWidgetPredicate(
    (w) =>
        w is InkWell &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('home-section-'),
  );

  for (final width in [360.0, 402.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('chevrons share the cards\' trailing edge at ${width}pt, '
          '${scale}x', (tester) async {
        tester.view.physicalSize = Size(width, width > 1000 ? 900 : 874);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(await signedInApp(seeded()));
        await tester.pumpAndSettle();

        final cardRight = tester
            .getRect(
              find.ancestor(
                of: find.text('Tarihsiz iş'),
                matching: find.byType(Card),
              ),
            )
            .right;
        final found = headers().evaluate().toList();
        expect(found.length, greaterThanOrEqualTo(2));
        final rights = <double>{};
        for (final e in found) {
          final header = find.byWidget(e.widget);
          final rect = tester.getRect(header);
          expect(rect.right, closeTo(cardRight, 0.5));
          final target = find.descendant(
            of: header,
            matching: find.byKey(const Key('home-section-chevron')),
          );
          final t = tester.getRect(target);
          expect(t.width, greaterThanOrEqualTo(48));
          expect(t.height, greaterThanOrEqualTo(48));
          rights.add(t.right.roundToDouble());
          final glyph = tester.getRect(
            find.descendant(of: target, matching: find.byType(Icon)),
          );
          // The glyph is centred in its target, so it sits 12 pt inside the
          // card edge — the row badge's inset.
          expect(glyph.center.dx, closeTo(t.center.dx, 0.5));
        }
        expect(rights, {cardRight.roundToDouble()});
      });
    }
  }

  testWidgets('the whole header folds, chevron or title, and says its state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(await signedInApp(seeded()));
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('home-section-noDate'));
    SemanticsNode node() => tester.getSemantics(header);
    expect(node().flagsCollection.isExpanded, Tristate.isTrue);
    expect(node().flagsCollection.isButton, isTrue);
    expect(node().flagsCollection.isHeader, isTrue);
    expect(find.text('Tarihsiz iş'), findsOneWidget);

    // A tap on the title folds it…
    await tester.tap(
      find.descendant(of: header, matching: find.byType(Text)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Tarihsiz iş'), findsNothing);
    expect(node().flagsCollection.isExpanded, Tristate.isFalse);

    // …and a tap at the far right, on the chevron, opens it again.
    final r = tester.getRect(header);
    await tester.tapAt(Offset(r.right - 4, r.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('Tarihsiz iş'), findsOneWidget);
    expect(node().flagsCollection.isExpanded, Tristate.isTrue);
    handle.dispose();
  });
}
