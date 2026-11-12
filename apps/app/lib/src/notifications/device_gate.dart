import 'planner.dart';

/// Whether urgent alarms ring on THIS device (#48, OPH-446).
///
/// The server decides which of a person's devices ring
/// (`notification_devices.rings_urgent`); this is the device's cached copy of
/// that answer, in four states because "no answer" has two meanings:
///
///   • [on] / [off] — what the last register (or list) response said.
///   • [unknown] — a fresh sign-in or an account switch, before the register
///     response arrived. Urgent alarms come as ordinary notifications: a
///     newly signed-in device never rings before the server said it should.
///   • [legacy] — no answer will come: an install updated from a build before
///     #48 that restored its session (nothing stored yet), or a server that
///     does not know the field. It rings as it always did.
enum RingsUrgentHere { on, off, unknown, legacy }

/// The LocalKv key the state lives under. Read by the foreground, the overlay
/// and the headless pass alike, so they apply the same gate.
const String kRingsUrgentKey = 'alliswell_rings_urgent';

/// The stored string back to a state. A missing key is [RingsUrgentHere.legacy]:
/// every fresh sign-in WRITES [RingsUrgentHere.unknown] before its session is
/// exposed, so only an install that predates the key has none. A value this
/// build does not know never rings on a guess.
RingsUrgentHere ringsUrgentHereFromStored(String? stored) {
  if (stored == null) return RingsUrgentHere.legacy;
  for (final here in RingsUrgentHere.values) {
    if (here.name == stored) return here;
  }
  return RingsUrgentHere.unknown;
}

/// What a device row's `ringsUrgent` field means here: absent (an older
/// server) is [RingsUrgentHere.legacy], so the update changes nothing there.
RingsUrgentHere ringsUrgentHereFromServer(bool? ringsUrgent) =>
    switch (ringsUrgent) {
      true => RingsUrgentHere.on,
      false => RingsUrgentHere.off,
      null => RingsUrgentHere.legacy,
    };

/// The one gate every alarm path applies (OPH-446).
///
/// [RingsUrgentHere.off] and [RingsUrgentHere.unknown] turn each urgent alarm
/// into an ordinary reminder — same id, same time, same text — so nothing is
/// lost, it only stops ringing. [RingsUrgentHere.on] and
/// [RingsUrgentHere.legacy] return [alarms] itself, unchanged.
List<AlarmInput> forThisDevice(List<AlarmInput> alarms, RingsUrgentHere here) {
  if (here == RingsUrgentHere.on || here == RingsUrgentHere.legacy) {
    return alarms;
  }
  return [
    for (final alarm in alarms)
      if (!alarm.urgent && !alarm.requiresAcknowledgement)
        alarm
      else
        AlarmInput(
          reminderId: alarm.reminderId,
          taskId: alarm.taskId,
          taskTitle: alarm.taskTitle,
          remindAt: alarm.remindAt,
          status: alarm.status,
          urgent: false,
          requiresAcknowledgement: false,
          kind: alarm.kind,
          snoozeRound: alarm.snoozeRound,
          snoozedUntil: alarm.snoozedUntil,
        ),
  ];
}
