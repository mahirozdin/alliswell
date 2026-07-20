import 'package:drift/drift.dart';

import '../../../core/fold.dart';
import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';

/// Local-first tag writes (round 8, OPH-165). Until now tags could only be
/// SELECTED — nothing in the app could create one. Same shape as
/// ProjectStore: optimistic drift row + outbox mutation in one transaction,
/// then poke the engine.
class TagStore {
  TagStore(this._db, {void Function()? onMutation})
    : _poke = onMutation ?? (() {});

  final AwDatabase _db;
  final void Function() _poke;

  /// The server derives the real slug from the name on push
  /// (`sync.js` — "the slug follows the name"); this provisional one only has
  /// to be locally plausible until the next pull replaces the row. Fold-based
  /// so it stays close to the server's NFKD slugify.
  static String provisionalSlug(String name) {
    final slug = foldSearchText(
      name,
    ).replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'tag' : slug;
  }

  /// Creates a tag and returns its id. Callers dedupe by folded name FIRST
  /// (the input widget does) — this always inserts.
  Future<String> create(
    String workspaceId,
    String name, {
    String? colorRgb,
  }) async {
    final id = newUlid();
    final trimmed = name.trim();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.tags)
          .insert(
            TagsCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              name: trimmed,
              slug: provisionalSlug(trimmed),
              colorRgb: colorRgb == null
                  ? const Value.absent()
                  : Value(colorRgb),
              nameFold: Value(foldSearchText(trimmed)),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'tag',
        entityId: id,
        operation: 'create',
        patch: {'name': trimmed, 'colorRgb': ?colorRgb},
      );
    });
    _poke();
    return id;
  }

  Future<void> rename(String tagId, String name) =>
      _update(tagId, name: name.trim());

  Future<void> setColor(String tagId, String colorRgb) =>
      _update(tagId, colorRgb: colorRgb);

  Future<void> _update(String tagId, {String? name, String? colorRgb}) async {
    final record = await (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(tagId))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.update(_db.tags)..where((t) => t.id.equals(tagId))).write(
        TagsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          slug: name == null
              ? const Value.absent()
              : Value(provisionalSlug(name)),
          nameFold: name == null
              ? const Value.absent()
              : Value(foldSearchText(name)),
          colorRgb: colorRgb == null ? const Value.absent() : Value(colorRgb),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'tag',
        entityId: tagId,
        operation: 'update',
        patch: {'name': ?name, 'colorRgb': ?colorRgb},
      );
    });
    _poke();
  }

  /// How many tasks carry this tag — the delete confirm names the blast
  /// radius (DESIGN F5/T3).
  Future<int> taskCount(String tagId) async {
    final rows = await (_db.select(
      _db.taskTagRows,
    )..where((r) => r.tagId.equals(tagId))).get();
    return rows.length;
  }

  /// Deletes the tag workspace-wide. Local `task_tag_rows` for it go too —
  /// the server's task snapshots stop carrying the id after its own cascade,
  /// and a dangling local join row would resurrect the chip until then.
  Future<void> delete(String tagId) async {
    final record = await (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(tagId))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTagRows,
      )..where((r) => r.tagId.equals(tagId))).go();
      await (_db.delete(_db.tags)..where((t) => t.id.equals(tagId))).go();
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'tag',
        entityId: tagId,
        operation: 'delete',
      );
    });
    _poke();
  }
}
