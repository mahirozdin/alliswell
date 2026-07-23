import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/persisted_prefs.dart';
import '../features/tasks/providers.dart';
import '../features/workspaces/workspaces.dart';
import '../router.dart';
import '../sync/providers.dart';
import 'actions.dart';
import 'alarmkit.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'reminder_store.dart';
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

/// OPH-064: lock-screen privacy — generic notification content instead of
/// task titles. Persisted per device.
final notificationPrivacyProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('notification_privacy', fallback: false),
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
    return await gateway.alarmSupport();
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
  );
  final responses = gateway.events.listen(onEvent);
  ref.onDispose(responses.cancel);
  final alarmKitResponses = alarmKit.events.listen(onEvent);
  ref.onDispose(alarmKitResponses.cancel);

  return scheduler;
});
