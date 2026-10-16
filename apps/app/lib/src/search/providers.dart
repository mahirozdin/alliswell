import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tasks/data/task_scope.dart';
import '../features/tasks/data/task_store.dart';
import '../features/tasks/providers.dart'
    show taskScopeProvider, taskStoreProvider;
import '../features/workspaces/workspaces.dart';
import '../sync/providers.dart';
import 'search.dart';

final searchServiceProvider = Provider<SearchService>(
  (ref) => SearchService(ref.watch(databaseProvider)),
);

/// One tiny notifier per screen — search state never leaks across screens
/// (DESIGN S5: entering/leaving search mutates nothing else).
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;

  void clear() => state = '';
}

final homeSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);
final projectsSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

class HomeSearchResults {
  const HomeSearchResults({required this.tasks, required this.events});

  final List<SearchHit> tasks;
  final List<SearchHit> events;

  bool get isEmpty => tasks.isEmpty && events.isEmpty;
}

/// Home search: every task the product plans with (planning statuses AND
/// inbox captures — BLUEPRINT §12.10) plus the user's calendar events.
/// Null = search off (empty query).
final homeSearchResultsProvider =
    FutureProvider.autoDispose<HomeSearchResults?>((ref) async {
      final query = ref.watch(homeSearchQueryProvider).trim();
      if (query.isEmpty) return null;
      final scope = await ref.watch(taskScopeProvider.future);
      if (scope == null) return null;
      final service = ref.watch(searchServiceProvider);
      final tasks = await searchTasksInScope(
        service: service,
        store: ref.read(taskStoreProvider),
        scope: scope,
        query: query,
        statuses: const [...kPlanningStatuses, 'inbox'],
      );
      // The calendar is a person's own; in an organisation's workspaces there
      // is none to search (it is not connected there).
      final events = scope.mineFor != null
          ? const <SearchHit>[]
          : await service.searchEvents(scope.workspaceIds.single, query);
      return HomeSearchResults(tasks: tasks, events: events);
    });

/// Tasks of [statuses] in a person's [scope], ranked — Home's search and the
/// global palette (OPH-374) ask the same question, so it is answered once.
///
/// Home searches what Home shows: one workspace for a person on their own; a
/// member's own work across every workspace they are in.
Future<List<SearchHit>> searchTasksInScope({
  required SearchService service,
  required TaskStore store,
  required TaskScope scope,
  required String query,
  required List<String> statuses,
}) async {
  final tasks = <SearchHit>[
    for (final workspaceId in scope.workspaceIds)
      ...await service.searchTasks(workspaceId, query, statuses: statuses),
  ];
  if (scope.mineFor != null) {
    final mine = await store.idsIn(scope, statuses);
    tasks.retainWhere((hit) => mine.contains(hit.id));
    // Each workspace came back ranked; together they rank by tier again
    // (`sort` is stable, so a workspace's own order survives inside one).
    tasks.sort((a, b) => a.tier.compareTo(b.tier));
  }
  return tasks;
}

/// Projects search: ranked ids, or null when search is off.
final projectsSearchResultsProvider =
    FutureProvider.autoDispose<List<SearchHit>?>((ref) async {
      final query = ref.watch(projectsSearchQueryProvider).trim();
      if (query.isEmpty) return null;
      final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
      if (workspaceId == null) return null;
      return ref
          .watch(searchServiceProvider)
          .searchProjects(workspaceId, query);
    });
