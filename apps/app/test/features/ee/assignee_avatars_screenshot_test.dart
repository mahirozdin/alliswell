// The assignee surfaces, shot in both themes (EE-068 acceptance).
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/assignee_avatars_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed.
//
// Why a picture for these: the avatar is the one element in the product whose
// colour comes from the SERVER and is therefore outside the palette's control.
// contrast.py pins the ratios, but a ratio cannot say whether ten different
// people in a row read as ten different people — or whether the tombstone
// avatar reads as "somebody who left" rather than as a rendering bug. Both are
// claims about how it looks, and how something looks is not checkable in a
// widget finder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/ui/assignee_avatars.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS.
const String _screenshotFamily = 'ScreenshotSans';

/// Every colour in the roster's palette, so the shot answers the question the
/// numbers cannot: do ten people read as ten people, in both themes?
const _palette = [
  ('Ayla Yönetici', 'AY', '#2563EB'),
  ('Barış Saha', 'BS', '#7C3AED'),
  ('Ceren Muhasebe', 'CM', '#DB2777'),
  ('Deniz Koordinatör', 'DK', '#DC2626'),
  ('Emre Bakım', 'EB', '#EA580C'),
  ('Fulya Depo', 'FD', '#CA8A04'),
  ('Gökhan Vardiya', 'GV', '#16A34A'),
  ('Hale Planlama', 'HP', '#0D9488'),
  ('İpek Kalite', 'İK', '#0284C7'),
  ('Jale Lojistik', 'JL', '#4F46E5'),
];

List<Assignee> get _everyone => [
  for (final (index, person) in _palette.indexed)
    Assignee(
      assignmentId: 'A$index',
      userId: 'U$index',
      displayName: person.$1,
      initials: person.$2,
      colorRgb: person.$3,
    ),
  // The churn case, deliberately last: somebody who left the unit but still
  // holds the work. It must read as a person, not as a failed render.
  const Assignee(assignmentId: 'A-GONE', userId: 'U-GONE'),
];

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    Widget body,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: AwPageBackground(child: body),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('assignee avatars, whole palette — ${brightness.name}', (
      tester,
    ) async {
      await shoot(
        tester,
        brightness,
        'ee-assignee-avatars',
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(AwSpace.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The size the task card uses…
                Wrap(
                  spacing: AwSpace.x2,
                  runSpacing: AwSpace.x2,
                  children: [
                    for (final assignee in _everyone)
                      AwAssigneeAvatar(assignee: assignee),
                  ],
                ),
                const SizedBox(height: AwSpace.x8),
                // …and the size the detail card uses.
                Wrap(
                  spacing: AwSpace.x3,
                  runSpacing: AwSpace.x3,
                  children: [
                    for (final assignee in _everyone)
                      AwAssigneeAvatar(assignee: assignee, size: 32),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
