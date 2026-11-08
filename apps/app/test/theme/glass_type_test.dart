import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/theme/typography.dart';

/// OPH-399 (ADR-0063, DESIGN §3.3) — Glass Type v1, platform tracking and
/// the page-ground contrast.
///
/// T-01/U-15: Material's Roboto-tuned tracking (+0.5 on bodyLarge, +0.25,
/// +0.4) was applied to SF Pro, which Flutter draws without Apple's dynamic
/// tracking — row titles came out 9.4–11.3 % wider than native iOS. The
/// widths themselves cannot be measured here (`flutter test` draws a test
/// font), so these tests pin the numbers that produce them; the simulator
/// measurement is a DEVICE-CHECKS row.
void main() {
  final sfTable = <double, double>{
    11: 0.06,
    12: 0,
    13: -0.08,
    14: -0.15,
    15: -0.23,
    16: -0.31,
    17: -0.43,
    20: -0.45,
    22: -0.26,
    24: 0.07,
    28: 0.38,
    34: 0.40,
  };

  TextTheme textOf(ThemeData t) => t.textTheme;
  Map<String, TextStyle> roles(TextTheme t) => {
    'displayLarge': t.displayLarge!,
    'displayMedium': t.displayMedium!,
    'displaySmall': t.displaySmall!,
    'headlineLarge': t.headlineLarge!,
    'headlineMedium': t.headlineMedium!,
    'headlineSmall': t.headlineSmall!,
    'titleLarge': t.titleLarge!,
    'titleMedium': t.titleMedium!,
    'titleSmall': t.titleSmall!,
    'bodyLarge': t.bodyLarge!,
    'bodyMedium': t.bodyMedium!,
    'bodySmall': t.bodySmall!,
    'labelLarge': t.labelLarge!,
    'labelMedium': t.labelMedium!,
    'labelSmall': t.labelSmall!,
  };

  ThemeData themeOn(
    TargetPlatform platform,
    Brightness brightness, {
    String? font,
  }) {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return buildAwTheme(brightness, fontFamilyOverride: font);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('awTracking', () {
    test('Apple: the HIG SF Pro table (ADR-0063 #1)', () {
      sfTable.forEach((size, points) {
        expect(awTracking(size, apple: true), points, reason: '$size pt');
      });
      // Between rows it takes the nearest one; past the table it is 0.
      expect(awTracking(15.6, apple: true), -0.31);
      expect(awTracking(120, apple: true), 0);
    });

    test('every other font keeps its own metrics: 0 at every size', () {
      for (var size = 6.0; size <= 96; size += 0.5) {
        expect(awTracking(size, apple: false), 0, reason: '$size pt');
      }
    });

    test('only iOS and macOS native draw in the Apple system font', () {
      for (final p in TargetPlatform.values) {
        expect(
          awUsesAppleSystemFont(platform: p),
          p == TargetPlatform.iOS || p == TargetPlatform.macOS,
          reason: '$p',
        );
      }
      // The screenshot harness draws Roboto even on an Apple platform.
      expect(
        awUsesAppleSystemFont(
          platform: TargetPlatform.iOS,
          fontFamilyOverride: 'Roboto',
        ),
        isFalse,
      );
    });
  });

  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      test('iOS: every role tracks by the HIG table, never M3 positive', () {
        final t = textOf(themeOn(TargetPlatform.iOS, brightness));
        roles(t).forEach((name, s) {
          expect(
            s.letterSpacing,
            awTracking(s.fontSize!, apple: true),
            reason: name,
          );
        });
        // The values the measurement was about (typography-sf-verification §2).
        expect(t.bodyLarge!.letterSpacing, -0.31);
        expect(t.bodyMedium!.letterSpacing, -0.15);
        expect(t.bodySmall!.letterSpacing, 0);
        expect(t.labelLarge!.letterSpacing, -0.15);
        for (final s in [t.bodyLarge, t.bodyMedium, t.bodySmall]) {
          expect(s!.letterSpacing, lessThanOrEqualTo(0));
        }
      });

      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        test('${platform.name}: tracking 0 on every role', () {
          final t = textOf(themeOn(platform, brightness));
          roles(t).forEach((name, s) {
            expect(s.letterSpacing, 0, reason: name);
          });
        });
      }

      test('the screenshot font on iOS keeps Roboto metrics (0)', () {
        final t = textOf(
          themeOn(TargetPlatform.iOS, brightness, font: 'Roboto'),
        );
        roles(t).forEach((name, s) {
          expect(s.letterSpacing, 0, reason: name);
        });
      });

      test('Glass Type v1: sizes kept, line heights and weights set', () {
        final t = textOf(themeOn(TargetPlatform.iOS, brightness));
        // size / line height / weight — typography-system.md §4.2.
        const spec = <String, (double, double, FontWeight)>{
          'displaySmall': (36, 44, FontWeight.w700),
          'headlineMedium': (28, 34, FontWeight.w700),
          'headlineSmall': (24, 30, FontWeight.w700),
          'titleLarge': (22, 28, FontWeight.w700),
          'titleMedium': (16, 22, FontWeight.w600),
          'titleSmall': (14, 20, FontWeight.w600),
          'bodyLarge': (16, 22, FontWeight.w400),
          'bodyMedium': (14, 20, FontWeight.w400),
          'bodySmall': (12, 16, FontWeight.w400),
          'labelLarge': (14, 20, FontWeight.w600),
          'labelMedium': (12, 16, FontWeight.w600),
          'labelSmall': (11, 14, FontWeight.w500),
        };
        final all = roles(t);
        spec.forEach((name, v) {
          final s = all[name]!;
          expect(s.fontSize, v.$1, reason: '$name size');
          expect(s.fontSize! * s.height!, closeTo(v.$2, 0.001), reason: name);
          expect(s.fontWeight, v.$3, reason: '$name weight');
        });
        // Weights are 400/500/600/700 only — w800 is the alarm label's alone.
        for (final s in all.values) {
          expect(const [
            FontWeight.w400,
            FontWeight.w500,
            FontWeight.w600,
            FontWeight.w700,
          ], contains(s.fontWeight));
        }
        // The dashboard's big number is tabular.
        expect(
          t.displaySmall!.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      });

      test('the list row title is bodyLarge, w400 (was w500)', () {
        final theme = themeOn(TargetPlatform.iOS, brightness);
        expect(theme.listTileTheme.titleTextStyle, theme.textTheme.bodyLarge);
        expect(theme.listTileTheme.titleTextStyle!.fontWeight, FontWeight.w400);
      });

      test('semantic roles (context.awText)', () {
        for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
          final r = themeOn(platform, brightness).extension<AwTextRoles>()!;
          final apple = platform == TargetPlatform.iOS;
          void spec(TextStyle s, double size, double line, FontWeight w) {
            expect(s.fontSize, size);
            expect(s.fontSize! * s.height!, closeTo(line, 0.001));
            expect(s.fontWeight, w);
            expect(s.letterSpacing, awTracking(size, apple: apple));
          }

          spec(r.sectionLabel, 15, 20, FontWeight.w700);
          spec(r.dayNumber, 17, 22, FontWeight.w600);
          spec(r.meta, 13, 18, FontWeight.w400);
          spec(r.metaStrong, 13, 18, FontWeight.w500);
          spec(r.rowTitle, 16, 22, FontWeight.w400);
          const tabular = FontFeature.tabularFigures();
          expect(r.sectionLabel.fontFeatures, contains(tabular));
          expect(r.meta.fontFeatures, contains(tabular));
          expect(r.dayNumber.fontFeatures, contains(tabular));
          expect(r.tracking(11), awTracking(11, apple: apple));
        }
      });
    });
  }

  test('awTabular adds tabular figures once and keeps other features', () {
    const base = TextStyle(fontFeatures: [FontFeature.enable('ss01')]);
    final once = awTabular(base);
    expect(once.fontFeatures, [
      const FontFeature.enable('ss01'),
      const FontFeature.tabularFigures(),
    ]);
    expect(awTabular(once).fontFeatures, once.fontFeatures);
  });

  // ── Contrast on the page (ADR-0063 #4, T-05) ──
  //
  // contrast.py measures these too; the same model lives here so a token
  // change fails in `flutter test` as well as in the gate.
  Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);
  List<Color> pageGrounds(AwTokens t) => [
    for (final wash in [t.auroraTop, t.auroraBottom]) ...[
      over(t.veil, wash),
      for (final blob in [t.blobA, t.blobB, t.blobC])
        over(t.veil, over(blob, wash)),
    ],
  ];

  for (final brightness in Brightness.values) {
    test(
      '${brightness.name}: page text holds 4.5:1 over every aurora peak',
      () {
        final theme = buildAwTheme(brightness);
        final t = theme.extension<AwTokens>()!;
        final scheme = theme.colorScheme;
        final inks = {
          'overdue header (errorOnPage)': t.errorOnPage,
          'selected-day header (link)': t.link,
          'section header (onSurfaceVariant)': scheme.onSurfaceVariant,
          'body ink': scheme.onSurface,
        };
        for (final ground in pageGrounds(t)) {
          inks.forEach((name, ink) {
            expect(
              awContrastRatio(ink, ground),
              greaterThanOrEqualTo(4.5),
              reason: '$name on $ground',
            );
          });
        }
        // Why the token exists: the card red does NOT hold on the page.
        final worstError = pageGrounds(t)
            .map((g) => awContrastRatio(scheme.error, g))
            .reduce((a, b) => a < b ? a : b);
        expect(worstError, lessThan(4.5));
      },
    );

    test('${brightness.name}: the favourite star clears 3:1 on its chip', () {
      final theme = buildAwTheme(brightness);
      expect(
        awContrastRatio(
          theme.extension<AwTokens>()!.warning,
          theme.colorScheme.surfaceContainerLow,
        ),
        greaterThanOrEqualTo(3),
      );
    });
  }
}
