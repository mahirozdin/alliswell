// The history tab, shot in both themes (EE-026 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/history_tab_screenshot_test.dart
//
// Skipped without the dart-define, exactly like the other shot files: goldens
// are generated output, not committed, so a plain CI run must not compare
// against pictures that are not in the repository. The acceptance criterion
// is a picture a person looks at — contrast and rhythm in light AND dark.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/ui/history_tab.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — loading the font is only half the
/// job, the theme has to ask for it (the markdown shot file learned this).
const String _screenshotFamily = 'ScreenshotSans';

const _target = (entityType: 'ee_team', entityId: 'T0000000000000000000000000');

/// A fixture that exercises every visual case the row has: a person with a
/// palette colour, a second person, and a system repair (icon, not initials).
final _page = EeHistoryPage(
  items: [
    _event(
      id: '01A',
      name: 'Ada Yönetici',
      initials: 'AY',
      color: '#2563EB',
      verb: 'member_added',
      minute: 42,
    ),
    _event(
      id: '01B',
      name: 'Barış Kaya',
      initials: 'BK',
      color: '#DB2777',
      verb: 'role_changed',
      minute: 30,
    ),
    _event(
      id: '01C',
      name: null,
      initials: null,
      color: null,
      verb: 'repaired',
      actor: 'system',
      minute: 5,
    ),
    _event(
      id: '01D',
      name: 'Ada Yönetici',
      initials: 'AY',
      color: '#2563EB',
      verb: 'created',
      minute: 1,
    ),
  ],
  nextCursor: '01D',
);

EeHistoryEvent _event({
  required String id,
  required String? name,
  required String? initials,
  required String? color,
  required String verb,
  required int minute,
  String actor = 'user',
}) => EeHistoryEvent(
  id: id.padRight(26, '0'),
  occurredAt: DateTime(2026, 8, 20, 9, minute),
  actor: actor,
  verb: verb,
  entityType: _target.entityType,
  entityId: _target.entityId,
  actorName: name,
  actorInitials: initials,
  actorColorRgb: color,
);

void main() {
  // Without the dart-define this file is inert: the goldens it compares
  // against are generated locally and never committed.
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('history tab — ${brightness.name}', (tester) async {
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
            overrides: [
              eeHistoryProvider.overrideWith((ref, arg) async => _page),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAwTheme(
                brightness,
                fontFamilyOverride: _screenshotFamily,
              ),
              // Every route in the app is wrapped in the page background
              // (router.dart's `_page`), and the scaffold colour is the VEIL —
              // a scrim meant to sit over the aurora. Shooting a bare Scaffold
              // renders that scrim against nothing and produces a flat grey
              // that exists nowhere in the product.
              home: AwPageBackground(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: SafeArea(
                    child: EeHistoryTab(
                      entityType: _target.entityType,
                      entityId: _target.entityId,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../goldens/ee-history-${brightness.name}.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
