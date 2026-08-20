// The instance console, shot in both themes (EE-033 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/admin/admin_console_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository. The acceptance is a picture a
// person looks at — this console can suspend a customer, and it should look
// deliberate in light AND dark before anyone trusts it with that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/admin/admin_providers.dart';
import 'package:alliswell/src/features/ee/admin/data/admin_models.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_shell.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_usage_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — the markdown and history shot files
/// both learned this the same way.
const String _screenshotFamily = 'ScreenshotSans';

/// A fixture with every state the dashboard has to make legible at a glance:
/// a team comfortably inside its plan, one PAST it, one uncapped, and one
/// frozen.
final _usage = InstanceUsage.fromJson({
  'instance': {
    'teams': {'used': 4, 'max': 5},
  },
  'teams': [
    _team(
      id: 'T1',
      name: 'Acme Endüstri',
      slug: 'acme',
      used: 12,
      max: 10,
      exceeded: true,
    ),
    _team(id: 'T2', name: 'Globex', slug: 'globex', used: 47, max: 50),
    _team(id: 'T3', name: 'Initech', slug: 'initech', used: 6, max: null),
    _team(
      id: 'T4',
      name: 'Umbrella',
      slug: 'umbrella',
      used: 3,
      max: 10,
      status: 'suspended',
    ),
  ],
});

Map<String, dynamic> _team({
  required String id,
  required String name,
  required String slug,
  required int used,
  required int? max,
  bool exceeded = false,
  String status = 'active',
}) => {
  'id': id,
  'name': name,
  'slug': slug,
  'status': status,
  'packageName': max == null ? 'Enterprise' : 'Business',
  'seats': {
    'used': used,
    'pending': 0,
    'max': max,
    'remaining': max == null ? null : (max - used).clamp(0, max),
    'exceeded': exceeded,
    'canAdd': !exceeded && (max == null || used < max),
  },
  'workspaces': 4,
};

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('instance console — ${brightness.name}', (tester) async {
      await loadRealFontsForStore();
      tester.view.physicalSize = const Size(1100, 800);
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
              adminUsageProvider.overrideWith((ref) async => _usage),
              adminSessionProvider.overrideWith(AdminSessionController.new),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAwTheme(
                brightness,
                fontFamilyOverride: _screenshotFamily,
              ),
              // Same lesson as the history shot: every route is wrapped in the
              // page background, and a bare Scaffold renders the veil against
              // nothing — a flat grey that exists nowhere in the product.
              home: AwPageBackground(
                child: AdminShell(
                  location: '/admin',
                  child: const AdminUsageScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(AdminShell),
          matchesGoldenFile(
            '../../../goldens/ee-admin-console-${brightness.name}.png',
          ),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
