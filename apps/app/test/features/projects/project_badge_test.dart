import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/ui/project_badge.dart';
import 'package:alliswell/src/features/projects/ui/project_edit_sheet.dart';
import 'package:alliswell/src/theme/tokens.dart';

void main() {
  group('ProjectBadge.shortLabel', () {
    test('keeps names of 6 or fewer characters whole', () {
      expect(ProjectBadge.shortLabel('Deneme'), 'Deneme'); // exactly 6
      expect(ProjectBadge.shortLabel('Ev'), 'Ev');
    });

    test('truncates longer names to 6 graphemes + ellipsis', () {
      expect(ProjectBadge.shortLabel('Deneme Projesi'), 'Deneme…');
      expect(ProjectBadge.shortLabel('Website'), 'Websit…');
    });

    test('is grapheme-safe (a family emoji counts as one, never split)', () {
      const family = '👨‍👩‍👧‍👦'; // a single grapheme cluster
      expect(ProjectBadge.shortLabel('${family}abcde'), '${family}abcde');
      expect(ProjectBadge.shortLabel('${family}abcdef'), '${family}abcde…');
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
      expect(awContrastRatio(violet.ink, violet.fill), greaterThanOrEqualTo(4.5));
    });
  });

  testWidgets('renders the short label with the full name in a tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProjectBadge(name: 'Deneme Projesi', color: Color(0xFF2563EB)),
          ),
        ),
      ),
    );

    expect(find.text('Deneme…'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Deneme Projesi',
    );
  });
}
