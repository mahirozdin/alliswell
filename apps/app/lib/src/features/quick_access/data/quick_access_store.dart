import 'package:drift/drift.dart';

import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';
import 'quick_link.dart';

/// Drops local shortcuts to targets that just died on THIS device (OPH-198).
///
/// A free function, not a store method, so the entity stores can call it
/// inside their own delete transaction without taking a dependency on Quick
/// Access. It writes NO outbox mutation: the server cascades the shortcut when
/// it processes the target's delete (OPH-197), and a second delete mutation
/// would claim the user removed a shortcut they never touched. This only keeps
/// the current device from rendering a broken row for one round trip.
Future<void> forgetQuickLinksFor(
  AwDatabase db, {
  required String workspaceId,
  required QuickKind kind,
  required List<String> targetIds,
}) async {
  if (targetIds.isEmpty) return;
  await (db.delete(db.quickLinks)..where(
        (q) =>
            q.workspaceId.equals(workspaceId) &
            q.kind.equals(kind.name) &
            q.targetId.isIn(targetIds),
      ))
      .go();
}

/// Local-first quick access writes (OPH-198, ADR-0018) — the FolderStore
/// shape: optimistic drift row + outbox mutation in ONE transaction, then poke
/// the engine. Every operation works offline; the server re-runs the same
/// rules on push (limit, duplicate, target existence) and the pull converges.
class QuickAccessStore {
  QuickAccessStore(this._db, {void Function()? onMutation})
    : _poke = onMutation ?? (() {});

  final AwDatabase _db;
  final void Function() _poke;

  /// Gap between neighbours; mirrors the server's step so a pull does not
  /// reshuffle what the user just dragged.
  static const int sortStep = 1024;

  /// The cap the server enforces (`QUICK_LINK_LIMIT`), checked here too so the
  /// UI can refuse honestly while offline.
  static const int maxLinks = 50;

  /// The user's rail, each row joined to its target's live state.
  ///
  /// One `customSelect` with five LEFT JOINs rather than five combined
  /// streams: drift re-emits when ANY table in [readsFrom] changes, so
  /// renaming a project updates the rail without a second subscription. A
  /// missing `readsFrom` entry is not a compile error — it is a rail that
  /// silently stops updating, which is why the set is spelled out.
  ///
  /// No `LIMIT`: the list is capped at 50 rows, so the OPH-186 pagination trap
  /// (a JOIN multiplying rows inside the window) cannot arise here.
  Stream<List<QuickAccessRow>> watchMine(String workspaceId, String userId) {
    final query = _db.customSelect(
      '''
      SELECT q.*,
             p.name          AS project_name,
             p.color_rgb     AS project_color,
             p.status        AS project_status,
             t.title         AS task_title,
             t.status        AS task_status,
             n.title         AS note_title,
             n.is_archived   AS note_archived,
             fo.name         AS folder_name,
             fi.name         AS file_name
        FROM quick_links q
        LEFT JOIN projects  p  ON q.kind = 'project' AND p.id  = q.target_id
        LEFT JOIN tasks     t  ON q.kind = 'task'    AND t.id  = q.target_id
        LEFT JOIN notes     n  ON q.kind = 'note'    AND n.id  = q.target_id
        LEFT JOIN folders   fo ON q.kind = 'folder'  AND fo.id = q.target_id
        LEFT JOIN file_rows fi ON q.kind = 'file'    AND fi.id = q.target_id
       WHERE q.workspace_id = ?1 AND q.user_id = ?2
       ORDER BY q.sort_order ASC, q.id ASC
      ''',
      variables: [
        Variable.withString(workspaceId),
        Variable.withString(userId),
      ],
      readsFrom: {
        _db.quickLinks,
        _db.projects,
        _db.tasks,
        _db.notes,
        _db.folders,
        _db.fileRows,
      },
    );
    return query.watch().map((rows) => [for (final row in rows) ?_rowOf(row)]);
  }

  QuickAccessRow? _rowOf(QueryRow row) {
    final kind = QuickKind.parse(row.read<String>('kind'));
    if (kind == null) return null; // a kind this build does not know
    final link = QuickLink(
      id: row.read<String>('id'),
      workspaceId: row.read<String>('workspace_id'),
      userId: row.read<String>('user_id'),
      kind: kind,
      title: row.read<String>('title'),
      targetId: row.readNullable<String>('target_id'),
      url: row.readNullable<String>('url'),
      emoji: row.readNullable<String>('emoji'),
      colorRgb: row.readNullable<String>('color_rgb'),
      sortOrder: row.read<int>('sort_order'),
    );

    final targetTitle = switch (kind) {
      QuickKind.project => row.readNullable<String>('project_name'),
      QuickKind.task => row.readNullable<String>('task_title'),
      QuickKind.note => row.readNullable<String>('note_title'),
      QuickKind.folder => row.readNullable<String>('folder_name'),
      QuickKind.file => row.readNullable<String>('file_name'),
      QuickKind.url => null,
    };
    final taskStatus = row.readNullable<String>('task_status');
    return QuickAccessRow(
      link: link,
      targetTitle: targetTitle,
      targetColorRgb: kind == QuickKind.project
          ? row.readNullable<String>('project_color')
          : null,
      isArchived:
          row.readNullable<String>('project_status') == 'archived' ||
          taskStatus == 'archived' ||
          (row.readNullable<int>('note_archived') ?? 0) == 1,
      isCompleted: taskStatus == 'completed',
      // Archive is reversible and never breaks a shortcut (ADR-0018 §4); only
      // a target the replica does not have at all counts as broken.
      isBroken: kind.isEntity && targetTitle == null,
    );
  }

  /// How many shortcuts the user already has — the offline half of the limit.
  Future<int> countMine(String workspaceId, String userId) async {
    final rows =
        await (_db.select(_db.quickLinks)..where(
              (q) =>
                  q.workspaceId.equals(workspaceId) & q.userId.equals(userId),
            ))
            .get();
    return rows.length;
  }

  /// True when this target already sits on the rail — the menus render
  /// "remove" instead of "add" from this (OPH-201).
  Future<String?> idForTarget(
    String workspaceId,
    String userId,
    QuickKind kind,
    String targetId,
  ) async {
    final rows =
        await (_db.select(_db.quickLinks)..where(
              (q) =>
                  q.workspaceId.equals(workspaceId) &
                  q.userId.equals(userId) &
                  q.kind.equals(kind.name) &
                  q.targetId.equals(targetId),
            ))
            .get();
    return rows.isEmpty ? null : rows.first.id;
  }

  /// Adds a shortcut at the tail. Returns its id, or null when the rail is
  /// already full — the caller shows the honest message (OPH-201).
  Future<String?> add({
    required String workspaceId,
    required String userId,
    required QuickKind kind,
    required String title,
    String? targetId,
    String? url,
    String? emoji,
    String? colorRgb,
  }) async {
    if (await countMine(workspaceId, userId) >= maxLinks) return null;
    final existing = kind.isEntity && targetId != null
        ? await idForTarget(workspaceId, userId, kind, targetId)
        : null;
    if (existing != null) return existing; // adding twice is a no-op, not a row

    final id = newUlid();
    final now = DateTime.now().toUtc();
    final tail = await _nextSortOrder(workspaceId, userId);
    await _db.transaction(() async {
      await _db
          .into(_db.quickLinks)
          .insert(
            QuickLinksCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              userId: userId,
              kind: kind.name,
              title: title.trim(),
              targetId: Value(targetId),
              url: Value(url),
              emoji: Value(emoji),
              colorRgb: Value(colorRgb),
              sortOrder: Value(tail),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'quick_link',
        entityId: id,
        operation: 'create',
        patch: {
          'kind': kind.name,
          'title': title.trim(),
          'targetId': ?targetId,
          'url': ?url,
          'emoji': ?emoji,
          'colorRgb': ?colorRgb,
        },
      );
    });
    _poke();
    return id;
  }

  Future<void> rename(String id, String title) =>
      _update(id, {'title': title.trim()});

  /// `null` clears the emoji and returns the row to its kind icon.
  Future<void> setEmoji(String id, String? emoji) =>
      _update(id, {'emoji': emoji});

  Future<void> setColor(String id, String? colorRgb) =>
      _update(id, {'colorRgb': colorRgb});

  Future<void> remove(String id) async {
    final record = await (_db.select(
      _db.quickLinks,
    )..where((q) => q.id.equals(id))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.delete(_db.quickLinks)..where((q) => q.id.equals(id))).go();
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'quick_link',
        entityId: id,
        operation: 'delete',
      );
    });
    _poke();
  }

  /// Writes the whole order as ONE mutation (OPH-197's protocol note): an
  /// ordinary `update` on the head row carrying the virtual `orderedIds`
  /// field. Fifty separate updates would be fifty revisions and fifty chances
  /// for a partial order to survive a failure.
  Future<void> reorder(String workspaceId, List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await _db.transaction(() async {
      for (final (index, id) in orderedIds.indexed) {
        await (_db.update(_db.quickLinks)..where((q) => q.id.equals(id))).write(
          QuickLinksCompanion(
            sortOrder: Value(index * sortStep),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'quick_link',
        // The anchor is the head of the new order — derivable from the list
        // alone, so two clients producing the same order agree on it.
        entityId: orderedIds.first,
        operation: 'update',
        patch: {'orderedIds': orderedIds},
      );
    });
    _poke();
  }

  /// See [forgetQuickLinksFor].
  Future<void> forgetTargets(
    String workspaceId,
    QuickKind kind,
    List<String> targetIds,
  ) => forgetQuickLinksFor(
    _db,
    workspaceId: workspaceId,
    kind: kind,
    targetIds: targetIds,
  );

  Future<int> _nextSortOrder(String workspaceId, String userId) async {
    final rows =
        await (_db.select(_db.quickLinks)
              ..where(
                (q) =>
                    q.workspaceId.equals(workspaceId) & q.userId.equals(userId),
              )
              ..orderBy([(q) => OrderingTerm.asc(q.sortOrder)]))
            .get();
    if (rows.isEmpty) return 0;
    return rows.last.sortOrder + sortStep;
  }

  Future<void> _update(String id, Map<String, dynamic> patch) async {
    final record = await (_db.select(
      _db.quickLinks,
    )..where((q) => q.id.equals(id))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.update(_db.quickLinks)..where((q) => q.id.equals(id))).write(
        QuickLinksCompanion(
          title: patch.containsKey('title')
              ? Value(patch['title'] as String)
              : const Value.absent(),
          emoji: patch.containsKey('emoji')
              ? Value(patch['emoji'] as String?)
              : const Value.absent(),
          colorRgb: patch.containsKey('colorRgb')
              ? Value(patch['colorRgb'] as String?)
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'quick_link',
        entityId: id,
        operation: 'update',
        patch: patch,
      );
    });
    _poke();
  }
}
