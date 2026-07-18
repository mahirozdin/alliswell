import 'package:drift/drift.dart';

import '../sync/db/database.dart';
import '../sync/outbox.dart';
import '../sync/streams.dart';
import 'planner.dart';

/// Reminder-id prefix for alarms derived straight from a task row while the
/// server's reminder is still in flight (see [ReminderStore.watchAlarms]).
const kSyntheticReminderPrefix = 'local:';

/// Local-first reminder access (OPH-061/063): live alarms come from the
/// replica (reminders ⋈ tasks — reminder rows carry no workspace id), and an
/// acknowledge is an optimistic local write + outbox mutation, exactly like
/// every other write since OPH-054.
class ReminderStore {
  ReminderStore(this._db, this._poke);

  final AwDatabase _db;
  final void Function() _poke;

  /// Every alarm that may still fire, joined with its task for rendering.
  ///
  /// Two sources merge (feedback round 6):
  /// - **Reminder rows** (server-created, synced down) — canonical.
  /// - **Synthetic alarms** derived from tasks that want one — an explicit
  ///   `remindAt`, or an URGENT task's `dueAt` (mirroring the server's
  ///   `effectiveRemindAt`) — whose reminder row has not arrived yet. The
  ///   alarm rings on time even offline or mid-sync; when the real row lands
  ///   the same task drops its synthetic twin and the scheduler's
  ///   content-hash diff swaps them seamlessly. A task with ANY reminder row
  ///   (even a terminal one) never synthesizes — an acknowledged alarm must
  ///   stay acknowledged.
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

    final fromRows = query.watch().map(
      (rows) => [
        for (final row in rows)
          _toAlarm(row.readTable(_db.reminders), row.readTable(_db.tasks)),
      ],
    );

    // Tasks that want an alarm (server parity: remind_at ?? urgent's due_at),
    // in a state where one may fire.
    final wanting =
        (_db.select(_db.tasks)..where(
              (t) =>
                  t.workspaceId.equals(workspaceId) &
                  t.status.isNotIn(const [
                    'completed',
                    'cancelled',
                    'archived',
                  ]) &
                  (t.remindAt.isNotNull() |
                      (t.isUrgent.equals(true) & t.dueAt.isNotNull())),
            ))
            .watch();

    // Task ids that already own a reminder row in ANY status.
    final covered = _db
        .select(_db.reminders)
        .watch()
        .map((rows) => {for (final r in rows) r.taskId});

    return combineLatest3(
      fromRows,
      wanting,
      covered,
      (alarms, tasks, ownedTaskIds) => [
        ...alarms,
        for (final task in tasks)
          if (!ownedTaskIds.contains(task.id)) _syntheticAlarm(task),
      ],
    );
  }

  /// The task-derived stand-in for a reminder row that has not synced yet.
  AlarmInput _syntheticAlarm(TaskRecord task) => AlarmInput(
    reminderId: '$kSyntheticReminderPrefix${task.id}',
    taskId: task.id,
    taskTitle: task.title,
    remindAt: (task.remindAt ?? task.dueAt!).toUtc(),
    status: task.snoozedUntil == null ? 'scheduled' : 'snoozed',
    urgent: task.isUrgent,
    requiresAcknowledgement: task.requiresAcknowledgement,
    snoozedUntil: task.snoozedUntil?.toUtc(),
  );

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
  ///
  /// A SYNTHETIC id (task-derived alarm, row still in flight) resolves to the
  /// task's active reminder row — by tap time it has usually synced down. If
  /// no row exists yet (fully offline), this no-ops: complete/snooze still
  /// work through the task, and the chain stops at its last slot.
  Future<void> acknowledge(String reminderId) async {
    var id = reminderId;
    if (reminderId.startsWith(kSyntheticReminderPrefix)) {
      final taskId = reminderId.substring(kSyntheticReminderPrefix.length);
      final active =
          await (_db.select(_db.reminders)
                ..where(
                  (r) =>
                      r.taskId.equals(taskId) &
                      r.status.isIn(const [
                        'scheduled',
                        'snoozed',
                        'delivered',
                      ]),
                )
                ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (active == null) return;
      id = active.id;
    }

    final joined =
        await ((_db.select(_db.reminders)..where((r) => r.id.equals(id))).join([
          innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.reminders.taskId)),
        ])).getSingleOrNull();
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
      )..where((r) => r.id.equals(reminder.id))).write(
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
        entityId: reminder.id,
        operation: 'update',
        patch: {'status': 'acknowledged'},
      );
    });
    _poke();
  }
}
