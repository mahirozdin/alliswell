// The SLA admin editors, shot in both themes (EE-099's acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/sla_admin_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY THE CALENDAR TAB IS THE ONE THAT MATTERS. A shift ending past midnight
// is stored on the day it STARTS (ADR-0012 §1), so the screen has to say
// "06:00 (ertesi gün)" or an admin reads an eight-hour night as a sixteen-hour
// gap and "fixes" a calendar that was right. A picture is how that gets
// reviewed by somebody who is not reading the test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/sla_admin_models.dart';
import 'package:alliswell/src/features/ee/sla_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/sla_admin_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

class _Fixed extends EeSlaAdminController {
  _Fixed(this._value);
  final EeSlaAdminData _value;
  @override
  Future<EeSlaAdminData?> build() async => _value;
}

const _data = EeSlaAdminData(
  policies: [
    EeSlaPolicy(
      id: 'P1',
      name: 'Fabrika — vardiyalı',
      calendarId: 'C1',
      warnPercent: 80,
      targets: [
        EeSlaTarget(
          priority: 'urgent',
          firstResponseMinutes: 15,
          resolutionMinutes: 60,
        ),
        EeSlaTarget(
          priority: 'high',
          firstResponseMinutes: 60,
          resolutionMinutes: 240,
        ),
      ],
    ),
    EeSlaPolicy(
      id: 'P2',
      name: '7/24 destek',
      isDefault: true,
      warnPercent: 90,
    ),
  ],
  calendars: [
    EeBusinessCalendar(
      id: 'C1',
      name: 'Üç vardiya',
      timezone: 'Europe/Istanbul',
      hours: [
        EeBusinessHour(weekday: 1, startMinute: 360, endMinute: 840),
        EeBusinessHour(weekday: 1, startMinute: 840, endMinute: 1320),
        // The one the picture exists for: 22:00 → 06:00 the next day.
        EeBusinessHour(weekday: 1, startMinute: 1320, endMinute: 1800),
      ],
      holidays: [EeHoliday(date: '2026-04-23', name: 'Ulusal Egemenlik')],
    ),
  ],
  checks: [
    EeHealthCheck(
      id: 'M1',
      name: 'Hat 3 PLC',
      url: 'https://plc3.fabrika.example.com/health',
      status: 'down',
      lastError: 'status 503',
    ),
    EeHealthCheck(
      id: 'M2',
      name: 'Depo terminali',
      url: 'https://depo.fabrika.example.com/health',
      status: 'up',
    ),
    EeHealthCheck(
      id: 'M3',
      name: 'Yedek hat',
      url: 'https://yedek.fabrika.example.com/health',
      enabled: false,
    ),
  ],
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
    String? tabKey,
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
          overrides: [eeSlaAdminProvider.overrideWith(() => _Fixed(_data))],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: const AwPageBackground(child: EeSlaAdminScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (tabKey != null) {
        await tester.tap(find.byKey(Key(tabKey)));
        await tester.pumpAndSettle();
        if (tabKey == 'sla-tab-calendars') {
          // Expanded, because the wrap label is the whole reason this shot
          // exists and it lives inside the tile.
          await tester.tap(find.byKey(const Key('sla-calendar-C1')));
          await tester.pumpAndSettle();
        }
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('sla policies (${brightness.name})', (tester) async {
      await shoot(tester, brightness, 'ee-sla-policies', null);
    });
    testWidgets('sla calendars, night shift expanded (${brightness.name})', (
      tester,
    ) async {
      await shoot(tester, brightness, 'ee-sla-calendars', 'sla-tab-calendars');
    });
    testWidgets('sla monitors (${brightness.name})', (tester) async {
      await shoot(tester, brightness, 'ee-sla-monitors', 'sla-tab-monitors');
    });
  }
}
