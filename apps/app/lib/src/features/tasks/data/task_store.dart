import 'package:drift/drift.dart';

import '../../../core/fold.dart';
import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';
import '../../../sync/streams.dart';
import '../../../sync/sync_applier.dart';
import '../../quick_access/data/quick_access_store.dart';
import '../../quick_access/data/quick_link.dart';
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

  /// The planning set — plus, since OPH-185, whatever was completed on or
  /// after [completedSince] (the current local day's start).
  ///
  /// DESIGN §20 C1: completing is feedback, not disappearance. Passing null
  /// keeps the old behaviour (terminal statuses hidden outright), which is what
  /// callers that are not a day-scoped planning list want.
  Stream<List<Task>> watchOpen(
    String workspaceId, {
    DateTime? completedSince,
  }) => _watchList(
    workspaceId,
    (t) =>
        t.workspaceId.equals(workspaceId) &
        (t.status.isIn(kPlanningStatuses) | _completedSince(t, completedSince)),
  );

  /// Every status — the Board's source (OPH-168): its columns include
  /// terminal statuses the planning lists deliberately hide.
  Stream<List<Task>> watchAll(String workspaceId) =>
      _watchList(workspaceId, (t) => t.workspaceId.equals(workspaceId));

  Stream<List<Task>> watchInbox(String workspaceId) => _watchList(
    workspaceId,
    (t) => t.workspaceId.equals(workspaceId) & t.status.equals('inbox'),
  );

  Stream<List<Task>> watchProjectTasks(
    String workspaceId,
    String projectId, {
    DateTime? completedSince,
  }) => _watchList(
    workspaceId,
    (t) =>
        t.workspaceId.equals(workspaceId) &
        t.projectId.equals(projectId) &
        (t.status.isIn(kPlanningStatuses) | _completedSince(t, completedSince)),
  );

  /// "Completed on or after this instant" — or nothing at all when the caller
  /// passed no boundary. A constant false keeps the two branches of the OR
  /// symmetrical instead of forcing every caller to build two queries.
  Expression<bool> _completedSince($TasksTable t, DateTime? since) =>
      since == null
      ? const Constant(false)
      : t.status.equals('completed') &
            t.completedAt.isBiggerOrEqualValue(since.toUtc());

  /// The Completed archive (OPH-186, DESIGN §20 C4), newest first.
  ///
  /// Ordering is the user's own rule: **the task's own date when it has one,
  /// otherwise when they finished it** — `COALESCE(due_at, completed_at)`. Read
  /// from the local replica; the data is already here, and an archive that
  /// needs the network is an archive you cannot trust.
  ///
  /// Deliberately NOT built on [_watchList]: that one joins the tag table, and
  /// a `LIMIT` on a joined statement counts JOINED rows — a task with three
  /// tags would eat three slots of the page and page sizes would depend on how
  /// many tags the user happens to use. So the page is taken over task rows and
  /// the tags for exactly that page are read afterwards. The cost of that
  /// choice, stated rather than hidden: this stream re-emits on task changes,
  /// not on a tag rename — acceptable for an archive, wrong for a live list.
  Stream<List<Task>> watchCompleted(
    String workspaceId, {
    required int limit,
    int offset = 0,
  }) {
    final page = _db.select(_db.tasks)
      ..where(
        (t) => t.workspaceId.equals(workspaceId) & t.status.equals('completed'),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: CustomExpression<DateTime>(
            'COALESCE(due_at, completed_at)',
          ),
          mode: OrderingMode.desc,
        ),
        // A stable tiebreaker: ULIDs sort by creation, so two tasks with
        // the same sort instant keep a deterministic order across pages.
        // Without it a page boundary can repeat or skip a row.
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit, offset: offset);
    return page.watch().asyncMap((records) async {
      if (records.isEmpty) return const <Task>[];
      final ids = [for (final record in records) record.id];
      final tagRows = await (_db.select(
        _db.taskTagRows,
      )..where((r) => r.taskId.isIn(ids))).get();
      final tagsByTask = <String, List<String>>{};
      for (final row in tagRows) {
        tagsByTask.putIfAbsent(row.taskId, () => []).add(row.tagId);
      }
      return [
        for (final record in records)
          _task(record, tagIds: (tagsByTask[record.id]?..sort()) ?? const []),
      ];
    });
  }

  /// One WATCHED JOIN, not two combined streams: lists hydrate tagIds
  /// (OPH-165, DESIGN T4) while keeping the single-stream emission semantics
  /// the sync tests rely on — drift re-emits this stream when EITHER table
  /// changes.
  Stream<List<Task>> _watchList(
    String workspaceId,
    Expression<bool> Function($TasksTable) filter,
  ) {
    final query =
        (_db.select(_db.tasks)
              ..where(filter)
              // ULIDs sort by creation time — newest first, like the server
              // list.
              ..orderBy([(t) => OrderingTerm.desc(t.id)]))
            .join([
              leftOuterJoin(
                _db.taskTagRows,
                _db.taskTagRows.taskId.equalsExp(_db.tasks.id),
              ),
            ]);
    return query.watch().map((rows) {
      // The join multiplies rows per tag; regroup preserving query order.
      final order = <String>[];
      final tasksById = <String, TaskRecord>{};
      final tagsByTask = <String, List<String>>{};
      for (final row in rows) {
        final record = row.readTable(_db.tasks);
        if (!tasksById.containsKey(record.id)) {
          order.add(record.id);
          tasksById[record.id] = record;
        }
        final tagRow = row.readTableOrNull(_db.taskTagRows);
        if (tagRow != null) {
          tagsByTask.putIfAbsent(record.id, () => []).add(tagRow.tagId);
        }
      }
      return [
        for (final id in order)
          _task(tasksById[id]!, tagIds: (tagsByTask[id]?..sort()) ?? const []),
      ];
    });
  }

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
              titleFold: Value(
                foldSearchText((patch['title'] as String).trim()),
              ),
              projectId: Value(patch['projectId'] as String?),
              parentTaskId: Value(patch['parentTaskId'] as String?),
              status: Value((patch['status'] as String?) ?? 'open'),
              priority: Value((patch['priority'] as String?) ?? 'none'),
              description: Value(patch['description'] as String?),
              descriptionFold: Value(
                patch['description'] == null
                    ? null
                    : foldSearchText(patch['description'] as String),
              ),
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
      final title = (effective['title'] as String).trim();
      companion = companion.copyWith(
        title: Value(title),
        titleFold: Value(foldSearchText(title)),
      );
    }
    if (effective.containsKey('description')) {
      final description = effective['description'] as String?;
      companion = companion.copyWith(
        description: Value(description),
        descriptionFold: Value(
          description == null ? null : foldSearchText(description),
        ),
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
    // OPH-178: silence (or give back) this task's alarms. A marker, not a
    // schedule — the engine reads it and cancels every alarm the task owns.
    if (effective.containsKey('alarmsMutedAt')) {
      companion = companion.copyWith(
        alarmsMutedAt: _dateValue(effective, 'alarmsMutedAt'),
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

  /// Silence this task's alarms indefinitely (OPH-178, round 9 #6.7) — WITHOUT
  /// completing it. Marking a task done to make it shut up would be a lie in the
  /// data; this is a reversible, replicated fact the engine reads
  /// (`alarmInstantsFor` → no alarms → the rows are cancelled everywhere).
  Future<void> muteAlarms(String taskId) => update(taskId, {
    'alarmsMutedAt': DateTime.now().toUtc().toIso8601String(),
  });

  /// Give the alarms back. Whether one still fires depends on its instant —
  /// the caller tells the user when it has already passed.
  Future<void> unmuteAlarms(String taskId) =>
      update(taskId, {'alarmsMutedAt': null});

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
      // Every active alarm of the task (a reminder AND a deadline, OPH-175),
      // each carrying its own round count (OPH-177) — read first, because the
      // count is per row.
      final active =
          await (_db.select(_db.reminders)..where(
                (r) =>
                    r.taskId.equals(taskId) &
                    r.status.isIn(const ['scheduled', 'snoozed', 'delivered']),
              ))
              .get();
      for (final alarm in active) {
        await (_db.update(
          _db.reminders,
        )..where((r) => r.id.equals(alarm.id))).write(
          RemindersCompanion(
            status: const Value('snoozed'),
            snoozedUntil: Value(snoozeUntil),
            snoozeCount: Value(alarm.snoozeCount + 1),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
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
      // A shortcut to a task that no longer exists would render as broken
      // until the server's cascade comes back (OPH-197/198).
      await forgetQuickLinksFor(
        _db,
        workspaceId: record.workspaceId,
        kind: QuickKind.task,
        targetIds: [taskId],
      );
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
    alarmsMutedAt: r.alarmsMutedAt,
    completedAt: r.completedAt,
    timezone: r.timezone,
    isUrgent: r.isUrgent,
    requiresAcknowledgement: r.requiresAcknowledgement,
    calendarMirrorEnabled: r.calendarMirrorEnabled,
    seriesId: r.seriesId,
    occurrenceDate: r.occurrenceDate,
    createdAt: r.createdAt,
    sortOrder: r.sortOrder,
    revision: r.revision,
    tagIds: tagIds,
    checklist: checklist,
  );
}
