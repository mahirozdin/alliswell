import 'dart:convert';

import '../features/tasks/data/task_store.dart';
import 'gateway.dart';
import 'reminder_store.dart';

/// Notification action ids (OPH-062/063). Snooze presets mirror the server's
/// (BLUEPRINT §4.9); "custom" is the plain tap — it opens the task detail
/// where every date control lives.
const kActionComplete = 'complete';
const kActionAcknowledge = 'acknowledge';
const kActionSnoozePrefix = 'snooze:';

String snoozeActionId(String preset) => '$kActionSnoozePrefix$preset';

/// Routes one notification interaction into the local-first stores — the
/// writes are ordinary outbox mutations, so they work identically online and
/// offline (the checklist's "call endpoint when online; enqueue when offline"
/// collapses into a single path since OPH-054).
Future<void> handleNotificationEvent(
  NotificationEvent event, {
  required TaskStore tasks,
  required ReminderStore reminders,
  required void Function(String location) navigate,
}) async {
  final raw = event.payload;
  if (raw == null || raw.isEmpty) return;
  Map<String, dynamic> payload;
  try {
    payload = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return; // not ours / corrupted — never crash on a notification tap
  }
  final taskId = payload['taskId'] as String?;
  final reminderId = payload['reminderId'] as String?;
  if (taskId == null) return;

  final action = event.actionId ?? '';
  if (action.isEmpty) {
    navigate('/tasks/$taskId');
    return;
  }
  if (action == kActionComplete) {
    await tasks.complete(taskId);
    return;
  }
  if (action == kActionAcknowledge) {
    if (reminderId != null) await reminders.acknowledge(reminderId);
    return;
  }
  if (action.startsWith(kActionSnoozePrefix)) {
    await tasks.snooze(
      taskId,
      preset: action.substring(kActionSnoozePrefix.length),
    );
  }
}
