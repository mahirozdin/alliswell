import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/persisted_prefs.dart';
import '../features/tasks/providers.dart';
import '../features/workspaces/workspaces.dart';
import '../router.dart';
import '../sync/providers.dart';
import 'actions.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'reminder_store.dart';
import 'scheduler.dart';

/// The OS adapter. Widget tests override this with a fake — the default
/// touches platform channels.
final notificationsGatewayProvider = Provider<NotificationsGateway>(
  (_) => LocalNotificationsGateway(),
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

/// One scheduler per signed-in workspace: keeps the OS schedule equal to the
/// replica (OPH-061) and routes notification taps/actions into the stores
/// (OPH-062/063). Rebuilt when the privacy setting flips (OPH-064) so
/// content re-renders under the new policy.
final notificationSchedulerProvider = Provider<NotificationScheduler?>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  final gateway = ref.watch(notificationsGatewayProvider);

  final scheduler = NotificationScheduler(
    gateway: gateway,
    alarms: ref.watch(reminderStoreProvider).watchAlarms(workspace.id),
    privacyMode: ref.watch(notificationPrivacyProvider),
  );
  unawaited(scheduler.start());
  ref.onDispose(scheduler.dispose);

  final responses = gateway.events.listen(
    (event) => handleNotificationEvent(
      event,
      tasks: ref.read(taskStoreProvider),
      reminders: ref.read(reminderStoreProvider),
      navigate: (location) => ref.read(routerProvider).push(location),
    ),
  );
  ref.onDispose(responses.cancel);

  return scheduler;
});
