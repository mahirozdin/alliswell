import 'dart:convert';

import '../i18n/i18n.dart';
import 'gateway.dart';

/// What the planner needs to know about one alarm — a reminder row joined
/// with its task (title for rendering, urgency for the chain).
class AlarmInput {
  const AlarmInput({
    required this.reminderId,
    required this.taskId,
    required this.taskTitle,
    required this.remindAt,
    required this.status,
    required this.urgent,
    required this.requiresAcknowledgement,
    this.snoozedUntil,
  });

  final String reminderId;
  final String taskId;
  final String taskTitle;
  final DateTime remindAt;

  /// scheduled | snoozed | delivered (anything else never reaches the planner,
  /// and gets filtered defensively if it does).
  final String status;
  final bool urgent;
  final bool requiresAcknowledgement;
  final DateTime? snoozedUntil;
}

/// Re-alert offsets for urgent alarms (NOTIFICATIONS.md §2): iOS has no
/// background timers, so "ring until acknowledged" is pre-scheduled as a
/// chain and cancelled on acknowledge — Android uses the same shape for
/// symmetry. 5 slots per alarm respects iOS's 64-pending cap.
const kUrgentChainOffsets = [
  Duration.zero,
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 30),
];

const _activeStatuses = {'scheduled', 'snoozed', 'delivered'};

/// Pure planning (OPH-061/063/064): alarms in, desired OS notifications out.
/// Windowed to [maxPending] soonest fire-times — iOS silently drops beyond 64
/// pending requests, so we keep well under (NOTIFICATIONS.md §2) and re-fill
/// as time passes. Past instants are skipped (the OS cannot schedule them; if
/// they were scheduled earlier, they already fired).
List<PlannedNotification> planNotifications({
  required List<AlarmInput> alarms,
  required DateTime now,
  required bool privacyMode,
  int maxPending = 40,
}) {
  final planned = <PlannedNotification>[];

  for (final alarm in alarms) {
    if (!_activeStatuses.contains(alarm.status)) continue;
    final base =
        (alarm.status == 'snoozed' ? alarm.snoozedUntil : null) ??
        alarm.remindAt;
    final chain = alarm.urgent && alarm.requiresAcknowledgement
        ? kUrgentChainOffsets
        : const [Duration.zero];

    for (final (index, offset) in chain.indexed) {
      final fireAt = base.add(offset).toUtc();
      if (!fireAt.isAfter(now)) continue;

      // Privacy mode (OPH-064, BLUEPRINT §8.3): nothing personal on the lock
      // screen — the tap still deep-links to the task.
      final title = privacyMode
          ? 'AllisWell'
          : (alarm.urgent ? '⏰ ${alarm.taskTitle}' : alarm.taskTitle);
      final body = privacyMode
          ? 'notif.privateBody'.tr()
          : (alarm.urgent
                ? (index == 0
                      ? 'notif.urgentFirst'.tr()
                      : 'notif.urgentRepeat'.tr(
                          args: {'count': '${index + 1}'},
                        ))
                : 'notif.reminder'.tr());

      final payload = jsonEncode({
        'taskId': alarm.taskId,
        'reminderId': alarm.reminderId,
        'chainIndex': index,
      });
      planned.add(
        PlannedNotification(
          id: notificationIdFor(
            '${alarm.reminderId}|$index|${fireAt.millisecondsSinceEpoch}|$title|$body|${alarm.urgent}',
          ),
          title: title,
          body: body,
          fireAt: fireAt,
          urgent: alarm.urgent,
          payload: payload,
        ),
      );
    }
  }

  planned.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return planned.length > maxPending ? planned.sublist(0, maxPending) : planned;
}
