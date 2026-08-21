// The unit surfaces, shot in both themes (EE-061 acceptance).
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/units_surfaces_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed.
//
// Why a picture for these two: "shared with me" is the only list in the
// product whose rows are NOT the user's own things, and the whole job of the
// layout is to say so at a glance. That is a claim about how it reads, and how
// something reads is not checkable in a widget finder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/shared_items_providers.dart';
import 'package:alliswell/src/features/ee/ui/shared_with_me_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS.
const String _screenshotFamily = 'ScreenshotSans';

SharedItem _item(String id, String title, String entityType, String rights) =>
    SharedItem(
      id: id,
      workspaceId: 'W1',
      shareId: 'S$id',
      sourceWorkspaceId: 'W-SOURCE',
      entityType: entityType,
      entityId: 'E$id',
      rights: rights,
      title: title,
      revision: 3,
      updatedAt: DateTime.utc(2026, 8, 21),
    );

/// Every state the row has to make legible: both ceilings, three kinds, and a
/// reference whose source has no title yet.
final _shared = [
  _item('1', 'Fatura mutabakatı', 'task', 'edit'),
  _item('2', 'Saha kurulum notları', 'note', 'view'),
  _item('3', 'Q3 Bakım Programı', 'project', 'view'),
  _item('4', '', 'file', 'edit'),
];

List<Override> _as(List<SharedItem> items) => [
  sharedWithMeProvider.overrideWith((ref) => Stream.value(items)),
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
    List<Override> overrides,
    Widget screen,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: AwPageBackground(child: screen),
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
    testWidgets('shared with me — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-shared-with-me',
        _as(_shared),
        const EeSharedWithMeScreen(),
      );
    });

    testWidgets('shared with me, empty — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-shared-with-me-empty',
        _as(const []),
        const EeSharedWithMeScreen(),
      );
    });
  }
}
