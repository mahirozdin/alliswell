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
}
