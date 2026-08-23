import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_banner.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../support/fake_notifications.dart';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
  extensions: const [AwTokens.light],
);

/// A gateway whose permission probe we can pin per test.
class _SupportGateway extends FakeNotificationsGateway {
  _SupportGateway(this._support);

  final AlarmSupport _support;

  @override
  Future<AlarmSupport> alarmSupport() async => _support;
}

Future<void> pumpBanner(WidgetTester tester, AlarmSupport support) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsGatewayProvider.overrideWithValue(
          _SupportGateway(support),
        ),
      ],
      child: MaterialApp(
        theme: _theme,
        home: const Scaffold(body: AlarmDegradationBanner()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('warns when notifications are off', (tester) async {
    await pumpBanner(
      tester,
      const AlarmSupport(
        notificationsEnabled: false,
        criticalAlertsEnabled: false,
      ),
    );
    expect(find.byKey(const Key('alarm-banner')), findsOneWidget);
    expect(find.textContaining('Notifications are off'), findsOneWidget);
  });

  testWidgets('warns when Android exact alarms are denied', (tester) async {
    await pumpBanner(
      tester,
      const AlarmSupport(
        notificationsEnabled: true,
        criticalAlertsEnabled: false,
        exactAlarmsEnabled: false,
      ),
    );
    expect(find.byKey(const Key('alarm-banner')), findsOneWidget);
    expect(find.textContaining('may arrive late'), findsOneWidget);
  });

  testWidgets('stays hidden when delivery is healthy', (tester) async {
    await pumpBanner(
      tester,
      const AlarmSupport(
        notificationsEnabled: true,
        criticalAlertsEnabled: false,
        exactAlarmsEnabled: true,
      ),
    );
    expect(find.byKey(const Key('alarm-banner')), findsNothing);
  });

  // ── Round 19 (OPH-277) ──────────────────────────────────────────────────
  //
  // The probe threw away four of the five answers iOS gives it, so a phone
  // with notifications ON and sound OFF reported "ready to ring". Every state
  // below used to render nothing at all.
  group('the states that used to look healthy', () {
    testWidgets('sound off — the alarm arrives, in silence', (tester) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          soundEnabled: false,
        ),
      );
      expect(find.byKey(const Key('alarm-banner')), findsOneWidget);
      expect(find.textContaining('Sound is off'), findsOneWidget);
    });

    testWidgets('Time Sensitive off — every Focus buries it', (tester) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          soundEnabled: true,
          alertEnabled: true,
          timeSensitiveEnabled: false,
        ),
      );
      expect(find.textContaining('Time Sensitive'), findsOneWidget);
    });

    testWidgets('provisional — granted quietly, delivered quietly', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          provisionalOnly: true,
        ),
      );
      expect(find.textContaining('silently'), findsOneWidget);
    });

    testWidgets('AlarmKit declined — urgent drops to a silenceable lane', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          soundEnabled: true,
          alertEnabled: true,
          timeSensitiveEnabled: true,
          alarmKitAuthorized: false,
        ),
      );
      expect(find.textContaining('Alarm permission is off'), findsOneWidget);
    });

    testWidgets('a healthy device still shows nothing', (tester) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          soundEnabled: true,
          alertEnabled: true,
          timeSensitiveEnabled: true,
          alarmKitAuthorized: true,
        ),
      );
      expect(find.byKey(const Key('alarm-banner')), findsNothing);
    });

    test('the cascade names the WORST problem, not the first one found', () {
      // Both wrong at once: "notifications are off" is the one to say.
      const both = AlarmSupport(
        notificationsEnabled: false,
        criticalAlertsEnabled: false,
        soundEnabled: false,
      );
      expect(both.worstProblem, AlarmProblem.notificationsOff);
    });

    testWidgets('tapping it opens the sheet that says where the switch is', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          soundEnabled: false,
        ),
      );
      // It used to re-run `requestPermissions()`, which does nothing once the
      // user has answered the prompt — a Fix button that could not fix.
      await tester.tap(find.byKey(const Key('alarm-banner')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alarm-fix-open')), findsOneWidget);
      expect(find.textContaining('Settings ▸ Notifications'), findsOneWidget);
    });
  });
}
