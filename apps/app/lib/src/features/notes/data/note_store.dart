import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/fold.dart';
import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';
import '../../../sync/streams.dart';
import 'note.dart';

const _snippetLength = 160;
const _maxPlainText = 60000;

enum NotesFilter { all, pinned, archived, readmes }

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

  /// The note ids that are a project's README (OPH-109). README notes live in
  /// their project's Overview, so the ordinary notes lists hide them; only the
  /// 'READMEs' filter surfaces them.
  Stream<Set<String>> _readmeNoteIds(String workspaceId) =>
      (_db.select(
        _db.projects,
      )..where((p) => p.workspaceId.equals(workspaceId))).watch().map(
        (rows) => {
          for (final p in rows)
            if (p.readmeNoteId != null) p.readmeNoteId!,
        },
      );

  Stream<List<NoteRow>> watchList(String workspaceId, NotesQuery query) =>
      combineLatest2(
        (_db.select(_db.notes)
              ..where((n) => n.workspaceId.equals(workspaceId))
              ..orderBy([(n) => OrderingTerm.desc(n.id)]))
            .watch(),
        _readmeNoteIds(workspaceId),
        (rows, readmeIds) {
          // OPH-167 (ADR-0013): search folds — case- AND Turkish-accent-
          // insensitive, every word must match somewhere (AND, order-free).
          final words = query.search.trim().isEmpty
              ? const <String>[]
              : foldSearchText(
                  query.search,
                ).split(' ').where((w) => w.isNotEmpty).toList();
          final hits = [
            for (final r in rows)
              if (_matches(r, query, words, readmeIds.contains(r.id)))
                (_tier(r, words), _row(r)),
          ];
          if (words.isNotEmpty) {
            // Ranked tiers (S3): title hits above body hits, stable within.
            hits.sort((a, b) => a.$1.compareTo(b.$1));
          }
          return [for (final hit in hits) hit.$2];
        },
      );

  /// 0 = every word in the title, 2 = body carried the match.
  int _tier(NoteRecord r, List<String> words) {
    if (words.isEmpty) return 0;
    final title = r.titleFold ?? foldSearchText(r.title);
    return words.every(title.contains) ? 0 : 2;
  }

  bool _matches(
    NoteRecord r,
    NotesQuery query,
    List<String> words,
    bool isReadme,
  ) {
    switch (query.filter) {
      case NotesFilter.readmes:
        if (!isReadme) return false;
      case NotesFilter.archived:
        if (isReadme || !r.isArchived) return false;
      case NotesFilter.pinned:
        if (isReadme || !r.isPinned || r.isArchived) return false;
      case NotesFilter.all:
        // README notes belong to their project's Overview, not the notes list.
        if (isReadme || r.isArchived) return false;
    }
    if (words.isEmpty) return true;
    // Fold columns arrive with v6; rows written before the migration ran (or
    // by an older peer) fold on the fly — correctness beats the fast path.
    final haystack =
        '${r.titleFold ?? foldSearchText(r.title)} '
        '${r.bodyFold ?? foldSearchText(r.plainText ?? '')}';
    return words.every(haystack.contains);
  }

  /// A project's notes: directly attached (projectId) ∪ link-attached,
  /// archived hidden — mirrors `GET /projects/:id/notes`. The project's OWN
  /// README is excluded (OPH-109): it lives in the Overview tab, not here.
  Stream<List<NoteRow>> watchForProject(String workspaceId, String projectId) =>
      combineLatest3(
        (_db.select(_db.notes)
              ..where((n) => n.workspaceId.equals(workspaceId))
              ..orderBy([(n) => OrderingTerm.desc(n.id)]))
            .watch(),
        (_db.select(_db.noteLinkRows)..where(
              (l) =>
                  l.entityType.equals('project') & l.entityId.equals(projectId),
            ))
            .watch(),
        (_db.select(
          _db.projects,
        )..where((p) => p.id.equals(projectId))).watchSingleOrNull(),
        (rows, links, project) {
          final linked = {for (final l in links) l.noteId};
          final readmeId = project?.readmeNoteId;
          return [
            for (final r in rows)
              if (!r.isArchived &&
                  r.id != readmeId &&
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
              titleFold: Value(
                foldSearchText((body['title'] as String).trim()),
              ),
              projectId: Value(body['projectId'] as String?),
              contentDelta: Value(delta == null ? null : jsonEncode(delta)),
              contentMarkdown: Value(body['contentMarkdown'] as String?),
              plainText: Value(plainTextFromDelta(delta)),
              bodyFold: Value(foldSearchText(plainTextFromDelta(delta))),
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
        titleFold: Value(foldSearchText((patch['title'] as String).trim())),
      );
    }
    if (patch.containsKey('contentDelta')) {
      final delta = (patch['contentDelta'] as List?)
          ?.cast<Map<String, dynamic>>();
      companion = companion.copyWith(
        contentDelta: Value(delta == null ? null : jsonEncode(delta)),
        plainText: Value(plainTextFromDelta(delta)),
        bodyFold: Value(foldSearchText(plainTextFromDelta(delta))),
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
