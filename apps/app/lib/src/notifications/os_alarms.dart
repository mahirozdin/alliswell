import 'alarmkit.dart';
import 'gateway.dart';

/// Takes every alarm this install holds out of the OS, scheduled or already
/// presented: what a revoked session leaves behind (OPH-447,
/// revocation-leaves-delivered-alarm). Nobody is signed in to answer an alarm
/// any more, so one ringing now is silenced too — an Android notification
/// looping its sound is cancelled with the rest, an alerting AlarmKit alarm is
/// stopped before it is cancelled.
///
/// Best effort per lane; never throws. [alarmKit] is null where there is no
/// AlarmKit to ask (the Android background turn).
Future<void> dropEveryOsAlarm({
  required NotificationsGateway gateway,
  AlarmKitHost? alarmKit,
}) async {
  try {
    await gateway.initialize();
    await gateway.cancelAll();
  } on Object {
    // A plugin that cannot clear everything at once: one id at a time, the
    // presented ones included.
    try {
      for (final id in await gateway.pendingIds()) {
        await gateway.cancel(id);
      }
      for (final shown in await gateway.activeNotifications()) {
        await gateway.cancel(shown.id);
      }
    } on Object {
      // No plugin on this platform, or the OS refused: nothing more to do.
    }
  }
  if (alarmKit == null) return;
  final List<AlarmKitScheduled> alarms;
  try {
    alarms = await alarmKit.scheduledAlarms();
  } on Object {
    // AlarmKit is iOS 26+ only; elsewhere the channel is missing.
    return;
  }
  for (final alarm in alarms) {
    try {
      if (alarm.state == AlarmKitAlarmState.alerting) {
        await alarmKit.stop(alarm.id);
      }
      await alarmKit.cancel(alarm.id);
    } on Object {
      // One alarm the OS would not take back does not keep the others.
    }
  }
}
