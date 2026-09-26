import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/integrations/providers.dart'
    show urlLauncherProvider;
import 'package:alliswell/src/notifications/alarm_banner.dart';
import 'package:alliswell/src/notifications/alarm_fix_sheet.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../support/fake_notifications.dart';

/// #19 — on the web the fix sheet's button opened `app-settings:` in a new
/// tab: an iOS address no browser knows, so the tab was dead and the fix the
/// banner promised was unreachable. What each problem's button does is now
/// one exhaustive switch; these pin it from the outside, through the banner a
/// person actually taps, and count what reached the browser and the launcher.

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
  extensions: const [AwTokens.light],
);

class _Gateway extends FakeNotificationsGateway {
  _Gateway(this.support);

  final AlarmSupport support;
  int asked = 0;

  @override
  Future<AlarmSupport> alarmSupport() async => support;

  @override
  Future<bool> requestPermissions() async {
    asked += 1;
    return false;
  }
}

/// The probe writes a `degraded` row whenever delivery is off, and a real log
/// opens a real database per test. These tests are about the sheet.
class _QuietLog implements AlarmLog {
  @override
  Future<void> record({
    required String event,
    required String lane,
    String? kind,
    int? slotIndex,
    bool urgent = false,
    String? sound,
    String? level,
    DateTime? fireAt,
    String? taskId,
    String? reminderId,
    String? detail,
    DateTime? at,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Opened {
  _Opened(this.gateway);

  final _Gateway gateway;
  final List<Uri> launched = [];
}

Future<_Opened> _openSheet(WidgetTester tester, AlarmSupport support) async {
  final opened = _Opened(_Gateway(support));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsGatewayProvider.overrideWithValue(opened.gateway),
        alarmLogProvider.overrideWithValue(_QuietLog()),
        urlLauncherProvider.overrideWithValue((url) async {
          opened.launched.add(url);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: _theme,
        home: const Scaffold(body: AlarmDegradationBanner()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('alarm-banner')));
  await tester.pumpAndSettle();
  return opened;
}

Finder get _button => find.byKey(const Key('alarm-fix-open'));

AlarmSupport _browser(WebPermissionState permission) => AlarmSupport(
  notificationsEnabled: false,
  criticalAlertsEnabled: false,
  webPushReady: false,
  webPermission: permission,
);

void main() {
  group('on the web it never opens an iOS page (#19)', () {
    testWidgets('an unanswered prompt: the button asks the browser', (
      tester,
    ) async {
      final opened = await _openSheet(
        tester,
        _browser(WebPermissionState.prompt),
      );
      expect(find.text('Allow notifications'), findsOneWidget);

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(opened.gateway.asked, 1);
      expect(opened.launched, isEmpty);
      expect(_button, findsNothing, reason: 'the sheet closes once it asked');
    });

    testWidgets('a block: the address-bar steps, and a button that checks', (
      tester,
    ) async {
      final opened = await _openSheet(
        tester,
        _browser(WebPermissionState.denied),
      );
      expect(find.textContaining('won’t ask again'), findsOneWidget);
      expect(find.textContaining('site-info icon'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
      expect(find.text('Check again'), findsOneWidget);

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(opened.gateway.asked, 1);
      expect(opened.launched, isEmpty);
    });

    testWidgets('no web push at all: the way to get it, and no button', (
      tester,
    ) async {
      final opened = await _openSheet(
        tester,
        _browser(WebPermissionState.unsupported),
      );
      expect(find.textContaining('Add to Home Screen'), findsOneWidget);
      expect(_button, findsNothing);
      expect(opened.gateway.asked, 0);
      expect(opened.launched, isEmpty);
    });

    testWidgets('allowed but unreachable: checks again, opens nothing', (
      tester,
    ) async {
      final opened = await _openSheet(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          webPushReady: false,
        ),
      );
      expect(find.text('Check again'), findsOneWidget);

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(opened.gateway.asked, 1);
      expect(opened.launched, isEmpty);
    });
  });

  group('the native paths are what they were', () {
    testWidgets('an iOS switch still opens the app’s own Settings page', (
      tester,
    ) async {
      final opened = await _openSheet(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          soundEnabled: false,
        ),
      );
      expect(find.text('Open settings'), findsOneWidget);

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(opened.launched, [Uri.parse(kIosAppSettingsUrl)]);
      expect(opened.gateway.asked, 0);
    });

    testWidgets('Android’s exact alarms re-run the request that deep-links', (
      tester,
    ) async {
      final opened = await _openSheet(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          exactAlarmsEnabled: false,
        ),
      );

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(opened.gateway.asked, 1);
      expect(opened.launched, isEmpty);
    });
  });
}
