import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tasks/data/task_store.dart' show kPlanningStatuses;
import '../features/tasks/providers.dart'
    show taskScopeProvider, taskStoreProvider;
import '../features/workspaces/workspaces.dart';
import '../sync/db/database.dart';
import '../sync/providers.dart';
import 'providers.dart';
import 'search.dart';

/// Search everywhere (OPH-374, ADR-0055, DESIGN §40).
///
/// One palette over five kinds, read from the replica through the same fold
/// registry every per-screen search uses (ADR-0013, OPH-326) — so it works
/// with no signal, and "matches" means the same thing on every surface.
enum GlobalSearchKind { task, project, note, tag, file }

/// One row of the palette: enough to draw it and to open it, nothing else.
class GlobalSearchItem {
  const GlobalSearchItem({
    required this.kind,
    required this.id,
    required this.title,
    this.context,
    this.done = false,
    this.archived = false,
    this.mime,
  });

  final GlobalSearchKind kind;
  final String id;
  final String title;

  /// The secondary line: WHERE it hit (a `#tag`, a body snippet — DESIGN S3)
  /// or, for a title hit, the project it lives in.
  final String? context;

  /// A completed task — drawn with a check, still found (ADR-0055).
  final bool done;

  /// An archived project — drawn with a label, still found.
  final bool archived;

  /// Files only: the icon follows the type.
  final String? mime;
}

/// One kind's results: the first [kGlobalSearchGroupLimit] rows and how many
/// matched in all.
class GlobalSearchGroup {
  const GlobalSearchGroup({
    required this.kind,
    required this.items,
    required this.total,
  });

  final GlobalSearchKind kind;
  final List<GlobalSearchItem> items;
  final int total;
}

/// Rows per group. Five of each keeps all five kinds on one screen; the count
/// in the header says when there are more, and the screen's own search is
/// where a long list belongs.
const int kGlobalSearchGroupLimit = 5;

/// The statuses the palette finds tasks in: what Home plans with, the inbox,
/// and completed work (shown with a check). Cancelled work is out — it was
/// decided against, and finding it from everywhere would put it back in play.
const List<String> kGlobalSearchTaskStatuses = [
  ...kPlanningStatuses,
  'inbox',
  'completed',
];

/// The palette's results for [query], groups in the fixed order tasks,
/// projects, notes, tags, files; empty groups dropped. Empty query → `[]`.
///
/// Tasks follow the person's task scope (Home's: in an organisation, their
/// own work across every unit). Projects, notes, tags and files are the
/// active workspace's — the content screens' scope (LESSONS flutter-app).
final globalSearchProvider = FutureProvider.autoDispose
    .family<List<GlobalSearchGroup>, String>((ref, rawQuery) async {
      final query = rawQuery.trim();
      if (query.isEmpty) return const [];
      final service = ref.watch(searchServiceProvider);
      final db = ref.watch(databaseProvider);
      final words = SearchService.queryWords(query);

      final scope = await ref.watch(taskScopeProvider.future);
      final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);

      final hits = <GlobalSearchKind, List<SearchHit>>{
        GlobalSearchKind.task: scope == null
            ? const []
            : await searchTasksInScope(
                service: service,
                store: ref.read(taskStoreProvider),
                scope: scope,
                query: query,
                statuses: kGlobalSearchTaskStatuses,
              ),
        if (workspaceId != null) ...{
          GlobalSearchKind.project: await service.searchProjects(
            workspaceId,
            query,
          ),
          GlobalSearchKind.note: await service.searchNotes(workspaceId, query),
          GlobalSearchKind.tag: await service.searchTags(workspaceId, query),
          GlobalSearchKind.file: await service.searchFiles(workspaceId, query),
        },
      };

      final groups = <GlobalSearchGroup>[];
      for (final kind in GlobalSearchKind.values) {
        final kindHits = hits[kind] ?? const <SearchHit>[];
        if (kindHits.isEmpty) continue;
        final shown = kindHits.take(kGlobalSearchGroupLimit).toList();
        final items = await resolveGlobalSearchItems(
          db,
          kind,
          [for (final hit in shown) hit.id],
          tiers: {for (final hit in shown) hit.id: hit.tier},
          words: words,
        );
        if (items.isEmpty) continue;
        groups.add(
          GlobalSearchGroup(kind: kind, items: items, total: kindHits.length),
        );
      }
      return groups;
    });

/// Reads [ids] of one [kind] from the replica, IN THE ORDER GIVEN, dropping
/// any that are gone. [tiers] (search hits) decide the context line; without
/// them (recents) every row reads as a title hit.
Future<List<GlobalSearchItem>> resolveGlobalSearchItems(
  AwDatabase db,
  GlobalSearchKind kind,
  List<String> ids, {
  Map<String, int> tiers = const {},
  List<String> words = const [],
}) async {
  if (ids.isEmpty) return const [];
  final placeholders = List.filled(ids.length, '?').join(', ');
  final vars = [for (final id in ids) Variable.withString(id)];
  Future<List<QueryRow>> select(String sql) =>
      db.customSelect(sql, variables: vars).get();
  final firstWord = words.isEmpty ? '' : words.first;

  final byId = <String, GlobalSearchItem>{};
  switch (kind) {
    case GlobalSearchKind.task:
      final rows = await select(
        'SELECT t.id, t.title, t.status, t.description, p.name AS project '
        'FROM tasks t LEFT JOIN projects p ON p.id = t.project_id '
        'WHERE t.id IN ($placeholders)',
      );
      final tagNames = await _tagNamesFor(db, [
        for (final row in rows)
          if (tiers[row.read<String>('id')] == 1) row.read<String>('id'),
      ]);
      for (final row in rows) {
        final id = row.read<String>('id');
        final tier = tiers[id] ?? 0;
        final description = row.read<String?>('description');
        final String? context;
        if (tier == 1) {
          context = _matchingTag(tagNames[id] ?? const [], words);
        } else if (tier == 2 && description != null) {
          context = searchSnippet(description, firstWord);
        } else {
          context = row.read<String?>('project');
        }
        byId[id] = GlobalSearchItem(
          kind: kind,
          id: id,
          title: row.read<String>('title'),
          context: context,
          done: row.read<String>('status') == 'completed',
        );
      }
    case GlobalSearchKind.project:
      final rows = await select(
        'SELECT id, name, status, description FROM projects '
        'WHERE id IN ($placeholders)',
      );
      for (final row in rows) {
        final id = row.read<String>('id');
        final description = row.read<String?>('description');
        byId[id] = GlobalSearchItem(
          kind: kind,
          id: id,
          title: row.read<String>('name'),
          context: tiers[id] == 2 && description != null
              ? searchSnippet(description, firstWord)
              : null,
          archived: row.read<String>('status') == 'archived',
        );
      }
    case GlobalSearchKind.note:
      final rows = await select(
        'SELECT n.id, n.title, n.plain_text, p.name AS project '
        'FROM notes n LEFT JOIN projects p ON p.id = n.project_id '
        'WHERE n.id IN ($placeholders)',
      );
      for (final row in rows) {
        final id = row.read<String>('id');
        final body = row.read<String?>('plain_text');
        byId[id] = GlobalSearchItem(
          kind: kind,
          id: id,
          title: row.read<String>('title'),
          context: tiers[id] == 2 && body != null
              ? searchSnippet(body, firstWord)
              : row.read<String?>('project'),
        );
      }
    case GlobalSearchKind.tag:
      final rows = await select(
        'SELECT id, name FROM tags WHERE id IN ($placeholders)',
      );
      for (final row in rows) {
        final id = row.read<String>('id');
        byId[id] = GlobalSearchItem(
          kind: kind,
          id: id,
          title: '#${row.read<String>('name')}',
        );
      }
    case GlobalSearchKind.file:
      final rows = await select(
        'SELECT id, name, mime FROM file_rows WHERE id IN ($placeholders)',
      );
      for (final row in rows) {
        final id = row.read<String>('id');
        byId[id] = GlobalSearchItem(
          kind: kind,
          id: id,
          title: row.read<String>('name'),
          mime: row.read<String>('mime'),
        );
      }
  }
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}

/// Task id → its tags' (name, folded name), for the tier-1 context line.
Future<Map<String, List<(String, String)>>> _tagNamesFor(
  AwDatabase db,
  List<String> taskIds,
) async {
  if (taskIds.isEmpty) return const {};
  final rows = await db
      .customSelect(
        'SELECT tt.task_id AS task_id, g.name AS name, g.name_fold AS fold '
        'FROM task_tag_rows tt JOIN tags g ON g.id = tt.tag_id '
        'WHERE tt.task_id IN (${List.filled(taskIds.length, '?').join(', ')}) '
        'ORDER BY g.name ASC',
        variables: [for (final id in taskIds) Variable.withString(id)],
      )
      .get();
  final out = <String, List<(String, String)>>{};
  for (final row in rows) {
    out.putIfAbsent(row.read<String>('task_id'), () => []).add((
      row.read<String>('name'),
      row.read<String?>('fold') ?? '',
    ));
  }
  return out;
}

/// The first tag carrying a query word, as `#name` — the honest "it hit
/// here" for a tag-tier task (DESIGN S3).
String? _matchingTag(List<(String, String)> tags, List<String> words) {
  for (final (name, fold) in tags) {
    if (words.any(fold.contains)) return '#$name';
  }
  return tags.isEmpty ? null : '#${tags.first.$1}';
}
