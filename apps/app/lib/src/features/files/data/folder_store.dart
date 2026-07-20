import 'package:drift/drift.dart';

import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';

/// A folder as the Dosyalar tree sees it.
class Folder {
  const Folder({
    required this.id,
    required this.workspaceId,
    required this.parentId,
    required this.name,
  });

  final String id;
  final String workspaceId;
  final String? parentId;
  final String name;
}

/// Local-first folder writes (OPH-170, ADR-0014) — the ProjectStore shape:
/// optimistic drift row + outbox mutation in one transaction, then poke.
/// Folders are pure metadata, so EVERY operation works offline; the server
/// re-runs the same guards on push (cycle/depth/name) and the pull converges.
class FolderStore {
  FolderStore(this._db, {void Function()? onMutation})
    : _poke = onMutation ?? (() {});

  final AwDatabase _db;
  final void Function() _poke;

  /// The whole live tree, name-ordered — screens assemble levels from it.
  Stream<List<Folder>> watchAll(String workspaceId) =>
      (_db.select(_db.folders)
            ..where((f) => f.workspaceId.equals(workspaceId))
            ..orderBy([(f) => OrderingTerm.asc(f.name)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                Folder(
                  id: r.id,
                  workspaceId: r.workspaceId,
                  parentId: r.parentId,
                  name: r.name,
                ),
            ],
          );

  Future<String> create(
    String workspaceId,
    String name, {
    String? parentId,
  }) async {
    final id = newUlid();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.folders)
          .insert(
            FoldersCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              parentId: Value(parentId),
              name: name.trim(),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'folder',
        entityId: id,
        operation: 'create',
        patch: {'name': name.trim(), 'parentId': ?parentId},
      );
    });
    _poke();
    return id;
  }

  Future<void> rename(String folderId, String name) =>
      _update(folderId, {'name': name.trim()});

  /// Move under [parentId] (null = root). The picker UI never offers the
  /// folder's own subtree, and the server refuses cycles regardless.
  Future<void> move(String folderId, String? parentId) =>
      _update(folderId, {'parentId': parentId});

  Future<void> _update(String folderId, Map<String, dynamic> patch) async {
    final record = await (_db.select(
      _db.folders,
    )..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.update(
        _db.folders,
      )..where((f) => f.id.equals(folderId))).write(
        FoldersCompanion(
          name: patch.containsKey('name')
              ? Value(patch['name'] as String)
              : const Value.absent(),
          parentId: patch.containsKey('parentId')
              ? Value(patch['parentId'] as String?)
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'folder',
        entityId: folderId,
        operation: 'update',
        patch: patch,
      );
    });
    _poke();
  }

  /// What dies with this folder — the F9 confirm's blast radius, computed on
  /// the replica (server truth converges on pull).
  Future<({int folders, int files})> subtreeCounts(
    String workspaceId,
    String folderId,
  ) async {
    final ids = await _subtreeIds(workspaceId, folderId);
    final files =
        await (_db.select(_db.fileRows)..where(
              (f) =>
                  f.workspaceId.equals(workspaceId) &
                  f.targetType.equals('workspace') &
                  f.folderId.isIn(ids),
            ))
            .get();
    return (folders: ids.length, files: files.length);
  }

  Future<List<String>> _subtreeIds(String workspaceId, String rootId) async {
    final out = <String>[rootId];
    var frontier = [rootId];
    while (frontier.isNotEmpty) {
      final children =
          await (_db.select(_db.folders)..where(
                (f) =>
                    f.workspaceId.equals(workspaceId) &
                    f.parentId.isIn(frontier),
              ))
              .get();
      frontier = [for (final c in children) c.id];
      out.addAll(frontier);
    }
    return out;
  }

  /// Optimistic recursive delete mirroring the server cascade: local subtree
  /// folders + their workspace file rows go now; ONE outbox delete for the
  /// root — the server cascades the rest and the pull's tombstones agree.
  Future<void> delete(String workspaceId, String folderId) async {
    final ids = await _subtreeIds(workspaceId, folderId);
    await _db.transaction(() async {
      await (_db.delete(_db.fileRows)..where(
            (f) =>
                f.workspaceId.equals(workspaceId) &
                f.targetType.equals('workspace') &
                f.folderId.isIn(ids),
          ))
          .go();
      await (_db.delete(_db.folders)..where((f) => f.id.isIn(ids))).go();
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'folder',
        entityId: folderId,
        operation: 'delete',
      );
    });
    _poke();
  }
}
