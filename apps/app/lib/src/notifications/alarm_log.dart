import 'package:drift/drift.dart';

import '../sync/db/database.dart';
import 'gateway.dart';

/// Alarm-log event names (OPH-176). Deliberately small: this log records what
/// we DID and what the user DID, never what we hope the OS did.
abstract final class AlarmLogEvent {
  /// We asked the OS to ring at an instant.
  static const scheduled = 'scheduled';

  /// We took a pending alarm back (acknowledged, completed, re-planned).
  static const cancelled = 'cancelled';

  /// The user touched a delivered notification (the only proof of delivery iOS
  /// ever gives us).
  static const interacted = 'interacted';

  /// The user pressed one of its buttons.
  static const action = 'action';

  /// The in-app ring screen took over the screen.
  static const ringShown = 'ring_shown';

  /// We know delivery is degraded (permission off, exact alarms denied, a sound
  /// the OS could not resolve).
  static const degraded = 'degraded';
}

/// Which surface an event belongs to.
abstract final class AlarmLogLane {
  static const notification = 'notification';
  static const alarmkit = 'alarmkit';
  static const inapp = 'inapp';
}

/// The device's own alarm record (DESIGN §11 A6, NOTIFICATIONS §6).
///
/// Round 9 cost an evening to a question we could not answer — *which* lane
/// fired, with *which* sound, at *which* slot. From now on the device keeps a
/// ring buffer of [kAlarmLogLimit] rows, local only: it never syncs, never
/// leaves the device, and never claims a delivery it cannot observe.
class AlarmLog {
  AlarmLog(this._db);

  final AwDatabase _db;

  /// Records one event, then trims the buffer. Never throws: a diagnostic that
  /// can break alarm scheduling would be worse than no diagnostic at all.
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
  }) async {
    try {
      await _db
          .into(_db.alarmEvents)
          .insert(
            AlarmEventsCompanion.insert(
              at: (at ?? DateTime.now()).toUtc(),
              event: event,
              lane: lane,
              kind: Value(kind),
              slotIndex: Value(slotIndex),
              urgent: Value(urgent),
              sound: Value(sound),
              level: Value(level),
              fireAt: Value(fireAt?.toUtc()),
              taskId: Value(taskId),
              reminderId: Value(reminderId),
              detail: Value(detail),
            ),
          );
      await _trim();
    } on Object {
      // Swallowed on purpose — see the doc comment.
    }
  }

  /// Convenience for the notification/AlarmKit lanes: everything a planned
  /// alarm knows, plus what the gateway said it asked for.
  Future<void> recordScheduled(
    PlannedNotification notification, {
    required String lane,
    required ScheduledDelivery delivery,
    String? kind,
    int? slotIndex,
    String? taskId,
    String? reminderId,
  }) => record(
    event: AlarmLogEvent.scheduled,
    lane: lane,
    kind: kind,
    slotIndex: slotIndex,
    urgent: notification.urgent,
    sound: delivery.sound,
    level: delivery.level,
    fireAt: notification.fireAt,
    taskId: taskId,
    reminderId: reminderId,
  );

  /// Newest first. The Settings screen watches this.
  Stream<List<AlarmEvent>> watchRecent({int limit = kAlarmLogLimit}) =>
      (_db.select(_db.alarmEvents)
            ..orderBy([(e) => OrderingTerm.desc(e.at)])
            ..limit(limit))
          .watch();

  Future<List<AlarmEvent>> recent({int limit = kAlarmLogLimit}) =>
      (_db.select(_db.alarmEvents)
            ..orderBy([(e) => OrderingTerm.desc(e.at)])
            ..limit(limit))
          .get();

  Future<void> clear() => _db.delete(_db.alarmEvents).go();

  /// Ring buffer: drop everything older than the newest [kAlarmLogLimit].
  Future<void> _trim() async {
    final keep =
        await (_db.select(_db.alarmEvents)
              ..orderBy([(e) => OrderingTerm.desc(e.at)])
              ..limit(kAlarmLogLimit))
            .get();
    if (keep.length < kAlarmLogLimit) return;
    final cutoff = keep.last.at;
    await (_db.delete(
      _db.alarmEvents,
    )..where((e) => e.at.isSmallerThanValue(cutoff))).go();
  }
}

/// One line of the log, as the diagnostic screen (and a copy-paste into a bug
/// report) shows it. Data only — no localization, on purpose: this is the part
/// a developer reads.
String formatAlarmLogLine(AlarmEvent e) {
  final parts = <String>[
    e.at.toIso8601String(),
    e.event,
    e.lane,
    if (e.kind != null) e.kind!,
    if (e.slotIndex != null) 'slot ${e.slotIndex}',
    if (e.urgent) 'urgent',
    if (e.sound != null) 'sound=${e.sound}',
    if (e.level != null) 'level=${e.level}',
    if (e.fireAt != null) 'fireAt=${e.fireAt!.toIso8601String()}',
    if (e.reminderId != null) 'reminder=${e.reminderId}',
    if (e.detail != null) e.detail!,
  ];
  return parts.join(' · ');
}
