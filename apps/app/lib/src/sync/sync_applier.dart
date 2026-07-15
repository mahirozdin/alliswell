import 'dart:convert';

import 'package:drift/drift.dart';

import 'db/database.dart';
import 'sync_api.dart';

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();

Value<DateTime?> _dateValue(Object? value) => Value(_date(value));

/// Applies one pull batch to the local replica in a single transaction and
/// advances the workspace's sync cursor (OPH-054/OPH-051 client side).
///
/// Snapshots are CURRENT server rows — upserts by primary key; tombstones
/// remove the row plus its purely-local join data (task tags, note links,
/// checklist rows of a deleted task). Unknown entity types are skipped so an
/// older app survives a newer server.
Future<void> applyPulledChanges(
  AwDatabase db, {
  required String workspaceId,
  required List<SyncChange> changes,
  required int toRevision,
}) async {
  await db.transaction(() async {
    for (final change in changes) {
      if (change.isTombstone) {
        await _applyTombstone(db, change);
      } else {
        await _applySnapshot(db, change.entityType, change.data!);
      }
    }
    await (db.update(
      db.syncStates,
    )..where((s) => s.workspaceId.equals(workspaceId))).write(
      SyncStatesCompanion(
        lastRevision: Value(toRevision),
        lastPulledAt: Value(DateTime.now().toUtc()),
      ),
    );
  });
}

Future<void> _applyTombstone(AwDatabase db, SyncChange change) async {
  final id = change.entityId;
  switch (change.entityType) {
    case 'project':
      await (db.delete(db.projects)..where((p) => p.id.equals(id))).go();
    case 'tag':
      await (db.delete(db.tags)..where((t) => t.id.equals(id))).go();
      await (db.delete(db.taskTagRows)..where((r) => r.tagId.equals(id))).go();
    case 'task':
      await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
      await (db.delete(db.taskTagRows)..where((r) => r.taskId.equals(id))).go();
      await (db.delete(
        db.checklistItems,
      )..where((c) => c.taskId.equals(id))).go();
    case 'note':
      await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
      await (db.delete(
        db.noteLinkRows,
      )..where((l) => l.noteId.equals(id))).go();
    case 'checklist_item':
      await (db.delete(db.checklistItems)..where((c) => c.id.equals(id))).go();
    case 'reminder':
      await (db.delete(db.reminders)..where((r) => r.id.equals(id))).go();
    case 'external_event':
      await (db.delete(db.externalEvents)..where((e) => e.id.equals(id))).go();
  }
}

Future<void> _applySnapshot(
  AwDatabase db,
  String entityType,
  Map<String, dynamic> data,
) async {
  switch (entityType) {
    case 'project':
      await db.into(db.projects).insertOnConflictUpdate(projectCompanion(data));
    case 'tag':
      await db.into(db.tags).insertOnConflictUpdate(tagCompanion(data));
    case 'task':
      await db.into(db.tasks).insertOnConflictUpdate(taskCompanion(data));
      await replaceTaskTags(
        db,
        data['id'] as String,
        ((data['tagIds'] as List?) ?? const []).cast<String>(),
      );
    case 'note':
      await db.into(db.notes).insertOnConflictUpdate(noteCompanion(data));
      await _replaceNoteLinks(
        db,
        data['id'] as String,
        ((data['links'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      );
    case 'checklist_item':
      await db
          .into(db.checklistItems)
          .insertOnConflictUpdate(checklistItemCompanion(data));
    case 'reminder':
      await db
          .into(db.reminders)
          .insertOnConflictUpdate(reminderCompanion(data));
    case 'external_event':
      await db
          .into(db.externalEvents)
          .insertOnConflictUpdate(externalEventCompanion(data));
  }
}

/// Replace-set of a task's tag joins — shared by the applier and optimistic
/// local writes.
Future<void> replaceTaskTags(
  AwDatabase db,
  String taskId,
  List<String> tagIds,
) async {
  await (db.delete(db.taskTagRows)..where((r) => r.taskId.equals(taskId))).go();
  for (final tagId in tagIds.toSet()) {
    await db
        .into(db.taskTagRows)
        .insert(TaskTagRowsCompanion.insert(taskId: taskId, tagId: tagId));
  }
}

Future<void> _replaceNoteLinks(
  AwDatabase db,
  String noteId,
  List<Map<String, dynamic>> links,
) async {
  await (db.delete(
    db.noteLinkRows,
  )..where((l) => l.noteId.equals(noteId))).go();
  for (final link in links) {
    await db
        .into(db.noteLinkRows)
        .insert(
          NoteLinkRowsCompanion.insert(
            id: link['id'] as String,
            noteId: noteId,
            entityType: link['entityType'] as String,
            entityId: link['entityId'] as String,
          ),
        );
  }
}

// ── Snapshot JSON (REST serializer shape) → drift companions ────────────────

ProjectsCompanion projectCompanion(Map<String, dynamic> d) =>
    ProjectsCompanion.insert(
      id: d['id'] as String,
      workspaceId: d['workspaceId'] as String,
      name: d['name'] as String,
      description: Value(d['description'] as String?),
      colorRgb: Value((d['colorRgb'] as String?) ?? '#2563EB'),
      icon: Value(d['icon'] as String?),
      status: Value((d['status'] as String?) ?? 'active'),
      startAt: _dateValue(d['startAt']),
      dueAt: _dateValue(d['dueAt']),
      sortOrder: Value((d['sortOrder'] as int?) ?? 0),
      isFavorite: Value((d['isFavorite'] as bool?) ?? false),
      readmeNoteId: Value(d['readmeNoteId'] as String?),
      revision: Value((d['revision'] as int?) ?? 0),
      createdAt: _dateValue(d['createdAt']),
      updatedAt: _dateValue(d['updatedAt']),
    );

TagsCompanion tagCompanion(Map<String, dynamic> d) => TagsCompanion.insert(
  id: d['id'] as String,
  workspaceId: d['workspaceId'] as String,
  name: d['name'] as String,
  slug: d['slug'] as String,
  colorRgb: Value((d['colorRgb'] as String?) ?? '#64748B'),
  icon: Value(d['icon'] as String?),
  revision: Value((d['revision'] as int?) ?? 0),
  createdAt: _dateValue(d['createdAt']),
  updatedAt: _dateValue(d['updatedAt']),
);

/// OPH-083 — the user's own calendar events (ADR-0008). Read-only: no outbox
/// path exists for this table, so the server is the only writer.
ExternalEventsCompanion externalEventCompanion(Map<String, dynamic> d) =>
    ExternalEventsCompanion.insert(
      id: d['id'] as String,
      workspaceId: d['workspaceId'] as String,
      summary: Value(d['summary'] as String?),
      location: Value(d['location'] as String?),
      startsAt: _date(d['startsAt'])!,
      endsAt: _date(d['endsAt'])!,
      isAllDay: Value((d['isAllDay'] as bool?) ?? false),
      isBusy: Value((d['isBusy'] as bool?) ?? true),
      htmlLink: Value(d['htmlLink'] as String?),
      revision: Value((d['revision'] as int?) ?? 0),
    );

TasksCompanion taskCompanion(Map<String, dynamic> d) => TasksCompanion.insert(
  id: d['id'] as String,
  workspaceId: d['workspaceId'] as String,
  projectId: Value(d['projectId'] as String?),
  parentTaskId: Value(d['parentTaskId'] as String?),
  title: d['title'] as String,
  description: Value(d['description'] as String?),
  status: Value((d['status'] as String?) ?? 'open'),
  priority: Value((d['priority'] as String?) ?? 'none'),
  colorRgb: Value(d['colorRgb'] as String?),
  startAt: _dateValue(d['startAt']),
  dueAt: _dateValue(d['dueAt']),
  scheduledStartAt: _dateValue(d['scheduledStartAt']),
  scheduledEndAt: _dateValue(d['scheduledEndAt']),
  remindAt: _dateValue(d['remindAt']),
  snoozedUntil: _dateValue(d['snoozedUntil']),
  timezone: Value((d['timezone'] as String?) ?? 'Europe/Istanbul'),
  isUrgent: Value((d['isUrgent'] as bool?) ?? false),
  requiresAcknowledgement: Value(
    (d['requiresAcknowledgement'] as bool?) ?? false,
  ),
  calendarMirrorEnabled: Value((d['calendarMirrorEnabled'] as bool?) ?? false),
  repeatRule: Value(d['repeatRule'] as String?),
  estimatedMinutes: Value(d['estimatedMinutes'] as int?),
  actualMinutes: Value(d['actualMinutes'] as int?),
  sortOrder: Value((d['sortOrder'] as int?) ?? 0),
  completedAt: _dateValue(d['completedAt']),
  revision: Value((d['revision'] as int?) ?? 0),
  createdAt: _dateValue(d['createdAt']),
  updatedAt: _dateValue(d['updatedAt']),
);

NotesCompanion noteCompanion(Map<String, dynamic> d) => NotesCompanion.insert(
  id: d['id'] as String,
  workspaceId: d['workspaceId'] as String,
  projectId: Value(d['projectId'] as String?),
  createdFromTaskId: Value(d['createdFromTaskId'] as String?),
  title: d['title'] as String,
  contentDelta: Value(
    d['contentDelta'] == null ? null : jsonEncode(d['contentDelta']),
  ),
  contentMarkdown: Value(d['contentMarkdown'] as String?),
  plainText: Value((d['plainText'] as String?) ?? (d['snippet'] as String?)),
  isPinned: Value((d['isPinned'] as bool?) ?? false),
  isArchived: Value((d['isArchived'] as bool?) ?? false),
  revision: Value((d['revision'] as int?) ?? 0),
  createdAt: _dateValue(d['createdAt']),
  updatedAt: _dateValue(d['updatedAt']),
);

ChecklistItemsCompanion checklistItemCompanion(Map<String, dynamic> d) =>
    ChecklistItemsCompanion.insert(
      id: d['id'] as String,
      taskId: d['taskId'] as String,
      title: d['title'] as String,
      isDone: Value((d['isDone'] as bool?) ?? false),
      sortOrder: Value((d['sortOrder'] as int?) ?? 0),
      revision: Value((d['revision'] as int?) ?? 0),
      createdAt: _dateValue(d['createdAt']),
      updatedAt: _dateValue(d['updatedAt']),
    );

RemindersCompanion reminderCompanion(Map<String, dynamic> d) =>
    RemindersCompanion.insert(
      id: d['id'] as String,
      taskId: d['taskId'] as String,
      remindAt: _date(d['remindAt'])!,
      timezone: Value((d['timezone'] as String?) ?? 'Europe/Istanbul'),
      alarmLevel: Value((d['alarmLevel'] as String?) ?? 'normal'),
      requiresAcknowledgement: Value(
        (d['requiresAcknowledgement'] as bool?) ?? false,
      ),
      repeatRule: Value(d['repeatRule'] as String?),
      status: Value((d['status'] as String?) ?? 'scheduled'),
      snoozedUntil: _dateValue(d['snoozedUntil']),
      deliveredAt: _dateValue(d['deliveredAt']),
      acknowledgedAt: _dateValue(d['acknowledgedAt']),
      revision: Value((d['revision'] as int?) ?? 0),
      createdAt: _dateValue(d['createdAt']),
      updatedAt: _dateValue(d['updatedAt']),
    );
