import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/persisted_prefs.dart';
import '../features/tasks/providers.dart';
import '../features/workspaces/workspaces.dart';
import '../router.dart';
import '../sync/db/database.dart';
import '../sync/providers.dart';
import 'actions.dart';
import 'alarm_log.dart';
import 'alarm_sound.dart';
import 'alarmkit.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'reminder_profile.dart';
import 'reminder_store.dart';
import 'sound_store.dart';
import 'scheduler.dart';

/// The OS adapter. Widget tests override this with a fake — the default
/// touches platform channels.
final notificationsGatewayProvider = Provider<NotificationsGateway>(
  (_) => LocalNotificationsGateway(),
);

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
