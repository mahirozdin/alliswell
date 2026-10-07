import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/data/sla_admin_models.dart';
import 'package:alliswell/src/features/ee/sla_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/sla_admin_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/features/ee/providers.dart';

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
  final calls = <String>[];
  Object? refuseWith;
  Map<String, EeSlaTarget> savedTargets = const {};
  @override
  Future<EeSlaAdminData?> build() async => _value;

  @override
  Future<void> savePolicyAndTargets({
    String? id,
    required String name,
    String? calendarId,
    bool? isDefault,
    int? warnPercent,
    Map<String, EeSlaTarget> targets = const {},
  }) async {
    calls.add('save ${id ?? 'new'} $name');
    savedTargets = targets;
  }

  @override
  Future<void> deletePolicy(String id) async {
    calls.add('delete $id');
    if (refuseWith != null) throw refuseWith!;
  }

  @override
  Future<void> deleteCalendar(String id) async => calls.add('deleteCal $id');

  @override
  Future<void> deleteCheck(String id) async => calls.add('deleteCheck $id');
}

late _Fixed _controller;

Future<void> _pump(
  WidgetTester tester,
  EeSlaAdminData? value, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeSlaAdminProvider.overrideWith(() => _controller = _Fixed(value)),
        // OPH-356: the "+" waits for a yes; this file is an admin's.
        canProvider.overrideWith((ref, id) => true),
      ],
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

  group('UI-AUDIT OPH-360', () {
    Future<void> openNew(WidgetTester tester) async {
      await _pump(
        tester,
        const EeSlaAdminData(
          policies: [EeSlaPolicy(id: 'P1', name: 'Mevcut', isDefault: true)],
        ),
      );
      await tester.tap(find.byKey(const Key('sla-policy-new')));
      await tester.pumpAndSettle();
    }

    FilledButton save(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('sla-policy-save')));

    testWidgets('UI-AUDIT #23: typing a name switches Save on, alone', (
      tester,
    ) async {
      await openNew(tester);
      expect(save(tester).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('sla-policy-name')), 'Altın');
      await tester.pump();
      // Nothing else touched — no slider, no switch.
      expect(save(tester).onPressed, isNotNull);
      await tester.ensureVisible(find.byKey(const Key('sla-policy-save')));
      await tester.tap(find.byKey(const Key('sla-policy-save')));
      await tester.pumpAndSettle();
      expect(_controller.calls, ['save new Altın']);
    });

    testWidgets(
      'UI-AUDIT #46: a policy has a target table, and only the changed rows travel',
      (tester) async {
        await _pump(
          tester,
          const EeSlaAdminData(
            policies: [
              EeSlaPolicy(
                id: 'P1',
                name: 'Standart',
                isDefault: true,
                targets: [
                  EeSlaTarget(
                    priority: 'high',
                    firstResponseMinutes: 60,
                    resolutionMinutes: 480,
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.tap(find.byKey(const Key('sla-policy-P1')));
        await tester.pumpAndSettle();
        for (final p in ['urgent', 'high', 'normal', 'low']) {
          expect(find.byKey(Key('sla-target-$p-first')), findsOneWidget);
          expect(find.byKey(Key('sla-target-$p-resolve')), findsOneWidget);
        }
        // The stored target is shown, and read back as a span.
        expect(find.text('8 h'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('sla-target-urgent-first')),
          '30',
        );
        await tester.enterText(
          find.byKey(const Key('sla-target-urgent-resolve')),
          '2880',
        );
        await tester.pump();
        expect(find.text('2 d'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('sla-policy-save')));
        await tester.tap(find.byKey(const Key('sla-policy-save')));
        await tester.pumpAndSettle();
        expect(_controller.calls, ['save P1 Standart']);
        expect(_controller.savedTargets.keys, ['urgent']);
        expect(_controller.savedTargets['urgent']!.firstResponseMinutes, 30);
        expect(_controller.savedTargets['urgent']!.resolutionMinutes, 2880);
      },
    );

    testWidgets('UI-AUDIT #46: a target that is not a number holds Save', (
      tester,
    ) async {
      await openNew(tester);
      await tester.enterText(find.byKey(const Key('sla-policy-name')), 'Altın');
      await tester.enterText(
        find.byKey(const Key('sla-target-low-first')),
        'abc',
      );
      await tester.pump();
      expect(save(tester).onPressed, isNull);
    });

    Future<void> openDelete(WidgetTester tester, EeSlaPolicy policy) async {
      await _pump(tester, EeSlaAdminData(policies: [policy]));
      await tester.tap(find.byKey(Key('sla-policy-${policy.id}')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('sla-policy-delete')));
      await tester.tap(find.byKey(const Key('sla-policy-delete')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'UI-AUDIT #22: deleting a policy asks first, with what it changes',
      (tester) async {
        await openDelete(tester, const EeSlaPolicy(id: 'P2', name: 'Altın'));
        // Nothing has been deleted by the tap on Delete.
        expect(_controller.calls, isEmpty);
        expect(find.textContaining('fall back to the team'), findsOneWidget);
        await tester.tap(find.text('Keep it'));
        await tester.pumpAndSettle();
        expect(_controller.calls, isEmpty);
      },
    );

    testWidgets('UI-AUDIT #22: confirming deletes', (tester) async {
      await openDelete(tester, const EeSlaPolicy(id: 'P2', name: 'Altın'));
      await tester.tap(find.byKey(const Key('sla-policy-delete-confirm')));
      await tester.pumpAndSettle();
      expect(_controller.calls, ['delete P2']);
    });

    testWidgets(
      'UI-AUDIT #22: the default policy is not deleted — the screen says how to replace it',
      (tester) async {
        await openDelete(
          tester,
          const EeSlaPolicy(id: 'P1', name: 'Standart', isDefault: true),
        );
        expect(find.textContaining('Mark another policy'), findsOneWidget);
        expect(
          find.byKey(const Key('sla-policy-delete-confirm')),
          findsNothing,
        );
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(_controller.calls, isEmpty);
      },
    );

    testWidgets(
      'UI-AUDIT #22: a 409 SLA_POLICY_DEFAULT from a stale list is a sentence, and the list stays',
      (tester) async {
        await _pump(
          tester,
          const EeSlaAdminData(
            policies: [EeSlaPolicy(id: 'P2', name: 'Altın')],
          ),
        );
        _controller.refuseWith = const ApiException(
          'SLA_POLICY_DEFAULT',
          'This is the default policy. Mark another policy as the default first, then delete this one.',
          statusCode: 409,
        );
        await tester.tap(find.byKey(const Key('sla-policy-P2')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('sla-policy-delete')));
        await tester.tap(find.byKey(const Key('sla-policy-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sla-policy-delete-confirm')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            "This is the team's default policy, so it cannot be "
            'deleted. Mark another policy as the default first, then '
            'delete this one.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('sla-policy-P2')), findsOneWidget);
      },
    );

    testWidgets(
      'UI-AUDIT #22: a calendar a policy counts against names the policy instead of deleting',
      (tester) async {
        await _pump(
          tester,
          const EeSlaAdminData(
            policies: [
              EeSlaPolicy(id: 'P1', name: 'Standart', calendarId: 'C1'),
            ],
            calendars: [EeBusinessCalendar(id: 'C1', name: 'Mesai')],
          ),
        );
        await tester.tap(find.byKey(const Key('sla-tab-calendars')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sla-calendar-C1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sla-calendar-edit-C1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sla-calendar-delete')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Standart'), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(_controller.calls, isEmpty);
      },
    );

    testWidgets('UI-AUDIT #22: deleting a monitor asks first', (tester) async {
      await _pump(
        tester,
        const EeSlaAdminData(
          checks: [EeHealthCheck(id: 'H1', name: 'ERP', url: 'https://erp')],
        ),
      );
      await tester.tap(find.byKey(const Key('sla-tab-monitors')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sla-monitor-H1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sla-monitor-delete')));
      await tester.pumpAndSettle();
      expect(_controller.calls, isEmpty);
      await tester.tap(find.byKey(const Key('sla-monitor-delete-confirm')));
      await tester.pumpAndSettle();
      expect(_controller.calls, ['deleteCheck H1']);
    });
  });
}
