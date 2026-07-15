import 'package:drift/drift.dart';

import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';
import 'project.dart';

/// Local-first project access (OPH-054): watch queries over the replica,
/// optimistic writes + outbox rows in one transaction.
class ProjectStore {
  ProjectStore(this._db, this._poke);

  final AwDatabase _db;
  final void Function() _poke;

  Stream<List<Project>> watchAll(String workspaceId) =>
      (_db.select(_db.projects)
            ..where((p) => p.workspaceId.equals(workspaceId))
            // Server list order: sort_order, then created_at.
            ..orderBy([
              (p) => OrderingTerm.asc(p.sortOrder),
              (p) => OrderingTerm.asc(p.createdAt),
            ]))
          .watch()
          .map((rows) => rows.map(_project).toList());

  Future<String> create(String workspaceId, Map<String, dynamic> body) async {
    final id = newUlid();
    await _db.transaction(() async {
      await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              name: (body['name'] as String).trim(),
              description: Value(body['description'] as String?),
              colorRgb: Value((body['colorRgb'] as String?) ?? '#2563EB'),
              icon: Value(body['icon'] as String?),
              status: Value((body['status'] as String?) ?? 'active'),
              sortOrder: Value((body['sortOrder'] as int?) ?? 0),
              isFavorite: Value((body['isFavorite'] as bool?) ?? false),
              readmeNoteId: Value(body['readmeNoteId'] as String?),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'project',
        entityId: id,
        operation: 'create',
        patch: body,
      );
    });
    _poke();
    return id;
  }

  Future<void> update(String projectId, Map<String, dynamic> patch) async {
    final record = await (_db.select(
      _db.projects,
    )..where((p) => p.id.equals(projectId))).getSingleOrNull();
    if (record == null) return;

    var companion = ProjectsCompanion(updatedAt: Value(DateTime.now().toUtc()));
    if (patch.containsKey('name')) {
      companion = companion.copyWith(
        name: Value((patch['name'] as String).trim()),
      );
    }
    if (patch.containsKey('description')) {
      companion = companion.copyWith(
        description: Value(patch['description'] as String?),
      );
    }
    if (patch.containsKey('colorRgb')) {
      companion = companion.copyWith(
        colorRgb: Value(patch['colorRgb'] as String),
      );
    }
    if (patch.containsKey('icon')) {
      companion = companion.copyWith(icon: Value(patch['icon'] as String?));
    }
    if (patch.containsKey('status')) {
      companion = companion.copyWith(status: Value(patch['status'] as String));
    }
    if (patch.containsKey('sortOrder')) {
      companion = companion.copyWith(
        sortOrder: Value(patch['sortOrder'] as int),
      );
    }
    if (patch.containsKey('isFavorite')) {
      companion = companion.copyWith(
        isFavorite: Value(patch['isFavorite'] as bool),
      );
    }
    if (patch.containsKey('readmeNoteId')) {
      companion = companion.copyWith(
        readmeNoteId: Value(patch['readmeNoteId'] as String?),
      );
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.projects,
      )..where((p) => p.id.equals(projectId))).write(companion);
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'project',
        entityId: projectId,
        operation: 'update',
        patch: patch,
      );
    });
    _poke();
  }

  /// Optimistic delete: the server enforces the owner/admin rule — a refusal
  /// comes back as a rejected mutation and the next pull restores the row.
  Future<void> delete(String projectId) async {
    final record = await (_db.select(
      _db.projects,
    )..where((p) => p.id.equals(projectId))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.projects,
      )..where((p) => p.id.equals(projectId))).go();
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'project',
        entityId: projectId,
        operation: 'delete',
      );
    });
    _poke();
  }

  Project _project(ProjectRecord r) => Project(
    id: r.id,
    workspaceId: r.workspaceId,
    name: r.name,
    description: r.description,
    colorRgb: r.colorRgb,
    icon: r.icon,
    readmeNoteId: r.readmeNoteId,
    status: r.status,
    startAt: r.startAt,
    dueAt: r.dueAt,
    sortOrder: r.sortOrder,
    isFavorite: r.isFavorite,
    revision: r.revision,
  );
}
