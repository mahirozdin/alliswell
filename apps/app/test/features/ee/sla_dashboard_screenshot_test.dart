// The SLA dashboard, shot in both themes (EE-098's acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/sla_dashboard_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY TWO SHOTS. This screen is sales material, and the two states it has to
// survive being photographed in are opposites:
//
//   • A DESK IN TROUBLE — a compliance figure below the line, a real breach
//     list, uneven bars. This is the shot that has to be legible across a
//     meeting room and in a black-and-white print-out, which is why every
//     number is text beside its bar rather than only a bar.
//   • A DESK THAT IS FINE — nothing missed. Good news needs its own sentence,
//     because an empty list drawn as an empty list reads as a screen that
//     failed to load, and that is the shot a customer is most likely to see
//     on the day the product is working.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/sla_dashboard_models.dart';
import 'package:alliswell/src/features/ee/sla_dashboard_providers.dart';
import 'package:alliswell/src/features/ee/ui/sla_dashboard_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

class _Fixed extends EeSlaDashboardController {
  _Fixed(this._value);
  final EeSlaDashboard _value;
  @override
  Future<EeSlaDashboard?> build() async => _value;
}

final _struggling = EeSlaDashboard(
  compliance: 78.4,
  byStatus: const [
    EeSlaBucket(key: 'new', label: 'new', count: 41),
    EeSlaBucket(key: 'in_progress', label: 'in_progress', count: 63),
    EeSlaBucket(key: 'closed', label: 'closed', count: 210),
  ],
  byUnit: const [
    EeSlaBucket(key: 'U1', label: 'Bakım', count: 186),
    EeSlaBucket(key: 'U2', label: 'Mühendislik', count: 92),
    EeSlaBucket(key: 'U3', label: 'Elektrik', count: 36),
  ],
  byService: const [
    EeSlaBucket(key: 'S1', label: 'Hat duruşu', count: 148),
    EeSlaBucket(key: 'S2', label: 'Kalibrasyon', count: 97),
    // A retired catalogue entry keeps its count: dropping it would make the
    // axes disagree, which is the quiet arithmetic error EE-090 refused.
    EeSlaBucket(key: null, label: null, count: 69),
  ],
  breaches: const [
    EeSlaBreach(
      id: 'T1',
      subject: '3. hat dolum bandı sensörü çift sayıyor, vardiya durdu',
      priority: 'urgent',
      status: 'in_progress',
    ),
    EeSlaBreach(
      id: 'T2',
      subject: 'Kaynak robotu kalibrasyonu sapıyor',
      priority: 'high',
      status: 'waiting',
    ),
  ],
);

final _healthy = EeSlaDashboard(
  compliance: 99.2,
  byStatus: const [EeSlaBucket(key: 'closed', label: 'closed', count: 254)],
  byUnit: const [EeSlaBucket(key: 'U1', label: 'Bakım', count: 254)],
  byService: const [EeSlaBucket(key: 'S1', label: 'Hat duruşu', count: 254)],
);

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
    EeSlaDashboard data,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [eeSlaDashboardProvider.overrideWith(() => _Fixed(data))],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: const AwPageBackground(child: EeSlaDashboardScreen()),
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
    testWidgets('sla dashboard, a desk in trouble (${brightness.name})', (
      tester,
    ) async {
      await shoot(tester, brightness, 'ee-sla-dashboard', _struggling);
    });

    testWidgets('sla dashboard, nothing missed (${brightness.name})', (
      tester,
    ) async {
      await shoot(tester, brightness, 'ee-sla-dashboard-clear', _healthy);
    });
  }
}
