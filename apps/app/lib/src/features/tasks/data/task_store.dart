import 'package:drift/drift.dart';

import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';
import '../../../sync/streams.dart';
import '../../../sync/sync_applier.dart';
import 'task.dart';

/// Statuses that appear on planning lists (Home, project Tasks). Inbox captures
/// (`inbox`) are excluded — they live only in the Inbox until triaged (OPH-107);
/// terminal statuses (completed/cancelled/archived) never appear here either.
const kPlanningStatuses = ['open', 'scheduled', 'in_progress', 'waiting'];

/// Local-first task access (OPH-054): reads are drift watch queries over the
/// replica; writes change the replica optimistically AND enqueue the same
/// patch in the outbox (OPH-055) inside one transaction, then poke the sync
/// engine. The server stays canonical — pulled snapshots overwrite rows.
class TaskStore {
  TaskStore(this._db, this._poke);

  final AwDatabase _db;
  final void Function() _poke;

  // ── Reads ──────────────────────────────────────────────────────────────────

  Stream<List<Task>> watchOpen(String workspaceId) => _watchList(
    workspaceId,
    (t) => t.workspaceId.equals(workspaceId) & t.status.isIn(kPlanningStatuses),
  );

  Stream<List<Task>> watchInbox(String workspaceId) => _watchList(
    workspaceId,
    (t) => t.workspaceId.equals(workspaceId) & t.status.equals('inbox'),
  );

  Stream<List<Task>> watchProjectTasks(String workspaceId, String projectId) =>
      _watchList(
        workspaceId,
        (t) =>
            t.workspaceId.equals(workspaceId) &
            t.status.isIn(kPlanningStatuses) &
            t.projectId.equals(projectId),
      );

  Stream<List<Task>> _watchList(
    String workspaceId,
    Expression<bool> Function($TasksTable) filter,
  ) =>
      (_db.select(_db.tasks)
            ..where(filter)
            // ULIDs sort by creation time — newest first, like the server list.
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .watch()
          .map((rows) => rows.map(_task).toList());

  /// Detail = task row + tag joins + checklist, live on every part.
  Stream<Task> watchDetail(String taskId) => combineLatest3(
    (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(taskId))).watchSingleOrNull(),
    (_db.select(
      _db.taskTagRows,
    )..where((r) => r.taskId.equals(taskId))).watch(),
    (_db.select(_db.checklistItems)
          ..where((c) => c.taskId.equals(taskId))
          ..orderBy([
            (c) => OrderingTerm.asc(c.sortOrder),
            (c) => OrderingTerm.asc(c.createdAt),
          ]))
        .watch(),
    (record, tagRows, checklist) => record == null
        ? null
        : _task(
            record,
            tagIds: [for (final r in tagRows) r.tagId]..sort(),
            checklist: [
              for (final c in checklist)
                ChecklistItem(
                  id: c.id,
                  title: c.title,
                  isDone: c.isDone,
                  sortOrder: c.sortOrder,
                ),
            ],
          ),
  ).where((task) => task != null).map((task) => task!);

  // ── Writes (optimistic + outbox) ───────────────────────────────────────────

  Future<String> create(String workspaceId, Map<String, dynamic> body) async {
    final id = newUlid();
    final patch = {...body};
    // Urgent alarms demand acknowledgement unless opted out (server parity).
    if (patch['isUrgent'] == true &&
        !patch.containsKey('requiresAcknowledgement')) {
      patch['requiresAcknowledgement'] = true;
    }
    // A capture created WITH a date or project isn't a capture — promote it so
    // it lands on planning lists, not the Inbox (OPH-107 parity with update).
    if (patch['status'] == 'inbox' &&
        (patch['dueAt'] != null || patch['projectId'] != null)) {
      patch['status'] = 'open';
    }
    final tagIds = ((patch['tagIds'] as List?) ?? const []).cast<String>();

    await _db.transaction(() async {
      await _db
          .into(_db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              title: (patch['title'] as String).trim(),
              projectId: Value(patch['projectId'] as String?),
              parentTaskId: Value(patch['parentTaskId'] as String?),
              status: Value((patch['status'] as String?) ?? 'open'),
              priority: Value((patch['priority'] as String?) ?? 'none'),
              description: Value(patch['description'] as String?),
              dueAt: _dateValue(patch, 'dueAt'),
              remindAt: _dateValue(patch, 'remindAt'),
              startAt: _dateValue(patch, 'startAt'),
              isUrgent: Value((patch['isUrgent'] as bool?) ?? false),
              requiresAcknowledgement: Value(
                (patch['requiresAcknowledgement'] as bool?) ?? false,
              ),
              calendarMirrorEnabled: Value(
                (patch['calendarMirrorEnabled'] as bool?) ?? false,
              ),
              sortOrder: Value((patch['sortOrder'] as int?) ?? 0),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      if (tagIds.isNotEmpty) await replaceTaskTags(_db, id, tagIds);
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'task',
        entityId: id,
        operation: 'create',
        patch: patch,
      );
    });
    _poke();
    return id;
  }

  Future<void> update(String taskId, Map<String, dynamic> patch) async {
    final record = await _record(taskId);
    if (record == null) return;
    final effective = {...patch};
    if (effective['isUrgent'] == true &&
        !effective.containsKey('requiresAcknowledgement')) {
      effective['requiresAcknowledgement'] = true;
    }
    // Auto-promote a capture: giving an inbox item a date or a project means it
    // has been triaged, so it graduates to 'open' in the SAME write + outbox
    // mutation (OPH-107) — unless the caller set status explicitly.
    if (record.status == 'inbox' && !effective.containsKey('status')) {
      final gainsDate =
          effective.containsKey('dueAt') && effective['dueAt'] != null;
      final gainsProject =
          effective.containsKey('projectId') && effective['projectId'] != null;
      if (gainsDate || gainsProject) effective['status'] = 'open';
    }

    var companion = const TasksCompanion();
    if (effective.containsKey('title')) {
      companion = companion.copyWith(
        title: Value((effective['title'] as String).trim()),
      );
    }
    if (effective.containsKey('description')) {
      companion = companion.copyWith(
        description: Value(effective['description'] as String?),
      );
    }
    if (effective.containsKey('projectId')) {
      companion = companion.copyWith(
        projectId: Value(effective['projectId'] as String?),
      );
    }
    if (effective.containsKey('priority')) {
      companion = companion.copyWith(
        priority: Value(effective['priority'] as String),
      );
    }
    if (effective.containsKey('isUrgent')) {
      companion = companion.copyWith(
        isUrgent: Value(effective['isUrgent'] as bool),
      );
    }
    if (effective.containsKey('requiresAcknowledgement')) {
      companion = companion.copyWith(
        requiresAcknowledgement: Value(
          effective['requiresAcknowledgement'] as bool,
        ),
      );
    }
    if (effective.containsKey('calendarMirrorEnabled')) {
      companion = companion.copyWith(
        calendarMirrorEnabled: Value(
          effective['calendarMirrorEnabled'] as bool,
        ),
      );
    }
    if (effective.containsKey('dueAt')) {
      companion = companion.copyWith(dueAt: _dateValue(effective, 'dueAt'));
    }
    if (effective.containsKey('remindAt')) {
      companion = companion.copyWith(
        remindAt: _dateValue(effective, 'remindAt'),
      );
    }
    if (effective.containsKey('startAt')) {
      companion = companion.copyWith(startAt: _dateValue(effective, 'startAt'));
    }
    if (effective.containsKey('scheduledStartAt')) {
      companion = companion.copyWith(
        scheduledStartAt: _dateValue(effective, 'scheduledStartAt'),
      );
    }
    if (effective.containsKey('scheduledEndAt')) {
      companion = companion.copyWith(
        scheduledEndAt: _dateValue(effective, 'scheduledEndAt'),
      );
    }
    if (effective.containsKey('sortOrder')) {
      companion = companion.copyWith(
        sortOrder: Value(effective['sortOrder'] as int),
      );
    }
    if (effective.containsKey('status')) {
      final status = effective['status'] as String;
      companion = companion.copyWith(status: Value(status));
      // completed_at bookkeeping mirrors the server (OPH-033).
      if (status == 'completed' && record.status != 'completed') {
        companion = companion.copyWith(
          completedAt: Value(DateTime.now().toUtc()),
        );
      } else if (status != 'completed' && record.status == 'completed') {
        companion = companion.copyWith(completedAt: const Value(null));
      }
    }
    companion = companion.copyWith(updatedAt: Value(DateTime.now().toUtc()));

    await _db.transaction(() async {
      await (_db.update(
        _db.tasks,
      )..where((t) => t.id.equals(taskId))).write(companion);
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'task',
        entityId: taskId,
        operation: 'update',
        patch: effective,
      );
    });
    _poke();
  }

  Future<void> complete(String taskId) =>
      update(taskId, {'status': 'completed'});

  Future<void> reopen(String taskId) => update(taskId, {'status': 'open'});

  /// Snooze presets shared with the server (BLUEPRINT §4.9). Offsets are
  /// from "now"; tomorrow_morning is 09:00 on the device's wall clock — the
  /// server's task-timezone version applies when snoozing over REST.
  static DateTime snoozeUntilFor(String preset, {DateTime? now}) {
    final base = now ?? DateTime.now();
    switch (preset) {
      case '5_min':
        return base.add(const Duration(minutes: 5));
      case '30_min':
        return base.add(const Duration(minutes: 30));
      case '1_hour':
        return base.add(const Duration(hours: 1));
      case 'tomorrow_morning':
        final local = base.toLocal();
        return DateTime(local.year, local.month, local.day + 1, 9);
      default:
        throw ArgumentError.value(preset, 'preset');
    }
  }

  /// Offline-first snooze (OPH-062): the task AND its active alarm move
  /// locally in one transaction; the outbox patch replays the same semantics
  /// server-side (sync push snoozedUntil → reminder snooze, same trx).
  Future<void> snooze(String taskId, {String? preset, DateTime? until}) async {
    final record = await _record(taskId);
    if (record == null) return;
    if (record.status == 'completed' || record.status == 'cancelled') return;
    final snoozeUntil = (until ?? snoozeUntilFor(preset!)).toUtc();

    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(
          snoozedUntil: Value(snoozeUntil),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await (_db.update(_db.reminders)..where(
            (r) =>
                r.taskId.equals(taskId) &
                r.status.isIn(const ['scheduled', 'snoozed', 'delivered']),
          ))
          .write(
            RemindersCompanion(
              status: const Value('snoozed'),
              snoozedUntil: Value(snoozeUntil),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'task',
        entityId: taskId,
        operation: 'update',
        patch: {'snoozedUntil': snoozeUntil.toIso8601String()},
      );
    });
    _poke();
  }

  /// Replace-set tags, like `PUT /tasks/:id/tags` (synced as an update patch).
  Future<void> setTags(String taskId, List<String> tagIds) async {
    final record = await _record(taskId);
    if (record == null) return;
    await _db.transaction(() async {
      await replaceTaskTags(_db, taskId, tagIds);
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'task',
        entityId: taskId,
        operation: 'update',
        patch: {'tagIds': tagIds},
      );
    });
    _poke();
  }

  Future<void> delete(String taskId) async {
    final record = await _record(taskId);
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.delete(_db.tasks)..where((t) => t.id.equals(taskId))).go();
      await (_db.delete(
        _db.taskTagRows,
      )..where((r) => r.taskId.equals(taskId))).go();
      await (_db.delete(
        _db.checklistItems,
      )..where((c) => c.taskId.equals(taskId))).go();
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'task',
        entityId: taskId,
        operation: 'delete',
      );
    });
    _poke();
  }

  // ── Checklist (each item is its own sync entity) ───────────────────────────

  Future<void> addChecklistItem(String taskId, String title) async {
    final record = await _record(taskId);
    if (record == null) return;
    final existing = await (_db.select(
      _db.checklistItems,
    )..where((c) => c.taskId.equals(taskId))).get();
    final id = newUlid();
    final sortOrder = existing.length;
    await _db.transaction(() async {
      await _db
          .into(_db.checklistItems)
          .insert(
            ChecklistItemsCompanion.insert(
              id: id,
              taskId: taskId,
              title: title,
              sortOrder: Value(sortOrder),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'checklist_item',
        entityId: id,
        operation: 'create',
        patch: {'taskId': taskId, 'title': title, 'sortOrder': sortOrder},
      );
    });
    _poke();
  }

  Future<void> setChecklistItemDone(
    String taskId,
    String itemId, {
    required bool isDone,
  }) async {
    final record = await _record(taskId);
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.update(
        _db.checklistItems,
      )..where((c) => c.id.equals(itemId))).write(
        ChecklistItemsCompanion(
          isDone: Value(isDone),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'checklist_item',
        entityId: itemId,
        operation: 'update',
        patch: {'isDone': isDone},
      );
    });
    _poke();
  }

  Future<void> deleteChecklistItem(String taskId, String itemId) async {
    final record = await _record(taskId);
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.checklistItems,
      )..where((c) => c.id.equals(itemId))).go();
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'checklist_item',
        entityId: itemId,
        operation: 'delete',
      );
    });
    _poke();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<TaskRecord?> _record(String taskId) => (_db.select(
    _db.tasks,
  )..where((t) => t.id.equals(taskId))).getSingleOrNull();

  Value<DateTime?> _dateValue(Map<String, dynamic> patch, String key) {
    final raw = patch[key];
    return Value(raw == null ? null : DateTime.parse(raw as String).toUtc());
  }

  Task _task(
    TaskRecord r, {
    List<String> tagIds = const [],
    List<ChecklistItem> checklist = const [],
  }) => Task(
    id: r.id,
    workspaceId: r.workspaceId,
    projectId: r.projectId,
    parentTaskId: r.parentTaskId,
    title: r.title,
    description: r.description,
    status: r.status,
    priority: r.priority,
    colorRgb: r.colorRgb,
    startAt: r.startAt,
    dueAt: r.dueAt,
    scheduledStartAt: r.scheduledStartAt,
    scheduledEndAt: r.scheduledEndAt,
    remindAt: r.remindAt,
    snoozedUntil: r.snoozedUntil,
    completedAt: r.completedAt,
    timezone: r.timezone,
    isUrgent: r.isUrgent,
    requiresAcknowledgement: r.requiresAcknowledgement,
    calendarMirrorEnabled: r.calendarMirrorEnabled,
    sortOrder: r.sortOrder,
    revision: r.revision,
    tagIds: tagIds,
    checklist: checklist,
  );
}
