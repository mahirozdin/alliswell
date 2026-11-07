import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/home/home_screen.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/theme/typography.dart';

/// OPH-399 (ADR-0063 #2–#4, T-05) — Home's section headers sit on the page,
/// not on a card: they take the section role (15/20 w700 since OPH-401,
/// tabular count) and, for "Overdue", the page-safe red. `scheme.error` measured 4.32:1 (light) /
/// 4.34:1 (dark) over the aurora's brightest blob.
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: Home section headers use the section '
        'role and the page-safe red', (tester) async {
      final theme = buildAwTheme(brightness);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ListView(
                  children: buildHomeGroupRows(context, const [
                    HomeGroup(
                      bucket: HomeBucket.overdue,
                      items: [],
                      dimmed: false,
                    ),
                    HomeGroup(
                      bucket: HomeBucket.noDate,
                      items: [],
                      dimmed: false,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );

      final tokens = theme.extension<AwTokens>()!;
      final roles = theme.extension<AwTextRoles>()!;
      // OPH-401 (DESIGN §47 S1): the name and the count are two texts.
      TextStyle styleOf(String label) =>
          tester.widget<Text>(find.text(label)).style!;

      final overdue = styleOf(HomeBucket.overdue.label);
      expect(overdue.color, tokens.errorOnPage);
      expect(overdue.color, isNot(theme.colorScheme.error));
      expect(overdue.fontSize, roles.sectionLabel.fontSize);
      expect(overdue.fontWeight, FontWeight.w700);
      expect(overdue.letterSpacing, 0, reason: 'no hand-picked +0.4');
      expect(
        overdue.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      final plain = styleOf(HomeBucket.noDate.label);
      expect(plain.color, theme.colorScheme.onSurface);
      expect(plain.fontSize, roles.sectionLabel.fontSize);
    });
  }
}
