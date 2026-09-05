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
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/sla_dashboard_models.dart';
import 'package:alliswell/src/features/ee/sla_dashboard_providers.dart';
import 'package:alliswell/src/features/ee/ui/sla_dashboard_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

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
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('sla dashboard, a desk in trouble (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-sla-dashboard',
        size: const Size(900, 1100),
        overrides: [
          eeSlaDashboardProvider.overrideWith(() => _Fixed(_struggling)),
        ],
        screen: const EeSlaDashboardScreen(),
      );
    });

    testWidgets('sla dashboard, nothing missed (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-sla-dashboard-clear',
        size: const Size(900, 1100),
        overrides: [
          eeSlaDashboardProvider.overrideWith(() => _Fixed(_healthy)),
        ],
        screen: const EeSlaDashboardScreen(),
      );
    });
  }
}
