// Absences and the on-call cover they cause (EE-236, AW-E18).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/absences_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THESE TWO SHOTS.
//
//   • THE REPORT'S SCENE, AFTER THE FIX: Ayşe is away this week, and the first
//     thing on the screen is who has the pager instead — Burak, covering for
//     her, until the day she is back. Below it the next 90 days of absences,
//     her own removable and a colleague's not.
//   • WRITING ONE, AS A MANAGER: whose (the person picker exists only for
//     somebody who records for others), which days, and the v1 limits said
//     where the absence is written — whole days, no approval, no reason.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/absences_providers.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/absences_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/absences_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');
const _me = '01USERMEAAAAAAAAAAAAAAAAAA';

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  bool tr() => AwI18n.instance.locale.languageCode == 'tr';

  List<Override> overrides({bool manager = false}) => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    workspaceRosterProvider.overrideWith(
      (ref) => Stream.value(const [
        MemberProfile(
          id: 'MP1',
          workspaceId: 'W1',
          userId: _me,
          displayName: 'Ayşe Kaya',
          colorRgb: '#2563EB',
          revision: 1,
        ),
        MemberProfile(
          id: 'MP2',
          workspaceId: 'W1',
          userId: '01USERDENIZAAAAAAAAAAAAAAA',
          displayName: 'Deniz Aksoy',
          colorRgb: '#16A34A',
          revision: 1,
        ),
      ]),
    ),
    currentUserIdProvider.overrideWithValue(_me),
    eeMyOnCallProvider.overrideWith(
      (ref) async => [
        EeOnCallNow(
          unitId: 'U1',
          unitName: tr() ? 'Bakım' : 'Maintenance',
          userId: '01USERBURAKAAAAAAAAAAAAAAA',
          userName: 'Burak Demir',
          coveringFor: _me,
          coveringForName: 'Ayşe Kaya',
          until: DateTime(2026, 10, 1, 9),
        ),
        EeOnCallNow(
          unitId: 'U2',
          unitName: tr() ? 'Bilgi İşlem' : 'IT',
          userId: '01USERCEMAAAAAAAAAAAAAAAAA',
          userName: 'Cem Yıldız',
          until: DateTime(2026, 9, 28, 9),
        ),
      ],
    ),
    eeAbsencePageProvider.overrideWith(
      (ref) async => EeAbsencePage(
        today: DateTime.utc(2026, 9, 25),
        canManage: manager,
        absences: [
          EeAbsence(
            id: 'A1',
            userId: _me,
            userName: 'Ayşe Kaya',
            startDate: DateTime.utc(2026, 9, 25),
            endDate: DateTime.utc(2026, 9, 30),
          ),
          EeAbsence(
            id: 'A2',
            userId: '01USERDENIZAAAAAAAAAAAAAAA',
            userName: 'Deniz Aksoy',
            startDate: DateTime.utc(2026, 10, 12),
            endDate: DateTime.utc(2026, 10, 12),
          ),
        ],
      ),
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('who is away, and who covers (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-absences',
        size: const Size(900, 1100),
        overrides: overrides(),
        screen: const EeAbsencesScreen(),
      );
    });

    testWidgets('writing one, as a manager (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-absences-add',
        size: const Size(900, 1100),
        overrides: overrides(manager: true),
        screen: const EeAbsencesScreen(),
        afterPump: (t) => t.tap(find.byKey(const Key('absences-add'))),
      );
    });
  }
}
