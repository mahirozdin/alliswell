import 'package:drift/drift.dart';

import '../sync/db/database.dart';
import '../sync/outbox.dart';
import '../sync/streams.dart';
import 'planner.dart';
import '../features/tasks/data/task_scope.dart';
import '../features/tasks/data/task_store.dart' show requireActionReceipt;

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
/// - a task in a terminal state — or one the user silenced (OPH-178) — has none.
List<({String kind, DateTime at})> taskAlarmInstants(TaskRecord task) {
  const silenced = {'completed', 'cancelled', 'archived'};
  if (silenced.contains(task.status)) return const [];
  // OPH-178: silenced indefinitely — the task is still open, it just has no
  // alarms until the user gives them back.
  if (task.alarmsMutedAt != null) return const [];
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

/// The projection both readers share (OPH-321): reminder rows first, then a
/// task-derived stand-in for every alarm kind that has no row yet.
///
/// Pure, and top-level, because the headless refresh and the live app MUST
/// produce the same set — two implementations of "which alarms exist" is how a
/// background turn ends up scheduling something the app would not have, and the
/// identity-parity test can only be honest if there is one function to test.
List<AlarmInput> mergeAlarms(
  List<AlarmInput> fromRows,
  List<TaskRecord> wanting,
  Set<String> ownedKinds,
) => [
  ...fromRows,
  for (final task in wanting)
    for (final instant in taskAlarmInstants(task))
      if (!ownedKinds.contains('${task.id}|${instant.kind}'))
        syntheticAlarmFor(task, instant.kind, instant.at),
];

/// The task-derived stand-in for a reminder row that has not synced yet.
AlarmInput syntheticAlarmFor(TaskRecord task, String kind, DateTime at) =>
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
  Stream<List<AlarmInput>> watchAlarms(String workspaceId) =>
      watchAlarmsIn(TaskScope.workspace(workspaceId));

  /// [watchAlarms] over a [TaskScope]. For a member of an organisation that
  /// is THEIR work only: a colleague's reminder on a task in the same unit is
  /// the colleague's alarm, and an alarm is the loudest thing this app does.
  Stream<List<AlarmInput>> watchAlarmsIn(TaskScope scope) {
    final query = _alarmRowsQuery(scope);

    final fromRows = query.watch().map(
      (rows) => [
        for (final row in rows)
          _toAlarm(row.readTable(_db.reminders), row.readTable(_db.tasks)),
      ],
    );

    // Tasks that want at least one alarm, in a state where one may fire. The
    // per-kind decision is [taskAlarmInstants]'; this only narrows the query.
    final wanting = _wantingTasksQuery(scope).watch();

    // '<taskId>|<kind>' pairs that already own a reminder row in ANY status.
    final covered = _db
        .select(_db.reminders)
        .watch()
        .map((rows) => {for (final r in rows) '${r.taskId}|${r.kind}'});

    return combineLatest3(fromRows, wanting, covered, mergeAlarms);
  }

  /// The same alarm set as [watchAlarms], read ONCE (OPH-321).
  ///
  /// A background turn has no UI, no provider graph and no reason to keep a
  /// stream open: it wakes, asks what should be scheduled, schedules it and
  /// dies. Three `.get()`s where the watcher has three streams, and the same
  /// [mergeAlarms] behind both — because two implementations of "which alarms
  /// exist" is exactly how a headless refresh ends up scheduling something the
  /// app would not have (OPH-299's lesson, one layer down).
  Future<List<AlarmInput>> readAlarms(String workspaceId) =>
      readAlarmsIn(TaskScope.workspace(workspaceId));

  /// [readAlarms] over a [TaskScope] — the background turn's read.
  Future<List<AlarmInput>> readAlarmsIn(TaskScope scope) async {
    final rows = await _alarmRowsQuery(scope).get();
    final tasks = await _wantingTasksQuery(scope).get();
    final covered = await _db.select(_db.reminders).get();
    return mergeAlarms(
      [
        for (final row in rows)
          _toAlarm(row.readTable(_db.reminders), row.readTable(_db.tasks)),
      ],
      tasks,
      {for (final r in covered) '${r.taskId}|${r.kind}'},
    );
  }

  /// Reminder rows that may still fire, joined to their task — reminder rows
  /// carry no workspace id, so the join is what scopes them.
  JoinedSelectStatement<HasResultSet, dynamic> _alarmRowsQuery(
    TaskScope scope,
  ) =>
      (_db.select(_db.reminders)..where(
            (r) => r.status.isIn(const ['scheduled', 'snoozed', 'delivered']),
          ))
          .join([
            innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.reminders.taskId)),
          ])
        ..where(taskScopeFilter(_db, _db.tasks, scope));

  SimpleSelectStatement<$TasksTable, TaskRecord> _wantingTasksQuery(
    TaskScope scope,
  ) => _db.select(_db.tasks)
    ..where(
      (t) =>
          taskScopeFilter(_db, t, scope) &
          t.status.isNotIn(const ['completed', 'cancelled', 'archived']) &
          t.alarmsMutedAt.isNull() &
          (t.remindAt.isNotNull() |
              (t.isUrgent.equals(true) & t.dueAt.isNotNull())),
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
  ///
  /// [receiptId] (OPH-427): the write applies a pulled action whose receipt
  /// the caller inserted in its own transaction; it runs inside that
  /// transaction and refuses to run without the receipt. Null behaves as
  /// before.
  Future<void> acknowledge(String reminderId, {String? receiptId}) async {
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
      await requireActionReceipt(_db, receiptId);
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

  /// A grouped stop (OPH-439, NOTIFICATIONS §2b.3): every member's active
  /// urgent reminder whose effective instant (the snooze target of a snoozed
  /// row, else `remindAt`) falls in the UTC minute [occurrenceMinute]
  /// (`floor(ms / 60000)`) is acknowledged in ONE transaction, the receipt
  /// check first, one outbox mutation per reminder. [taskIds] is
  /// de-duplicated; a reminder of a member in another minute is its own
  /// alarm and stays.
  Future<void> acknowledgeBatch(
    List<String> taskIds, {
    required int occurrenceMinute,
    String? receiptId,
  }) async {
    final ids = taskIds.toSet();
    var wrote = false;
    await _db.transaction(() async {
      await requireActionReceipt(_db, receiptId);
      if (ids.isEmpty) return;
      final rows =
          await ((_db.select(_db.reminders)..where(
                    (r) =>
                        r.taskId.isIn(ids) &
                        r.alarmLevel.equals('urgent') &
                        r.status.isIn(const [
                          'scheduled',
                          'snoozed',
                          'delivered',
                        ]),
                  ))
                  .join([
                    innerJoin(
                      _db.tasks,
                      _db.tasks.id.equalsExp(_db.reminders.taskId),
                    ),
                  ]))
              .get();
      final now = DateTime.now().toUtc();
      for (final row in rows) {
        final reminder = row.readTable(_db.reminders);
        if (!_matches(reminder, occurrenceMinute, now)) continue;
        await (_db.update(
          _db.reminders,
        )..where((r) => r.id.equals(reminder.id))).write(
          RemindersCompanion(
            status: const Value('acknowledged'),
            acknowledgedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await enqueueMutation(
          _db,
          workspaceId: row.readTable(_db.tasks).workspaceId,
          entityType: 'reminder',
          entityId: reminder.id,
          operation: 'update',
          patch: {'status': 'acknowledged'},
        );
        wrote = true;
      }
    });
    if (wrote) _poke();
  }

  /// The active urgent reminders of [taskId] an AlarmKit stop acknowledges
  /// (NOTIFICATIONS §2b.3): those whose effective instant (the snooze target
  /// of a snoozed row, else `remindAt`) falls in the UTC minute of
  /// [occurrenceFireAtMs] — a group rings at its earliest member's second.
  /// Without an occurrence (an entry converted from v1), every one that had
  /// come due by [dueBy].
  Future<List<String>> urgentReminderIdsAt(
    String taskId, {
    int? occurrenceFireAtMs,
    required DateTime dueBy,
  }) async {
    final rows =
        await (_db.select(_db.reminders)..where(
              (r) =>
                  r.taskId.equals(taskId) &
                  r.alarmLevel.equals('urgent') &
                  r.status.isIn(const ['scheduled', 'snoozed', 'delivered']),
            ))
            .get();
    final minute = occurrenceFireAtMs == null
        ? null
        : occurrenceFireAtMs ~/ 60000;
    return [
      for (final r in rows)
        if (_matches(r, minute, dueBy)) r.id,
    ];
  }

  static bool _matches(Reminder r, int? minute, DateTime dueBy) {
    final at = ((r.status == 'snoozed' ? r.snoozedUntil : null) ?? r.remindAt)
        .toUtc();
    if (minute != null) return at.millisecondsSinceEpoch ~/ 60000 == minute;
    return !at.isAfter(dueBy.toUtc());
  }
}
