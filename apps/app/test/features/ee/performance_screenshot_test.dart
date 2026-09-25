// The performance panel, with the kind of work first (EE-268, AW-E21).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/performance_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THIS SHOT.
//
//   • THE REPORT'S QUESTION, ANSWERED: "how long do repairs take, apart from
//     access requests?" — incidents and service requests as two rows at the
//     top, each with its MTTR and its own SLA compliance (one repair of two
//     was late), above the units and the people the panel already had.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/performance_models.dart';
import 'package:alliswell/src/features/ee/performance_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/performance_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

EePerformanceRow _row(
  String? key,
  String? label, {
  required int resolved,
  required double mttr,
  double? compliance,
  double? csat,
}) => EePerformanceRow.fromJson({
  'key': key,
  'label': label,
  'opened': resolved + 1,
  'answered': resolved,
  'resolved': resolved,
  'backlogDelta': 1,
  'mtta': {'minutes': 14.0, 'measured': resolved, 'total': resolved},
  'mttr': {'minutes': mttr, 'measured': resolved, 'total': resolved},
  'csat': {
    'average': csat,
    'answered': csat == null ? 0 : resolved,
    'sent': resolved,
  },
  'compliance': compliance,
});

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  bool tr() => AwI18n.instance.locale.languageCode == 'tr';

  List<Override> overrides() => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    eePerformanceProvider.overrideWith(
      () => _Fixed(
        EePerformance(
          from: '2026-08-27',
          to: '2026-09-25',
          closedIsNotPerformance: tr()
              ? 'Kapanan talep sayısı bir performans ölçüsü değildir: zor talepleri alan kişi daha az kapatır.'
              : 'The number of closed requests is not a measure of performance: whoever takes the hard ones closes fewer.',
          processTypes: [
            _row('incident', null, resolved: 2, mttr: 330, compliance: 50),
            _row('request', null, resolved: 14, mttr: 420, compliance: 100),
          ],
          units: [
            _row(
              'U1',
              tr() ? 'Bakım' : 'Maintenance',
              resolved: 16,
              mttr: 408,
              compliance: 94,
              csat: 4.6,
            ),
          ],
          agents: [
            _row('A1', 'Kerem Bakım', resolved: 9, mttr: 380, csat: 4.8),
            _row('A2', 'Ayla Servis', resolved: 7, mttr: 445, csat: 4.3),
          ],
        ),
      ),
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('the kind of work first (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-performance',
        size: const Size(900, 2200),
        overrides: overrides(),
        screen: const EePerformanceScreen(),
      );
    });
  }
}

class _Fixed extends EePerformanceController {
  _Fixed(this.value);
  final EePerformance value;

  @override
  Future<EePerformance?> build() async => value;
}
