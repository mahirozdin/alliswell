import 'package:drift/drift.dart';

import '../sync/db/database.dart';
import '../sync/outbox.dart';
import '../sync/streams.dart';
import 'planner.dart';

/// Reminder-id prefix for alarms derived straight from a task row while the
/// server's reminder is still in flight (see [ReminderStore.watchAlarms]).
/// The full shape is `local:<kind>:<taskId>` — a task can be waiting for TWO
/// rows at once (OPH-175), so the kind has to be part of the identity.
const kSyntheticReminderPrefix = 'local:';

/// The two alarms a task can own, in the server's order (`db/reminders.js`).
const kAlarmKinds = ['remind', 'due'];

/// Synthetic id for [taskId]'s [kind] alarm.
String syntheticReminderId(String kind, String taskId) =>
    '$kSyntheticReminderPrefix$kind:$taskId';

/// `(kind, taskId)` from a synthetic id, or null when it is a real reminder id.
/// Tolerates the pre-OPH-175 shape (`local:<taskId>`) so an id that outlived an
/// upgrade still resolves — it means the reminder kind.
({String kind, String taskId})? parseSyntheticReminderId(String id) {
  if (!id.startsWith(kSyntheticReminderPrefix)) return null;
  final rest = id.substring(kSyntheticReminderPrefix.length);
  final split = rest.indexOf(':');
  if (split < 0) return (kind: 'remind', taskId: rest);
  return (kind: rest.substring(0, split), taskId: rest.substring(split + 1));
}

/// The app's mirror of the server's `alarmInstantsFor` (NOTIFICATIONS §5a): the
/// alarms a task should have RIGHT NOW.
///
/// - `remind` whenever `remindAt` is set;
/// - `due` when the task is URGENT and has a deadline — **even alongside a
///   reminder** (round 9's correction: a nudge does not replace a deadline);
/// - both equal → only `remind`, because one moment must never ring twice;
/// - a task in a terminal state has none.
List<({String kind, DateTime at})> taskAlarmInstants(TaskRecord task) {
  const silenced = {'completed', 'cancelled', 'archived'};
  if (silenced.contains(task.status)) return const [];
  final instants = <({String kind, DateTime at})>[];
  final remindAt = task.remindAt;
  final dueAt = task.dueAt;
  if (remindAt != null) instants.add((kind: 'remind', at: remindAt));
  if (task.isUrgent && dueAt != null) instants.add((kind: 'due', at: dueAt));
  if (instants.length == 2 && instants[0].at.isAtSameMomentAs(instants[1].at)) {
    return [instants[0]];
  }
  return instants;
}

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
  /// Two sources merge (feedback round 6, extended in round 9):
  /// - **Reminder rows** (server-created, synced down) — canonical, each
  ///   carrying its `kind`.
  /// - **Synthetic alarms** derived from the task row for a kind whose reminder
  ///   row has not arrived yet ([taskAlarmInstants] mirrors the server's
  ///   `alarmInstantsFor`). The alarm rings on time even offline or mid-sync;
  ///   when the real row lands, that kind drops its synthetic twin and the
  ///   scheduler's content-hash diff swaps them seamlessly.
  ///
  /// A task that owns a reminder row of a kind in ANY status never synthesizes
  /// THAT kind — an acknowledged alarm must stay acknowledged. Per kind, since
  /// acknowledging the 22:42 nudge says nothing about the 22:45 deadline.
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

    // Tasks that want at least one alarm, in a state where one may fire. The
    // per-kind decision is [taskAlarmInstants]'; this only narrows the query.
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

    // '<taskId>|<kind>' pairs that already own a reminder row in ANY status.
    final covered = _db
        .select(_db.reminders)
        .watch()
        .map((rows) => {for (final r in rows) '${r.taskId}|${r.kind}'});

    return combineLatest3(
      fromRows,
      wanting,
      covered,
      (alarms, tasks, ownedKinds) => [
        ...alarms,
        for (final task in tasks)
          for (final instant in taskAlarmInstants(task))
            if (!ownedKinds.contains('${task.id}|${instant.kind}'))
              _syntheticAlarm(task, instant.kind, instant.at),
      ],
    );
  }

  /// The task-derived stand-in for a reminder row that has not synced yet.
  AlarmInput _syntheticAlarm(TaskRecord task, String kind, DateTime at) =>
      AlarmInput(
        reminderId: syntheticReminderId(kind, task.id),
        taskId: task.id,
        taskTitle: task.title,
        kind: kind,
        remindAt: at.toUtc(),
        status: task.snoozedUntil == null ? 'scheduled' : 'snoozed',
        urgent: task.isUrgent,
        requiresAcknowledgement: task.requiresAcknowledgement,
        snoozedUntil: task.snoozedUntil?.toUtc(),
      );

  AlarmInput _toAlarm(Reminder reminder, TaskRecord task) => AlarmInput(
    reminderId: reminder.id,
    taskId: task.id,
    taskTitle: task.title,
    kind: reminder.kind,
    snoozeRound: reminder.snoozeCount,
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
    final synthetic = parseSyntheticReminderId(reminderId);
    if (synthetic != null) {
      // Resolve to the row of the SAME kind (OPH-175): acknowledging the nudge
      // must not silence the deadline alarm sitting next to it.
      final active =
          await (_db.select(_db.reminders)
                ..where(
                  (r) =>
                      r.taskId.equals(synthetic.taskId) &
                      r.kind.equals(synthetic.kind) &
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
