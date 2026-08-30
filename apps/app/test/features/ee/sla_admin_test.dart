import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/sla_admin_models.dart';
import 'package:alliswell/src/features/ee/sla_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/sla_admin_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

/// EE-099 — the three editors, asserted where they would mislead.
///
/// The sharpest case here is the night shift. A calendar stores 22:00 → 06:00
/// as `[1320, 1800)` on the day it STARTS (ADR-0012 §1), and a screen that
/// printed the raw end time would say "22:00 – 06:00" — which reads as a
/// sixteen-hour gap rather than an eight-hour night. An admin would then
/// "fix" a calendar that was right. ADR-0012 wrote that down as a UI debt and
/// `formatShiftMinute` is where it is paid, so it is tested directly.
///
/// The others are the same family of quiet lies: a calendar with no shifts is
/// open around the clock rather than misconfigured, a policy with no calendar
/// is a real 24/7 contract rather than a missing value, and a monitor that has
/// never been asked is `unknown` rather than a warning.
class _Fixed extends EeSlaAdminController {
  _Fixed(this._value);
  final EeSlaAdminData? _value;
  @override
  Future<EeSlaAdminData?> build() async => _value;
}

Future<void> _pump(
  WidgetTester tester,
  EeSlaAdminData? value, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [eeSlaAdminProvider.overrideWith(() => _Fixed(value))],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeSlaAdminScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  group('the night shift, which is the whole UI debt ADR-0012 left', () {
    test('an end past midnight SAYS so', () {
      expect(formatShiftMinute(540), '09:00');
      expect(formatShiftMinute(1020), '17:00');
      expect(formatShiftMinute(1320), '22:00');
      // 1800 minutes from Monday midnight is 06:00 on Tuesday. Printing
      // "06:00" alone would turn an eight-hour night into a sixteen-hour gap
      // in the reader's head.
      expect(formatShiftMinute(1800), '06:00 (next day)');
      expect(formatShiftMinute(1440), '00:00 (next day)');
    });
  });

  testWidgets('a night shift is drawn with its wrap, in the list', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        calendars: [
          EeBusinessCalendar(
            id: 'C1',
            name: 'Fabrika',
            hours: [
              EeBusinessHour(weekday: 1, startMinute: 1320, endMinute: 1800),
            ],
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('sla-tab-calendars')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sla-calendar-C1')));
    await tester.pumpAndSettle();
    expect(find.text('Mon · 22:00 – 06:00 (next day)'), findsOneWidget);
  });

  testWidgets(
    'a calendar with no shifts says it is open, not that it is broken',
    (tester) async {
      await _pump(
        tester,
        const EeSlaAdminData(
          calendars: [EeBusinessCalendar(id: 'C1', name: 'Boş')],
        ),
      );
      await tester.tap(find.byKey(const Key('sla-tab-calendars')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sla-calendar-C1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('open around the clock'), findsOneWidget);
    },
  );

  testWidgets('a policy with no calendar reads as a CONTRACT, not a blank', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        policies: [EeSlaPolicy(id: 'P1', name: '7/24 destek', isDefault: true)],
      ),
    );
    expect(find.byKey(const Key('sla-policy-P1')), findsOneWidget);
    // "Around the clock", never an empty cell — null calendar is a real
    // contract (ADR-0012 §1).
    expect(find.textContaining('Around the clock'), findsOneWidget);
    expect(find.byKey(const Key('sla-policy-default-P1')), findsOneWidget);
  });

  testWidgets('the default is a WORD, so one team can only have one visibly', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        policies: [
          EeSlaPolicy(id: 'P1', name: 'Varsayılan', isDefault: true),
          EeSlaPolicy(id: 'P2', name: 'Özel', isDefault: false),
        ],
      ),
    );
    expect(find.byKey(const Key('sla-policy-default-P1')), findsOneWidget);
    expect(find.byKey(const Key('sla-policy-default-P2')), findsNothing);
  });

  testWidgets('a monitor never asked is UNKNOWN — neutral, not amber', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        checks: [
          EeHealthCheck(id: 'M1', name: 'Hat', url: 'https://example.com/h'),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('sla-tab-monitors')));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(EeSlaAdminScreen));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('sla-monitor-M1')),
        matching: find.byType(Icon),
      ),
    );
    // "Not asked yet" is not a warning, and it must not borrow the warning
    // colour — which could not carry a label anyway (3.46 on the light
    // surface, EE-097's measurement).
    expect(icon.color, isNot(context.awTokens.warning));
    expect(icon.color, Theme.of(context).disabledColor);
    expect(find.textContaining('Not checked yet'), findsOneWidget);
  });

  testWidgets('a down monitor carries its colour AND its word', (tester) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        checks: [
          EeHealthCheck(
            id: 'M1',
            name: 'Hat',
            url: 'https://example.com/h',
            status: 'down',
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('sla-tab-monitors')));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(EeSlaAdminScreen));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('sla-monitor-M1')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.color, Theme.of(context).colorScheme.error);
    expect(find.textContaining('Not answering'), findsOneWidget);
  });

  testWidgets('a paused monitor says paused rather than only looking quiet', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        checks: [
          EeHealthCheck(
            id: 'M1',
            name: 'Hat',
            url: 'https://example.com/h',
            status: 'up',
            enabled: false,
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('sla-tab-monitors')));
    await tester.pumpAndSettle();
    expect(find.textContaining('paused'), findsOneWidget);
  });

  testWidgets('each empty tab explains what the thing IS, with a way in', (
    tester,
  ) async {
    await _pump(tester, const EeSlaAdminData());
    // Policies
    expect(find.byKey(const Key('sla-policy-new-empty')), findsOneWidget);
    expect(find.textContaining('how fast this desk answers'), findsOneWidget);
    // Calendars
    await tester.tap(find.byKey(const Key('sla-tab-calendars')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sla-calendar-new-empty')), findsOneWidget);
    // Monitors
    await tester.tap(find.byKey(const Key('sla-tab-monitors')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sla-monitor-new-empty')), findsOneWidget);
  });

  testWidgets('no team at this address is an explanation, not an error', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.textContaining('Nothing to manage here'), findsOneWidget);
  });

  testWidgets('the policy sheet opens and offers 24/7 first', (tester) async {
    await _pump(
      tester,
      const EeSlaAdminData(
        policies: [EeSlaPolicy(id: 'P1', name: 'Mevcut')],
        calendars: [EeBusinessCalendar(id: 'C1', name: 'Mesai')],
      ),
    );
    await tester.tap(find.byKey(const Key('sla-policy-P1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sla-policy-name')), findsOneWidget);
    expect(find.byKey(const Key('sla-policy-calendar')), findsOneWidget);
    // Editing an existing policy offers deletion; creating one has nothing to
    // delete, which is why the button is conditional.
    expect(find.byKey(const Key('sla-policy-delete')), findsOneWidget);
  });
}
