import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/ui/project_badge.dart';
import 'package:alliswell/src/features/projects/ui/project_edit_sheet.dart';
import 'package:alliswell/src/theme/tokens.dart';

void main() {
  // Polish 3 J-03: the label is never cut; [fits] decides badge or meta.
  group('ProjectBadge.fits', () {
    Future<bool> fitsAt(WidgetTester tester, String name, double scale) async {
      late bool result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                result = ProjectBadge.fits(context, name);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return result;
    }

    testWidgets('a short name fits, a long one does not, a larger text '
        'size moves the line', (tester) async {
      expect(await fitsAt(tester, 'Ev', 1.0), isTrue);
      expect(await fitsAt(tester, 'Launch AllisWell', 1.0), isFalse);
      expect(await fitsAt(tester, 'Ev', 6.0), isFalse);
    });
  });

  group('ProjectBadge.legibleColors clears WCAG AA (4.5:1)', () {
    // The full set of colors a user can pick: the quick palette plus the
    // color-grid (Material primaries + the three neutrals in the grid).
    final gridColors = <Color>[
      for (final swatch in kProjectPalette) colorFromRgbHex(swatch),
      for (final primary in Colors.primaries) primary,
      Colors.blueGrey.shade700,
      Colors.brown.shade600,
      Colors.grey.shade700,
      const Color(0xFFFFFFFF), // pure white (extreme)
      const Color(0xFF000000), // pure black (extreme)
      const Color(0xFF808080), // mid grey (near the dead zone)
    ];

    for (final base in gridColors) {
      test('$base label ≥ 4.5:1', () {
        final (:fill, :ink) = ProjectBadge.legibleColors(base);
        expect(
          awContrastRatio(ink, fill),
          greaterThanOrEqualTo(4.5),
          reason: 'ink on the (possibly nudged) fill must be AA',
        );
      });
    }

    test('leaves easy colors untouched but nudges the dead-zone violet', () {
      // Blue #2563EB is comfortably dark → unchanged, white ink.
      final blue = ProjectBadge.legibleColors(const Color(0xFF2563EB));
      expect(blue.fill, const Color(0xFF2563EB));

      // Violet #8B5CF6 (luminance ≈ 0.198) cannot reach 4.5 with black OR white
      // on the raw color, so the fill must move.
      final violet = ProjectBadge.legibleColors(const Color(0xFF8B5CF6));
      expect(violet.fill, isNot(const Color(0xFF8B5CF6)));
      expect(
        awContrastRatio(violet.ink, violet.fill),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  testWidgets('renders the whole name, never "…"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProjectBadge(
              name: 'Deneme Projesi',
              color: Color(0xFF2563EB),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Deneme Projesi'), findsOneWidget);
    expect(find.textContaining('…'), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Deneme Projesi',
    );
  });
}
