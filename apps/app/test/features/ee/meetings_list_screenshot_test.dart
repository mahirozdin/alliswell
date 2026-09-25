// The unit's meetings (EE-271, AW-E26) — the door EE-115's screen never had.
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/meetings_list_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THIS SHOT. One picture of the three answers a row can give: a meeting
// that is ready and says what it decided, one still being written (a spinner
// word, no count it does not have yet), and one whose note is WAITING — the
// words are safe and the summary is missing, drawn as waiting rather than done.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/meeting_models.dart';
import 'package:alliswell/src/features/ee/meetings_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/meetings_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('the unit\'s meetings (${brightness.name})', (tester) async {
      final tr = AwI18n.instance.locale.languageCode == 'tr';
      final now = DateTime.now();
      EeMeetingSummary meeting(
        String id,
        String titleTr,
        String titleEn,
        EeMeetingStatus status,
        Duration ago, {
        int decisions = 0,
        int ideas = 0,
      }) => EeMeetingSummary(
        id: id,
        workspaceId: 'W1',
        status: status,
        attempts: 1,
        decisionCount: decisions,
        ideaCount: ideas,
        createdAt: now.subtract(ago),
        title: tr ? titleTr : titleEn,
      );

      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-meetings',
        size: const Size(900, 1200),
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          currentWorkspaceProvider.overrideWithValue(
            const AsyncValue.data(
              WorkspaceSummary(
                id: 'W1',
                name: 'Bakım',
                slug: 'bakim',
                colorRgb: '#2563EB',
                role: 'member',
              ),
            ),
          ),
          eeMeetingListProvider.overrideWith(
            (ref, workspaceId) async => [
              meeting(
                'M3',
                'Kalite gözden geçirme',
                'Quality review',
                EeMeetingStatus.summarizing,
                const Duration(minutes: 25),
              ),
              meeting(
                'M2',
                'Hat 3 duruş değerlendirmesi',
                'Line 3 stoppage review',
                EeMeetingStatus.transcribed,
                const Duration(hours: 5),
              ),
              meeting(
                'M1',
                'Haftalık üretim toplantısı',
                'Weekly production meeting',
                EeMeetingStatus.ready,
                const Duration(days: 2),
                decisions: 3,
                ideas: 2,
              ),
            ],
          ),
        ],
        screen: const EeMeetingsScreen(),
      );
    });
  }
}
