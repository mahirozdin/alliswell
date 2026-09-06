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
import 'support/demo_corpus.dart';
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

class _Fixed extends EeSlaDashboardController {
  _Fixed(this._value);
  final EeSlaDashboard _value;
  @override
  Future<EeSlaDashboard?> build() async => _value;
}

void main() {
  if (!_enabled) return;

  // 1820 and not 1100: at the old height the "Missed targets" heading sat on
  // the last visible line and the list itself was below the fold — in the
  // capture that has been shipping on /enterprise since EE-098. The breach
  // list is the thing this screen is photographed FOR, and _Breaches draws
  // every row it is given, so the frame has to be tall enough to hold them.

  // Both figures are FOLDS of the corpus now: compliance is
  // met/(met+breached) and the breach list is the corpus's own tickets.
  // The old fixture typed 78.4 beside a two-row list, which is about
  // fifty-four breaches the screen would have drawn in full.
  late DemoCorpus corpus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Order matters: the corpus reads the active language and asserts rather
    // than falling back to one.
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
    corpus = DemoCorpus.active();
  });

  for (final brightness in Brightness.values) {
    testWidgets('sla dashboard, a desk in trouble (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-sla-dashboard',
        size: const Size(900, 1820),
        overrides: [
          eeSlaDashboardProvider.overrideWith(
            () => _Fixed(corpus.dashboard(DemoPeriod.struggling)),
          ),
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
        size: const Size(900, 1820),
        overrides: [
          eeSlaDashboardProvider.overrideWith(
            () => _Fixed(corpus.dashboard(DemoPeriod.healthy)),
          ),
        ],
        screen: const EeSlaDashboardScreen(),
      );
    });
  }
}
