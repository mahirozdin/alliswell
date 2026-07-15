import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';
import '../../../sync/streams.dart';
import 'note.dart';

const _snippetLength = 160;
const _maxPlainText = 60000;

enum NotesFilter { all, pinned, archived }

class NotesQuery {
  const NotesQuery({this.filter = NotesFilter.all, this.search = ''});

  final NotesFilter filter;
  final String search;

  NotesQuery copyWith({NotesFilter? filter, String? search}) =>
      NotesQuery(filter: filter ?? this.filter, search: search ?? this.search);
}

/// Searchable plain text from delta ops — mirrors the server's derivation
/// (apps/api src/lib/delta.js) so offline search matches server search.
String plainTextFromDelta(List<Map<String, dynamic>>? ops) {
  if (ops == null) return '';
  final text = ops
      .map((op) => op['insert'])
      .whereType<String>()
      .join()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length > _maxPlainText ? text.substring(0, _maxPlainText) : text;
}

/// Local-first note access (OPH-054). Search is a case-insensitive substring
/// scan over title+plainText — the offline stand-in for server FULLTEXT.
class NoteStore {
  NoteStore(this._db, this._poke);

  final AwDatabase _db;
  final void Function() _poke;

  Stream<List<NoteRow>> watchList(String workspaceId, NotesQuery query) =>
      (_db.select(_db.notes)
            ..where((n) => n.workspaceId.equals(workspaceId))
            ..orderBy([(n) => OrderingTerm.desc(n.id)]))
          .watch()
          .map((rows) {
            final needle = query.search.trim().toLowerCase();
            return [
              for (final r in rows)
                if (_matches(r, query, needle)) _row(r),
            ];
          });

  bool _matches(NoteRecord r, NotesQuery query, String needle) {
    switch (query.filter) {
      case NotesFilter.archived:
        if (!r.isArchived) return false;
      case NotesFilter.pinned:
        if (!r.isPinned || r.isArchived) return false;
      case NotesFilter.all:
        if (r.isArchived) return false;
    }
    if (needle.isEmpty) return true;
    return '${r.title} ${r.plainText ?? ''}'.toLowerCase().contains(needle);
  }

  /// A project's notes: directly attached (projectId) ∪ link-attached,
  /// archived hidden — mirrors `GET /projects/:id/notes`.
  Stream<List<NoteRow>> watchForProject(String workspaceId, String projectId) =>
      combineLatest2(
        (_db.select(_db.notes)
              ..where((n) => n.workspaceId.equals(workspaceId))
              ..orderBy([(n) => OrderingTerm.desc(n.id)]))
            .watch(),
        (_db.select(_db.noteLinkRows)..where(
              (l) =>
                  l.entityType.equals('project') & l.entityId.equals(projectId),
            ))
            .watch(),
        (rows, links) {
          final linked = {for (final l in links) l.noteId};
          return [
            for (final r in rows)
              if (!r.isArchived &&
                  (r.projectId == projectId || linked.contains(r.id)))
                _row(r),
          ];
        },
      );

  Stream<NoteDetail> watchDetail(String noteId) => combineLatest2(
    (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(noteId))).watchSingleOrNull(),
    (_db.select(
      _db.noteLinkRows,
    )..where((l) => l.noteId.equals(noteId))).watch(),
    (record, links) => record == null ? null : _detail(record, links),
  ).where((n) => n != null).map((n) => n!);

  Future<String> create(String workspaceId, Map<String, dynamic> body) async {
    final id = newUlid();
    final delta = (body['contentDelta'] as List?)?.cast<Map<String, dynamic>>();
    await _db.transaction(() async {
      await _db
          .into(_db.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              title: (body['title'] as String).trim(),
              projectId: Value(body['projectId'] as String?),
              contentDelta: Value(delta == null ? null : jsonEncode(delta)),
              contentMarkdown: Value(body['contentMarkdown'] as String?),
              plainText: Value(plainTextFromDelta(delta)),
              isPinned: Value((body['isPinned'] as bool?) ?? false),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'note',
        entityId: id,
        operation: 'create',
        patch: body,
      );
    });
    _poke();
    return id;
  }

  Future<void> update(String noteId, Map<String, dynamic> patch) async {
    final record = await (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(noteId))).getSingleOrNull();
    if (record == null) return;

    var companion = NotesCompanion(updatedAt: Value(DateTime.now().toUtc()));
    if (patch.containsKey('title')) {
      companion = companion.copyWith(
        title: Value((patch['title'] as String).trim()),
      );
    }
    if (patch.containsKey('contentDelta')) {
      final delta = (patch['contentDelta'] as List?)
          ?.cast<Map<String, dynamic>>();
      companion = companion.copyWith(
        contentDelta: Value(delta == null ? null : jsonEncode(delta)),
        plainText: Value(plainTextFromDelta(delta)),
      );
    }
    if (patch.containsKey('contentMarkdown')) {
      companion = companion.copyWith(
        contentMarkdown: Value(patch['contentMarkdown'] as String?),
      );
    }
    if (patch.containsKey('projectId')) {
      companion = companion.copyWith(
        projectId: Value(patch['projectId'] as String?),
      );
    }
    if (patch.containsKey('isPinned')) {
      companion = companion.copyWith(
        isPinned: Value(patch['isPinned'] as bool),
      );
    }
    if (patch.containsKey('isArchived')) {
      companion = companion.copyWith(
        isArchived: Value(patch['isArchived'] as bool),
      );
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.notes,
      )..where((n) => n.id.equals(noteId))).write(companion);
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'note',
        entityId: noteId,
        operation: 'update',
        patch: patch,
      );
    });
    _poke();
  }

  Future<void> delete(String noteId) async {
    final record = await (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(noteId))).getSingleOrNull();
    if (record == null) return;
    await _db.transaction(() async {
      await (_db.delete(_db.notes)..where((n) => n.id.equals(noteId))).go();
      await (_db.delete(
        _db.noteLinkRows,
      )..where((l) => l.noteId.equals(noteId))).go();
      await enqueueMutation(
        _db,
        workspaceId: record.workspaceId,
        entityType: 'note',
        entityId: noteId,
        operation: 'delete',
      );
    });
    _poke();
  }

  NoteRow _row(NoteRecord r) => NoteRow(
    id: r.id,
    workspaceId: r.workspaceId,
    projectId: r.projectId,
    createdFromTaskId: r.createdFromTaskId,
    title: r.title,
    snippet: _snippet(r.plainText),
    isPinned: r.isPinned,
    isArchived: r.isArchived,
    revision: r.revision,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  NoteDetail _detail(NoteRecord r, List<NoteLinkRow> links) => NoteDetail(
    id: r.id,
    workspaceId: r.workspaceId,
    projectId: r.projectId,
    createdFromTaskId: r.createdFromTaskId,
    title: r.title,
    snippet: _snippet(r.plainText),
    isPinned: r.isPinned,
    isArchived: r.isArchived,
    revision: r.revision,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    contentDelta: r.contentDelta == null
        ? null
        : (jsonDecode(r.contentDelta!) as List).cast<Map<String, dynamic>>(),
    contentMarkdown: r.contentMarkdown,
    links: [
      for (final l in links)
        NoteLink(id: l.id, entityType: l.entityType, entityId: l.entityId),
    ],
  );

  String _snippet(String? plainText) {
    final text = plainText ?? '';
    return text.length > _snippetLength
        ? text.substring(0, _snippetLength)
        : text;
  }
}
