import 'package:drift/drift.dart';

import '../../../core/fold.dart';
import '../../../core/list_sort.dart';
import '../../../sync/db/database.dart';

/// One attachment's metadata (OPH-153, Epic 14, ADR-0011).
///
/// Only metadata lives here — the bytes are in object storage and are fetched
/// through short-lived download URLs minted by the API on demand. Rows arrive
/// exclusively via sync pull (the store below has no write path; uploads and
/// deletes are REST + `syncNow()`).
/// What a file list can be ordered by (OPH-258, DESIGN §34 L4).
///
/// The ids match the labels the project Files tab has used since OPH-170, so a
/// tab that shipped with `date | name | size` keeps the same vocabulary — it
/// just stops forgetting the choice between rebuilds.
const kFileSortChoices = [
  AwSortChoice(id: 'date', labelKey: 'sort.fileDate'),
  AwSortChoice(
    id: 'name',
    labelKey: 'sort.fileName',
    descendingByDefault: false,
  ),
  AwSortChoice(id: 'size', labelKey: 'sort.fileSize'),
];

/// Orders files for [sort]; ties break on the id so the list never shuffles.
Comparator<FileAttachment> fileSortComparator(AwSortState sort) {
  int ascending(FileAttachment a, FileAttachment b) => switch (sort.id) {
    'name' => foldSearchText(a.name).compareTo(foldSearchText(b.name)),
    'size' => a.sizeBytes.compareTo(b.sizeBytes),
    _ => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    ),
  };
  final ordered = sort.comparator<FileAttachment>(ascending);
  return (a, b) {
    final result = ordered(a, b);
    return result != 0 ? result : b.id.compareTo(a.id);
  };
}

class FileAttachment {
  const FileAttachment({
    required this.id,
    required this.workspaceId,
    required this.targetType,
    required this.targetId,
    required this.name,
    required this.mime,
    required this.sizeBytes,
    this.uploadedBy,
    this.createdAt,
    this.folderId,
  });

  final String id;
  final String workspaceId;

  /// `project` | `task` | `note`.
  final String targetType;
  final String targetId;
  final String name;
  final String mime;
  final int sizeBytes;
  final String? uploadedBy;
  final DateTime? createdAt;

  /// Folder membership — workspace-target files only (OPH-170).
  final String? folderId;

  bool get isImage => mime.startsWith('image/');
  bool get isVideo => mime.startsWith('video/');
  bool get isAudio => mime.startsWith('audio/');
}

/// A row of the project "Files" tab: the file plus where it came from.
class ProjectFileEntry {
  const ProjectFileEntry({
    required this.file,
    required this.sourceType,
    required this.sourceId,
    required this.sourceTitle,
  });

  final FileAttachment file;

  /// `project` | `task` | `note` — the entity the file hangs off.
  final String sourceType;
  final String sourceId;
  final String sourceTitle;
}

/// Local-first reads over the replica. Pull-only by construction — there is
/// no write path here at all (the ExternalEventStore guarantee): uploads and
/// deletes go through `FilesApi`, and the replica converges via sync.
class FileStore {
  FileStore(this._db);

  final AwDatabase _db;

  /// One file by id — how note embeds resolve `alliswell://file/{id}` to a
  /// name/mime (OPH-156). Null when the row hasn't synced yet or is gone.
  Future<FileAttachment?> byId(String id) async {
    final row = await (_db.select(
      _db.fileRows,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    return row == null ? null : _attachment(row);
  }

  /// One entity's attachments, newest first.
  Stream<List<FileAttachment>> watchForTarget({
    required String targetType,
    required String targetId,
  }) =>
      (_db.select(_db.fileRows)
            ..where(
              (f) =>
                  f.targetType.equals(targetType) & f.targetId.equals(targetId),
            )
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]))
          .watch()
          .map((rows) => rows.map(_attachment).toList());

  /// The project "Files" tab aggregate (ATTACHMENTS.md §6): the project's own
  /// files ∪ its tasks' ∪ its notes' files, each row naming its source. One
  /// SQL union so it stays a single live stream over the replica.
  Stream<List<ProjectFileEntry>> watchForProject(String projectId) {
    final query = _db.customSelect(
      '''
      SELECT f.*, 'project' AS source_type, f.target_id AS source_id,
             p.name AS source_title
        FROM file_rows f JOIN projects p ON p.id = f.target_id
       WHERE f.target_type = 'project' AND f.target_id = ?1
      UNION ALL
      SELECT f.*, 'task', t.id, t.title
        FROM file_rows f JOIN tasks t ON t.id = f.target_id
       WHERE f.target_type = 'task' AND t.project_id = ?1
      UNION ALL
      SELECT f.*, 'note', n.id, n.title
        FROM file_rows f JOIN notes n ON n.id = f.target_id
       WHERE f.target_type = 'note' AND n.project_id = ?1
      ORDER BY created_at DESC
      ''',
      variables: [Variable.withString(projectId)],
      readsFrom: {_db.fileRows, _db.projects, _db.tasks, _db.notes},
    );
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ProjectFileEntry(
              file: _fromRow(row),
              sourceType: row.read<String>('source_type'),
              sourceId: row.read<String>('source_id'),
              sourceTitle: row.read<String>('source_title'),
            ),
          )
          .toList(),
    );
  }

  /// One folder LEVEL of the Dosyalar tree: workspace-target files whose
  /// folder is [folderId] (null = the root level). Newest first.
  Stream<List<FileAttachment>> watchWorkspaceLevel(
    String workspaceId, {
    String? folderId,
  }) =>
      (_db.select(_db.fileRows)
            ..where(
              (f) =>
                  f.workspaceId.equals(workspaceId) &
                  f.targetType.equals('workspace') &
                  (folderId == null
                      ? f.folderId.isNull()
                      : f.folderId.equals(folderId)),
            )
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]))
          .watch()
          .map((rows) => rows.map(_attachment).toList());

  /// The Kaynaklar layer (DESIGN F7): every ATTACHED file in the workspace
  /// (project|task|note targets) with its source named — the project Files
  /// tab's union, workspace-wide.
  Stream<List<ProjectFileEntry>> watchWorkspaceAttached(String workspaceId) {
    final query = _db.customSelect(
      '''
      SELECT f.*, 'project' AS source_type, p.id AS source_id,
             p.name AS source_title
        FROM file_rows f JOIN projects p ON p.id = f.target_id
       WHERE f.target_type = 'project' AND f.workspace_id = ?1
      UNION ALL
      SELECT f.*, 'task', t.id, t.title
        FROM file_rows f JOIN tasks t ON t.id = f.target_id
       WHERE f.target_type = 'task' AND f.workspace_id = ?1
      UNION ALL
      SELECT f.*, 'note', n.id, n.title
        FROM file_rows f JOIN notes n ON n.id = f.target_id
       WHERE f.target_type = 'note' AND f.workspace_id = ?1
      ORDER BY created_at DESC
      ''',
      variables: [Variable.withString(workspaceId)],
      readsFrom: {_db.fileRows, _db.projects, _db.tasks, _db.notes},
    );
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ProjectFileEntry(
              file: _fromRow(row),
              sourceType: row.read<String>('source_type'),
              sourceId: row.read<String>('source_id'),
              sourceTitle: row.read<String>('source_title'),
            ),
          )
          .toList(),
    );
  }

  static FileAttachment _attachment(FileRecord r) => FileAttachment(
    id: r.id,
    workspaceId: r.workspaceId,
    targetType: r.targetType,
    targetId: r.targetId,
    name: r.name,
    mime: r.mime,
    sizeBytes: r.sizeBytes,
    uploadedBy: r.uploadedBy,
    createdAt: r.createdAt,
    folderId: r.folderId,
  );

  static FileAttachment _fromRow(QueryRow row) => FileAttachment(
    id: row.read<String>('id'),
    workspaceId: row.read<String>('workspace_id'),
    targetType: row.read<String>('target_type'),
    targetId: row.read<String>('target_id'),
    name: row.read<String>('name'),
    mime: row.read<String>('mime'),
    sizeBytes: row.read<int>('size_bytes'),
    uploadedBy: row.readNullable<String>('uploaded_by'),
    createdAt: row.readNullable<DateTime>('created_at'),
    folderId: row.readNullable<String>('folder_id'),
  );
}
