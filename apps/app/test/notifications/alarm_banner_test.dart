import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarm_banner.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart'
    show alarmClockProvider;
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../support/fake_notifications.dart';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
  extensions: const [AwTokens.light],
);

/// A gateway whose permission probe we can pin per test — and change, for the
/// tests about what happens after the person answers the prompt.
class SupportGateway extends FakeNotificationsGateway {
  SupportGateway(this.support);

  AlarmSupport support;
  int probes = 0;

  @override
  Future<AlarmSupport> alarmSupport() async {
    probes += 1;
    return support;
  }
}

Future<ProviderContainer> pumpBanner(
  WidgetTester tester,
  AlarmSupport support, {
  SupportGateway? gateway,
  DateTime Function()? clock,
  double textScale = 1.0,
  double width = 393,
}) async {
  final container = ProviderContainer(
    overrides: [
      notificationsGatewayProvider.overrideWithValue(
        gateway ?? SupportGateway(support),
      ),
      alarmLogProvider.overrideWithValue(_QuietLog()),
      if (clock != null) alarmClockProvider.overrideWithValue(clock),
      // These tests are about this device's permissions; with no session the
      // band has no device list to read (OPH-453 has its own group below).
      currentUserIdProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: _theme,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: const Scaffold(body: AlarmDegradationBanner()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The probe writes a `degraded` row whenever delivery is off; a real log opens
/// a real database per test, which made the re-probe tests slow enough to race
/// under a loaded full suite. These tests are about the strip.
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

const _off = AlarmSupport(
  notificationsEnabled: false,
  criticalAlertsEnabled: false,
);

/// A browser that granted permission on a server with no VAPID keys — the
/// `/push/public-key` 404 (E-14).
const _serverWithoutPush = AlarmSupport(
  notificationsEnabled: true,
  criticalAlertsEnabled: false,
  webPushReady: false,
  webPushServerConfigured: false,
);

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

  // ── OPH-393 (U-05, E-14) ────────────────────────────────────────────────
  //
  // The strips were alarm-red, dramatic ("nothing can reach you"), said
  // "Tap to fix" next to a "Fix" that did the same thing, could not be closed,
  // and showed a server's missing keys as the person's own fault.
  group('a strip that does not blame (OPH-393)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await localKv.remove(kAlarmBannerDismissedKey);
    });
    tearDown(() async => localKv.remove(kAlarmBannerDismissedKey));

    testWidgets('a warning, not an alarm: amber, never the error container', (
      tester,
    ) async {
      await pumpBanner(tester, _off);
      final strip = tester.widget<Material>(
        find.byKey(const Key('alarm-banner-surface')),
      );
      final scheme = _theme.colorScheme;
      expect(strip.color, isNot(scheme.errorContainer));
      expect(
        strip.color,
        Color.alphaBlend(
          AwTokens.light.warning.withValues(alpha: 0.10),
          scheme.surface,
        ),
      );
      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byKey(const Key('alarm-banner')),
              matching: find.byType(Icon),
            )
            .first,
      );
      expect(icon.size, 20);
      expect(icon.color, AwTokens.light.warning);
    });

    testWidgets('Ek A-02: one calm sentence and a verb button', (tester) async {
      await pumpBanner(tester, _off);
      expect(
        find.text("Notifications are off. Reminders can't reach you."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('alarm-banner-action')), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
      // No device verb, no drama, no "Fix" doubling the sentence.
      expect(find.textContaining('Tap'), findsNothing);
      expect(find.textContaining('nothing can reach'), findsNothing);
      expect(find.text('Fix'), findsNothing);
    });

    testWidgets('the verb opens the page that can fix it', (tester) async {
      await pumpBanner(tester, _off);
      await tester.tap(find.byKey(const Key('alarm-banner-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alarm-fix-open')), findsOneWidget);
    });

    testWidgets('one line at ~56 pt where the sentence fits', (tester) async {
      // The test font sets every glyph a full em wide, so "fits" needs a wide
      // window here; the phone width is a golden/device check.
      await pumpBanner(tester, _off, width: 1400);
      final height = tester
          .getSize(find.byKey(const Key('alarm-banner-surface')))
          .height;
      expect(height, inInclusiveRange(48, 64));
    });

    testWidgets('E-14: a server without push keys is the admin\'s message', (
      tester,
    ) async {
      await pumpBanner(tester, _serverWithoutPush);
      expect(_serverWithoutPush.worstProblem, AlarmProblem.webPushUnconfigured);
      expect(
        find.text(
          "Browser notifications aren't set up on this server. "
          'Let your server admin know.',
        ),
        findsOneWidget,
      );
      // Nothing the person can press would fix a server: no verb, only close.
      expect(find.byKey(const Key('alarm-banner-action')), findsNothing);
      expect(find.byKey(const Key('alarm-banner-close')), findsOneWidget);
      expect(find.textContaining('allowed'), findsNothing);
    });

    testWidgets('A-04: permission and keys, no subscription yet', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: true,
          criticalAlertsEnabled: false,
          webPushReady: false,
          webPushServerConfigured: true,
        ),
      );
      expect(
        find.text("Reminders can't reach this browser yet."),
        findsOneWidget,
      );
      expect(find.text('Finish setup'), findsOneWidget);
    });

    testWidgets('A-05 / A-06: the two browser refusals', (tester) async {
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: false,
          criticalAlertsEnabled: false,
          webPushReady: false,
          webPermission: WebPermissionState.denied,
        ),
      );
      expect(
        find.text(
          'Notifications are blocked for this site, '
          "so reminders can't reach this tab.",
        ),
        findsOneWidget,
      );
      expect(find.text('Show me how'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpBanner(
        tester,
        const AlarmSupport(
          notificationsEnabled: false,
          criticalAlertsEnabled: false,
          webPushReady: false,
          webPermission: WebPermissionState.prompt,
        ),
      );
      expect(
        find.text("You haven't allowed notifications in this browser yet."),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsOneWidget);
    });

    testWidgets('closing it hides it for seven days, then it is back', (
      tester,
    ) async {
      var now = DateTime.utc(2030, 6, 1, 9);
      final gateway = SupportGateway(_serverWithoutPush);
      await pumpBanner(
        tester,
        _serverWithoutPush,
        gateway: gateway,
        clock: () => now,
      );
      await tester.tap(find.byKey(const Key('alarm-banner-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alarm-banner')), findsNothing);
      expect(
        await localKv.get(kAlarmBannerDismissedKey),
        isNotNull,
        reason: 'device-local, so the next launch remembers it',
      );

      // A new launch six days later: still closed.
      now = now.add(const Duration(days: 6));
      await tester.pumpWidget(const SizedBox());
      await pumpBanner(
        tester,
        _serverWithoutPush,
        gateway: gateway,
        clock: () => now,
      );
      expect(find.byKey(const Key('alarm-banner')), findsNothing);

      // Past the seventh day: the problem is still real, so it says so again.
      now = now.add(const Duration(days: 1, minutes: 1));
      await tester.pumpWidget(const SizedBox());
      await pumpBanner(
        tester,
        _serverWithoutPush,
        gateway: gateway,
        clock: () => now,
      );
      expect(find.byKey(const Key('alarm-banner')), findsOneWidget);
    });

    testWidgets('closing one problem does not hide a different one', (
      tester,
    ) async {
      final gateway = SupportGateway(_serverWithoutPush);
      final container = await pumpBanner(
        tester,
        _serverWithoutPush,
        gateway: gateway,
      );
      await tester.tap(find.byKey(const Key('alarm-banner-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alarm-banner')), findsNothing);

      gateway.support = _off;
      container.invalidate(alarmSupportProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alarm-banner')), findsOneWidget);
    });

    testWidgets('large text: the button drops below, full width', (
      tester,
    ) async {
      await pumpBanner(tester, _off, textScale: 2.0);
      final strip = tester.getRect(
        find.byKey(const Key('alarm-banner-surface')),
      );
      final text = tester.getRect(
        find.text("Notifications are off. Reminders can't reach you."),
      );
      final button = tester.getRect(
        find.byKey(const Key('alarm-banner-action')),
      );
      expect(button.top, greaterThanOrEqualTo(text.bottom));
      // Full width inside the strip's padding.
      expect(button.width, greaterThan(strip.width - 2 * AwSpace.x4));
      expect(button.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('targets stay at 48 at 1.0', (tester) async {
      await pumpBanner(tester, _off);
      expect(
        tester.getSize(find.byKey(const Key('alarm-banner-close'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byKey(const Key('alarm-banner-action'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('not shown while the permission prompt is up', (tester) async {
      final gateway = SupportGateway(_off);
      final container = await pumpBanner(tester, _off, gateway: gateway);
      expect(find.byKey(const Key('alarm-banner')), findsOneWidget);

      container.read(alarmPermissionAskProvider.notifier).begin();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('alarm-banner')),
        findsNothing,
        reason: 'ios/05: the red strip sat behind the OS prompt',
      );

      // The person allows it: the strip must not stay behind.
      gateway.support = const AlarmSupport(
        notificationsEnabled: true,
        criticalAlertsEnabled: false,
      );
      container.read(alarmPermissionAskProvider.notifier).end();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alarm-banner')), findsNothing);
    });

    testWidgets('a refusal at the prompt shows the strip after it closes', (
      tester,
    ) async {
      final gateway = SupportGateway(_off);
      final container = await pumpBanner(tester, _off, gateway: gateway);
      final probesBefore = gateway.probes;
      container.read(alarmPermissionAskProvider.notifier).begin();
      await tester.pumpAndSettle();
      container.read(alarmPermissionAskProvider.notifier).end();
      await tester.pumpAndSettle();
      expect(gateway.probes, greaterThan(probesBefore), reason: 're-probed');
      expect(find.byKey(const Key('alarm-banner')), findsOneWidget);
    });
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

    test('off the web, "off" is still the native problem (#19)', () {
      // Only the web gateway fills `webPermission`. A phone with notifications
      // off must keep the sheet that opens its own Settings page.
      const phone = AlarmSupport(
        notificationsEnabled: false,
        criticalAlertsEnabled: false,
      );
      expect(phone.webPermission, isNull);
      expect(phone.worstProblem, AlarmProblem.notificationsOff);
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

  // ── OPH-453 (#48, mobbin §2.5 "Son çalan cihazı kapatma") ────────────────
  //
  // Switching off the last ringing device is allowed (warn, never block), so
  // the account can end up with urgent alarms ringing nowhere. The band says
  // so and leads to the page that changes it.
  group('no device rings urgent alarms (OPH-453)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await localKv.remove(kAlarmBannerDismissedKey);
      await localKv.remove(kAlarmBannerDeviceDismissedKey);
    });
    tearDown(() async {
      await localKv.remove(kAlarmBannerDismissedKey);
      await localKv.remove(kAlarmBannerDeviceDismissedKey);
    });

    testWidgets(
      'the band says no device rings urgent alarms and links to Devices',
      (tester) async {
        final api = _DevicesApi([
          _device(_thisId, 'android', 'Pixel', rings: false),
          _device(_phoneId, 'ios', 'iPhone 16', rings: false),
        ]);
        final container = await _pumpBand(tester, api);

        final item = find.byKey(const Key('alarm-banner-no-device'));
        expect(item, findsOneWidget);
        expect(find.text('No device rings urgent alarms'), findsOneWidget);
        expect(find.text('Choose a device'), findsOneWidget);
        // A warning, like every strip in the band: amber tint, onSurface ink.
        final surface = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const Key('alarm-banner-no-device-surface')),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(surface.color, isNot(_theme.colorScheme.errorContainer));
        final action = tester.getSize(
          find.byKey(const Key('alarm-banner-pick-device')),
        );
        expect(action.height, greaterThanOrEqualTo(44));

        // The moment a device rings again — here, turned on from Devices,
        // which shares this list — the item is gone.
        await container
            .read(devicesProvider.notifier)
            .setRingsUrgent(_phoneId, true);
        await tester.pumpAndSettle();
        expect(item, findsNothing);

        // Off again, and "Cihaz seç" opens Settings ▸ Devices.
        await container
            .read(devicesProvider.notifier)
            .setRingsUrgent(_phoneId, false);
        await tester.pumpAndSettle();
        expect(item, findsOneWidget);
        await tester.tap(find.byKey(const Key('alarm-banner-pick-device')));
        await tester.pumpAndSettle();
        expect(find.text('devices-page'), findsOneWidget);
      },
    );

    testWidgets('Turkish copy', (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
      await _pumpBand(
        tester,
        _DevicesApi([_device(_thisId, 'android', 'Pixel', rings: false)]),
      );
      expect(find.text('Acil alarm çalan cihaz yok'), findsOneWidget);
      expect(find.text('Cihaz seç'), findsOneWidget);
    });

    testWidgets('a device that rings anywhere, an old server, an offline list '
        'or no session: nothing', (tester) async {
      final item = find.byKey(const Key('alarm-banner-no-device'));
      // Another device rings.
      await _pumpBand(
        tester,
        _DevicesApi([
          _device(_thisId, 'android', 'Pixel', rings: false),
          _device(_phoneId, 'ios', 'iPhone 16', rings: true),
        ]),
      );
      expect(item, findsNothing);

      // A server from before #48 sends no flag: everything rings as before.
      await tester.pumpWidget(const SizedBox());
      await _pumpBand(
        tester,
        _DevicesApi([_device(_thisId, 'android', 'Pixel', rings: null)]),
      );
      expect(item, findsNothing);

      // Unreachable with no list this session: nothing new appears.
      await tester.pumpWidget(const SizedBox());
      await _pumpBand(tester, _DevicesApi([])..unreachable = true);
      expect(item, findsNothing);

      // Signed out.
      await tester.pumpWidget(const SizedBox());
      await _pumpBand(
        tester,
        _DevicesApi([_device(_thisId, 'android', 'Pixel', rings: false)]),
        userId: null,
      );
      expect(item, findsNothing);
    });

    testWidgets('a list that went offline shows nothing new', (tester) async {
      final api = _DevicesApi([
        _device(_thisId, 'android', 'Pixel', rings: false),
        _device(_phoneId, 'ios', 'iPhone 16', rings: true),
      ]);
      final container = await _pumpBand(tester, api);
      // The phone was switched off elsewhere while this one lost its network:
      // the cached list cannot say so, and the band does not guess.
      api
        ..rows[1]['ringsUrgent'] = false
        ..unreachable = true;
      container.invalidate(devicesProvider);
      await tester.pumpAndSettle();
      expect(container.read(devicesProvider).value?.offline, isTrue);
      expect(find.byKey(const Key('alarm-banner-no-device')), findsNothing);
    });

    testWidgets('back in the foreground, the list is read again', (
      tester,
    ) async {
      final api = _DevicesApi([
        _device(_thisId, 'android', 'Pixel', rings: false),
        _device(_phoneId, 'ios', 'iPhone 16', rings: false),
      ]);
      await _pumpBand(tester, api);
      final item = find.byKey(const Key('alarm-banner-no-device'));
      expect(item, findsOneWidget);

      // Turned on from the phone itself while this app was in the background.
      api.rows[1]['ringsUrgent'] = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(item, findsNothing);
    });

    testWidgets('it goes before a permission problem and hides on its own', (
      tester,
    ) async {
      var now = DateTime.utc(2030, 6, 1, 9);
      final api = _DevicesApi([
        _device(_thisId, 'android', 'Pixel', rings: false),
      ]);
      await _pumpBand(tester, api, support: _off, clock: () => now);
      final item = find.byKey(const Key('alarm-banner-no-device'));
      final problem = find.byKey(const Key('alarm-banner'));
      expect(item, findsOneWidget);
      expect(problem, findsNothing, reason: 'one strip at a time');

      await tester.tap(find.byKey(const Key('alarm-banner-close')));
      await tester.pumpAndSettle();
      expect(item, findsNothing);
      expect(problem, findsOneWidget);

      // Closing the permission strip does not bring the device item back.
      await tester.tap(find.byKey(const Key('alarm-banner-close')));
      await tester.pumpAndSettle();
      expect(item, findsNothing);
      expect(problem, findsNothing);

      // A week later the account still has no ringing device: it says so.
      now = now.add(const Duration(days: 7, minutes: 1));
      await tester.pumpWidget(const SizedBox());
      await _pumpBand(tester, api, support: _off, clock: () => now);
      expect(item, findsOneWidget);
    });
  });
}

const _thisId = '01HZTHISDEVICEAAAAAAAAAAAA';
const _phoneId = '01HZPHONEAAAAAAAAAAAAAAAAA';

const _healthy = AlarmSupport(
  notificationsEnabled: true,
  criticalAlertsEnabled: false,
  exactAlarmsEnabled: true,
);

Map<String, dynamic> _device(
  String id,
  String platform,
  String name, {
  required bool? rings,
}) => {
  'id': id,
  'platform': platform,
  'deviceName': name,
  'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
  'createdAt': '2026-11-01T08:00:00.000Z',
  'ringsUrgent': ?rings,
  if (rings != null) 'ringsUrgentSource': 'user',
  'hasSession': true,
};

class _DevicesApi implements DeviceApi {
  _DevicesApi(this.rows);

  final List<Map<String, dynamic>> rows;
  bool unreachable = false;

  @override
  Future<List<DeviceInfo>> list() async {
    if (unreachable) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notification-devices'),
        type: DioExceptionType.connectionError,
      );
    }
    return [for (final row in rows) DeviceInfo.fromJson(row)];
  }

  @override
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  }) async {
    final row = rows.firstWhere((r) => r['id'] == deviceId);
    if (ringsUrgent != null) row['ringsUrgent'] = ringsUrgent;
    return DevicePatchResult(device: DeviceInfo.fromJson(row));
  }

  @override
  Future<DeviceInfo?> register(
    String deviceId,
    DeviceDescriptor device,
  ) async => null;

  @override
  Future<void> unregister(String deviceId) async {}

  @override
  Future<PushKeyLookup> lookupPushKey() async => const PushKeyLookup.unknown();
}

class _MemoryKv implements LocalKv {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> removeWhere(bool Function(String key) test) async =>
      values.removeWhere((key, _) => test(key));
}

/// The band as Home shows it, inside a router so "Cihaz seç" can go
/// somewhere, with the account's devices served by [api].
Future<ProviderContainer> _pumpBand(
  WidgetTester tester,
  _DevicesApi api, {
  AlarmSupport support = _healthy,
  DateTime Function()? clock,
  String? userId = 'user-1',
}) async {
  final container = ProviderContainer(
    overrides: [
      notificationsGatewayProvider.overrideWithValue(SupportGateway(support)),
      alarmLogProvider.overrideWithValue(_QuietLog()),
      if (clock != null) alarmClockProvider.overrideWithValue(clock),
      deviceApiProvider.overrideWithValue(api),
      currentUserIdProvider.overrideWithValue(userId),
      syncClientIdProvider.overrideWith((ref) => Stream.value(_thisId)),
      ringsUrgentStoreProvider.overrideWithValue(
        RingsUrgentStore(kv: _MemoryKv()),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(393, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const Scaffold(body: Column(children: [AlarmDegradationBanner()])),
      ),
      GoRoute(
        path: '/settings/devices',
        builder: (_, _) => const Scaffold(body: Text('devices-page')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: _theme, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
