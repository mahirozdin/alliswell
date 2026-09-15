import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/persisted_prefs.dart';
import '../features/devices/data/device_api.dart';
import '../features/devices/providers.dart';
import '../features/tasks/providers.dart';
import '../i18n/i18n.dart';
import '../features/workspaces/workspaces.dart';
import '../router.dart';
import '../sync/db/database.dart';
import '../sync/providers.dart';
import 'actions.dart';
import 'web/alert_cache.dart';
import 'web/gateway_web.dart';
import 'web/push_host.dart';
import 'alarm_log.dart';
import 'alarm_sound.dart';
import 'alarmkit.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'reminder_profile.dart';
import 'reminder_store.dart';
import 'sound_store.dart';
import 'web_alert_mode.dart';
import 'scheduler.dart';

/// The OS adapter. Widget tests override this with a fake — the default
/// touches platform channels.
/// The gateway this platform can actually use.
///
/// Until OPH-313 this was `LocalNotificationsGateway()` with no platform guard
/// at all, including on the web — where `flutter_local_notifications` has no
/// implementation, so every call threw and the scheduler wrote a `degraded`
/// row. The browser gets a real gateway now; what it cannot do (schedule
/// locally) it says rather than swallows.
final notificationsGatewayProvider = Provider<NotificationsGateway>((ref) {
  if (!kIsWeb) return LocalNotificationsGateway();

  late final WebNotificationsGateway gateway;
  gateway = WebNotificationsGateway(
    host: createWebPushHost(),
    readVapidKey: () => ref.read(pushPublicKeyProvider.future),
    onSubscriptionChanged: () => unawaited(_publishSubscription(ref, gateway)),
    cache: createAlertCache(),
    // Read per notification rather than captured: the gateway outlives the
    // setting, and a tab that re-subscribed on every change would ask the
    // browser for a new endpoint each time somebody toggled a radio button.
    alertMode: () => ref.read(webAlertModeProvider),
    // The pair privacy mode already produces (`planner.dart:116-121`), so a
    // cache miss and a private device read identically rather than inventing a
    // third voice for the same moment.
    fallback: AlertText(title: 'AllisWell', body: 'notif.privateBody'.tr()),
  );
  // A tab that was already subscribed in an earlier session has one now, and
  // the registry needs to carry it on the first heartbeat rather than the one
  // after somebody happens to press the button again.
  unawaited(_publishSubscription(ref, gateway));
  // Turning delivery off has to reach the browser, not just the preference:
  // the subscription IS the thing the server sends to. One listener, so the
  // settings screen stays a screen.
  ref.listen<WebAlertMode>(
    webAlertModeProvider,
    (previous, next) => unawaited(gateway.applyAlertMode(next)),
  );
  ref.onDispose(gateway.dispose);
  return gateway;
});

/// Hands the browser's subscription to the device registry, then asks it to
/// send. One direction only: notifications knows about devices, not the
/// reverse.
Future<void> _publishSubscription(
  Ref ref,
  WebNotificationsGateway gateway,
) async {
  final subscription = await gateway.subscription();
  ref
      .read(devicePushCredentialsProvider.notifier)
      .set(
        subscription == null
            ? null
            : DevicePushCredentials.webPush(
                endpoint: subscription.endpoint,
                p256dh: subscription.p256dh,
                auth: subscription.auth,
              ),
      );
  await ref.read(deviceRegistryProvider).sync(signedIn: true);
}

/// iOS 26+ AlarmKit bridge (OPH-141, the URGENT lane that rings through the
/// mute switch). Tests override with a fake; the default talks to
/// `MethodChannel('alliswell/alarmkit')` and reports unsupported everywhere
/// else, so the scheduler keeps urgent alarms on notifications.
final alarmKitHostProvider = Provider<AlarmKitHost>(
  (_) => MethodChannelAlarmKitHost(),
);

/// The user's re-alert chain (OPH-179, DESIGN §18). Device-local, like every
/// other delivery preference: each device schedules its own notifications, so
/// each device owns how insistent they are.
final reminderProfileRawProvider = NotifierProvider<PersistedChoice, String>(
  // Empty parses to the factory chain, so an upgrade changes nothing.
  () => PersistedChoice('alliswell_reminder_profile', fallback: ''),
);

/// The parsed profile — junk resolves to [ReminderProfile.factory].
final reminderProfileProvider = Provider<ReminderProfile>(
  (ref) => ReminderProfile.parse(ref.watch(reminderProfileRawProvider)),
);

/// The order the snooze presets appear in on the alarm screen (N4 — the one
/// list where dragging is meaningful).
final snoozePresetOrderRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(
    'alliswell_snooze_presets',
    fallback: '5_min,30_min,1_hour,tomorrow_morning',
  ),
);

final snoozePresetOrderProvider = Provider<List<String>>(
  (ref) => parseSnoozePresetOrder(ref.watch(snoozePresetOrderRawProvider)),
);

/// Which sound each lane plays (OPH-181). Device-local: the sound file lives on
/// THIS device, and the library it can be chosen from is the workspace's.
final alarmSoundRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_alarm_sound', fallback: 'bundled:aw_alarm'),
);

/// Ordinary reminders keep the OS sound until the user says otherwise.
final reminderSoundRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_reminder_sound', fallback: 'os'),
);

/// How loud this BROWSER is (OPH-316). Device-local like every other delivery
/// preference, and the one the office asked for: the window without the sound.
/// Meaningless off the web — nothing reads it there.
final webAlertModeRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_web_alert_mode', fallback: 'silent'),
);

final webAlertModeProvider = Provider<WebAlertMode>(
  (ref) => WebAlertMode.parse(ref.watch(webAlertModeRawProvider)),
);

/// Whether the ring screen should open DECLARED silent (OPH-316): the user
/// asked this browser to be quiet, and the screen has to say so rather than
/// look like an alarm that failed. A provider rather than a `kIsWeb` read
/// inside the screen, because `kIsWeb` is a const `false` in a VM test and the
/// behaviour would then be untestable off the browser.
final alarmSilentByChoiceProvider = Provider<bool>(
  (ref) => kIsWeb && ref.watch(webAlertModeProvider) == WebAlertMode.silent,
);

/// Whether the browser will make a sound whatever the setting says (Firefox).
/// Asked through the gateway rather than by building a second host: the web
/// host installs a `serviceWorker.onmessage` handler, and two of those would
/// deliver every notification click twice.
final webIgnoresSilenceProvider = Provider<bool>((ref) {
  final gateway = ref.watch(notificationsGatewayProvider);
  return gateway is WebNotificationsGateway && gateway.ignoresSilence;
});

final alarmSoundChoiceProvider = Provider<AwSoundChoice>(
  (ref) => AwSoundChoice.parse(ref.watch(alarmSoundRawProvider)),
);

final reminderSoundChoiceProvider = Provider<AwSoundChoice>(
  (ref) => AwSoundChoice.parse(ref.watch(reminderSoundRawProvider)),
);

/// Resolves a choice into what this platform's notification lane can play.
final alarmSoundResolverProvider = Provider<AlarmSoundResolver>(
  (ref) => AlarmSoundResolver(
    store: soundStore,
    isIos: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
    isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  ),
);

/// OPH-064: lock-screen privacy — generic notification content instead of
/// task titles. Persisted per device.
final notificationPrivacyProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('notification_privacy', fallback: false),
);

/// The device's alarm record (OPH-176, DESIGN §11 A6). Local only — it lives in
/// the replica database but is neither synced nor pushed.
final alarmLogProvider = Provider<AlarmLog>(
  (ref) => AlarmLog(ref.watch(databaseProvider)),
);

/// The log's newest rows, for the diagnostic screen.
final alarmLogRowsProvider = StreamProvider<List<AlarmEvent>>(
  (ref) => ref.watch(alarmLogProvider).watchRecent(),
);

final reminderStoreProvider = Provider<ReminderStore>(
  (ref) => ReminderStore(
    ref.watch(databaseProvider),
    () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);

/// A one-shot probe of what alarm delivery the OS currently allows (OPH-139
/// [AlarmSupport]) — feeds the honest degradation banner (OPH-143). Invalidate
/// to re-probe (e.g. after the user returns from the permission flow).
final alarmSupportProvider = FutureProvider.autoDispose<AlarmSupport>((
  ref,
) async {
  final gateway = ref.watch(notificationsGatewayProvider);
  try {
    await gateway.initialize();
    final support = await gateway.alarmSupport();
    // Never fail silently (NOTIFICATIONS §1): a device that cannot ring properly
    // says so on Home and in Settings — and now leaves a record too (OPH-176),
    // so "it didn't go off" can be checked against what the OS allowed.
    if (!support.notificationsEnabled || support.exactAlarmsEnabled == false) {
      // Fire-and-forget behind its OWN guard: a diagnostic must never change
      // what the probe reports. (It did once, in the making — an unavailable
      // database made the whole probe fail, so a device with alarms OFF looked
      // healthy. That is the exact lie A6 exists to prevent.)
      try {
        unawaited(
          ref
              .read(alarmLogProvider)
              .record(
                event: AlarmLogEvent.degraded,
                lane: AlarmLogLane.notification,
                detail:
                    'notifications=${support.notificationsEnabled} '
                    'exactAlarms=${support.exactAlarmsEnabled} '
                    'critical=${support.criticalAlertsEnabled}',
              ),
        );
      } on Object {
        // No log available (no database on this surface) — the probe stands.
      }
    }
    return support;
  } catch (_) {
    // Web / no platform channel: assume permissive so we never nag falsely.
    return const AlarmSupport(
      notificationsEnabled: true,
      criticalAlertsEnabled: false,
    );
  }
});

/// One scheduler per signed-in workspace: keeps the OS schedule equal to the
/// replica (OPH-061) and routes notification taps/actions into the stores
/// (OPH-062/063). Rebuilt when the privacy setting flips (OPH-064) so
/// content re-renders under the new policy.
final notificationSchedulerProvider = Provider<NotificationScheduler?>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  final gateway = ref.watch(notificationsGatewayProvider);
  final alarmKit = ref.watch(alarmKitHostProvider);

  final scheduler = NotificationScheduler(
    gateway: gateway,
    alarmKit: alarmKit,
    alarms: ref.watch(reminderStoreProvider).watchAlarms(workspace.id),
    privacyMode: ref.watch(notificationPrivacyProvider),
    log: ref.watch(alarmLogProvider),
    profile: ref.watch(reminderProfileProvider),
    sounds: ref.watch(alarmSoundResolverProvider),
    alarmSound: ref.watch(alarmSoundChoiceProvider),
    reminderSound: ref.watch(reminderSoundChoiceProvider),
    // The AlarmKit alert has room for ONE snooze button (OPH-182), so it offers
    // whichever the user put first in their own order.
    snoozePreset: ref.watch(snoozePresetOrderProvider).first,
    // Round 19 K3: NOTIFICATIONS §2 has always said the window re-fills "on
    // every app foreground", and nothing was doing it — the plan only ever
    // moved when the replica emitted. Injected rather than reached for inside
    // the scheduler so a pure scheduler test needs no `WidgetsBinding`.
    onForeground: (onResume) {
      final listener = AppLifecycleListener(onResume: onResume);
      return listener.dispose;
    },
  );
  unawaited(scheduler.start());
  ref.onDispose(scheduler.dispose);

  // Taps/actions from EITHER lane route through the one handler — an AlarmKit
  // "Onayla"/"Ertele" is the same acknowledge/snooze as a notification button.
  void onEvent(NotificationEvent event) => handleNotificationEvent(
    event,
    tasks: ref.read(taskStoreProvider),
    reminders: ref.read(reminderStoreProvider),
    navigate: (location) => ref.read(routerProvider).push(location),
    log: ref.read(alarmLogProvider),
  );
  final responses = gateway.events.listen(onEvent);
  ref.onDispose(responses.cancel);
  final alarmKitResponses = alarmKit.events.listen(onEvent);
  ref.onDispose(alarmKitResponses.cancel);

  return scheduler;
});
