import 'package:drift/drift.dart';

import '../sync/db/database.dart';
import '../sync/outbox.dart';
import 'planner.dart';

/// Local-first reminder access (OPH-061/063): live alarms come from the
/// replica (reminders ⋈ tasks — reminder rows carry no workspace id), and an
/// acknowledge is an optimistic local write + outbox mutation, exactly like
/// every other write since OPH-054.
class ReminderStore {
  ReminderStore(this._db, this._poke);

  final AwDatabase _db;
  final void Function() _poke;

  /// Every alarm that may still fire, joined with its task for rendering.
  Stream<List<AlarmInput>> watchAlarms(String workspaceId) {
    final query =
        (_db.select(_db.reminders)..where(
              (r) => r.status.isIn(const ['scheduled', 'snoozed', 'delivered']),
            ))
            .join([
              innerJoin(
                _db.tasks,
                _db.tasks.id.equalsExp(_db.reminders.taskId),
              ),
            ])
          ..where(_db.tasks.workspaceId.equals(workspaceId));

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          _toAlarm(row.readTable(_db.reminders), row.readTable(_db.tasks)),
      ],
    );
  }

  AlarmInput _toAlarm(Reminder reminder, TaskRecord task) => AlarmInput(
    reminderId: reminder.id,
    taskId: task.id,
    taskTitle: task.title,
    remindAt: reminder.remindAt.toUtc(),
    status: reminder.status,
    urgent: reminder.alarmLevel == 'urgent',
    requiresAcknowledgement: reminder.requiresAcknowledgement,
    snoozedUntil: reminder.snoozedUntil?.toUtc(),
  );

  /// Acknowledge an urgent alarm (OPH-063): local row flips immediately (the
  /// planner drops its whole chain), the outbox mutation replays it on the
  /// server whenever connectivity allows.
  Future<void> acknowledge(String reminderId) async {
    final joined =
        await ((_db.select(
              _db.reminders,
            )..where((r) => r.id.equals(reminderId))).join([
              innerJoin(
                _db.tasks,
                _db.tasks.id.equalsExp(_db.reminders.taskId),
              ),
            ]))
            .getSingleOrNull();
    if (joined == null) return;
    final reminder = joined.readTable(_db.reminders);
    final task = joined.readTable(_db.tasks);
    if (reminder.status == 'cancelled' ||
        reminder.status == 'completed' ||
        reminder.status == 'acknowledged') {
      return;
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.reminders,
      )..where((r) => r.id.equals(reminderId))).write(
        RemindersCompanion(
          status: const Value('acknowledged'),
          acknowledgedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: task.workspaceId,
        entityType: 'reminder',
        entityId: reminderId,
        operation: 'update',
        patch: {'status': 'acknowledged'},
      );
    });
    _poke();
  }
}
