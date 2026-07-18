import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/data/file_attachment.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

// OPH-153 — the pull-only `file` entity in the replica (ADR-0011): applier
// round-trip, tombstones, and the FileStore queries the three UI surfaces
// read (per-target list + the project Files aggregate with sources).

const ws = 'W1000000000000000000000000';
const projectId = 'P1000000000000000000000000';
const taskId = 'T1000000000000000000000000';
const noteId = 'N1000000000000000000000000';

SyncChange fileChange(
  String id,
  String op, {
  String targetType = 'project',
  String targetId = projectId,
  String name = 'rapor.pdf',
  String mime = 'application/pdf',
  int size = 1024,
  int revision = 1,
  String createdAt = '2026-07-18T10:00:00.000Z',
}) => SyncChange(
  entityType: 'file',
  entityId: id,
  operation: op,
  revision: revision,
  data: op == 'delete'
      ? null
      : {
          'id': id,
          'workspaceId': ws,
          'targetType': targetType,
          'targetId': targetId,
          'name': name,
          'mime': mime,
          'sizeBytes': size,
          'status': 'ready',
          'uploadedBy': 'U1000000000000000000000000',
          'revision': revision,
          'createdAt': createdAt,
          'updatedAt': createdAt,
        },
);

Future<void> seedProjectGraph(AwDatabase db) async {
  await applyPulledChanges(
    db,
    workspaceId: ws,
    toRevision: 3,
    changes: [
      SyncChange(
        entityType: 'project',
        entityId: projectId,
        operation: 'create',
        revision: 1,
        data: {
          'id': projectId,
          'workspaceId': ws,
          'name': 'Dosyalı proje',
          'colorRgb': '#2563EB',
          'status': 'active',
          'sortOrder': 0,
          'isFavorite': false,
          'revision': 1,
        },
      ),
      SyncChange(
        entityType: 'task',
        entityId: taskId,
        operation: 'create',
        revision: 2,
        data: {
          'id': taskId,
          'workspaceId': ws,
          'projectId': projectId,
          'title': 'Ekli görev',
          'status': 'open',
          'priority': 'none',
          'timezone': 'Europe/Istanbul',
          'isUrgent': false,
          'requiresAcknowledgement': false,
          'sortOrder': 0,
          'revision': 2,
          'tagIds': const <String>[],
        },
      ),
      SyncChange(
        entityType: 'note',
        entityId: noteId,
        operation: 'create',
        revision: 3,
        data: {
          'id': noteId,
          'workspaceId': ws,
          'projectId': projectId,
          'title': 'Ekli not',
          'isPinned': false,
          'isArchived': false,
          'revision': 3,
          'links': const <Map<String, dynamic>>[],
        },
      ),
    ],
  );
}

void main() {
  late AwDatabase db;
  late FileStore store;

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    store = FileStore(db);
  });

  tearDown(() => db.close());

  test(
    'a pulled file round-trips into the replica; a tombstone removes it',
    () async {
      const id = 'F1000000000000000000000000';
      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 1,
        changes: [fileChange(id, 'create', name: 'Özet raporu.pdf')],
      );

      final rows = await db.select(db.fileRows).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Özet raporu.pdf');
      expect(rows.single.mime, 'application/pdf');
      expect(rows.single.sizeBytes, 1024);
      expect(rows.single.status, 'ready');
      expect(rows.single.createdAt, isNotNull);

      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 2,
        changes: [fileChange(id, 'delete', revision: 2)],
      );
      expect(await db.select(db.fileRows).get(), isEmpty);
    },
  );

  test(
    'an updated snapshot upserts over the existing row (rename lands)',
    () async {
      const id = 'F1000000000000000000000000';
      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 1,
        changes: [fileChange(id, 'create')],
      );
      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 2,
        changes: [fileChange(id, 'update', name: 'yeni-ad.pdf', revision: 2)],
      );
      final row = await db.select(db.fileRows).getSingle();
      expect(row.name, 'yeni-ad.pdf');
      expect(row.revision, 2);
    },
  );

  test('watchForTarget lists one entity newest-first', () async {
    await seedProjectGraph(db);
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 6,
      changes: [
        fileChange(
          'F1000000000000000000000000',
          'create',
          targetType: 'task',
          targetId: taskId,
          name: 'eski.png',
          mime: 'image/png',
          createdAt: '2026-07-17T10:00:00.000Z',
          revision: 4,
        ),
        fileChange(
          'F2000000000000000000000000',
          'create',
          targetType: 'task',
          targetId: taskId,
          name: 'yeni.png',
          mime: 'image/png',
          createdAt: '2026-07-18T10:00:00.000Z',
          revision: 5,
        ),
        // A different target must not leak into the task's list.
        fileChange('F3000000000000000000000000', 'create', revision: 6),
      ],
    );

    final files = await store
        .watchForTarget(targetType: 'task', targetId: taskId)
        .first;
    expect(files.map((f) => f.name).toList(), ['yeni.png', 'eski.png']);
    expect(files.first.isImage, isTrue);
  });

  test(
    'watchForProject aggregates project ∪ task ∪ note files with sources',
    () async {
      await seedProjectGraph(db);
      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 8,
        changes: [
          fileChange(
            'F1000000000000000000000000',
            'create',
            name: 'proje.bin',
            createdAt: '2026-07-18T12:00:00.000Z',
            revision: 4,
          ),
          fileChange(
            'F2000000000000000000000000',
            'create',
            targetType: 'task',
            targetId: taskId,
            name: 'görev.bin',
            createdAt: '2026-07-18T11:00:00.000Z',
            revision: 5,
          ),
          fileChange(
            'F3000000000000000000000000',
            'create',
            targetType: 'note',
            targetId: noteId,
            name: 'not.bin',
            createdAt: '2026-07-18T10:00:00.000Z',
            revision: 6,
          ),
          // A task OUTSIDE the project: its file must not appear.
          SyncChange(
            entityType: 'task',
            entityId: 'T2000000000000000000000000',
            operation: 'create',
            revision: 7,
            data: {
              'id': 'T2000000000000000000000000',
              'workspaceId': ws,
              'title': 'Başka görev',
              'status': 'open',
              'priority': 'none',
              'timezone': 'Europe/Istanbul',
              'isUrgent': false,
              'requiresAcknowledgement': false,
              'sortOrder': 0,
              'revision': 7,
              'tagIds': const <String>[],
            },
          ),
          fileChange(
            'F4000000000000000000000000',
            'create',
            targetType: 'task',
            targetId: 'T2000000000000000000000000',
            name: 'dışarıda.bin',
            revision: 8,
          ),
        ],
      );

      final entries = await store.watchForProject(projectId).first;
      expect(entries.map((e) => e.file.name).toList(), [
        'proje.bin',
        'görev.bin',
        'not.bin',
      ]);
      expect(entries[0].sourceType, 'project');
      expect(entries[0].sourceTitle, 'Dosyalı proje');
      expect(entries[1].sourceType, 'task');
      expect(entries[1].sourceTitle, 'Ekli görev');
      expect(entries[2].sourceType, 'note');
      expect(entries[2].sourceTitle, 'Ekli not');
    },
  );

  test('the aggregate stream is live: a new file event updates it', () async {
    await seedProjectGraph(db);
    final stream = store.watchForProject(projectId);
    expect(await stream.first, isEmpty);

    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 4,
      changes: [
        fileChange('F1000000000000000000000000', 'create', revision: 4),
      ],
    );
    final entries = await stream.first;
    expect(entries, hasLength(1));
    expect(entries.single.file.name, 'rapor.pdf');
  });
}
