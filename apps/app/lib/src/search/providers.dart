import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tasks/data/task_store.dart';
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
      final workspaces = await ref.watch(workspacesProvider.future);
      if (workspaces.isEmpty) return null;
      final service = ref.watch(searchServiceProvider);
      final workspaceId = workspaces.first.id;
      final tasks = await service.searchTasks(
        workspaceId,
        query,
        statuses: [...kPlanningStatuses, 'inbox'],
      );
      final events = await service.searchEvents(workspaceId, query);
      return HomeSearchResults(tasks: tasks, events: events);
    });

/// Projects search: ranked ids, or null when search is off.
final projectsSearchResultsProvider =
    FutureProvider.autoDispose<List<SearchHit>?>((ref) async {
      final query = ref.watch(projectsSearchQueryProvider).trim();
      if (query.isEmpty) return null;
      final workspaces = await ref.watch(workspacesProvider.future);
      if (workspaces.isEmpty) return null;
      return ref
          .watch(searchServiceProvider)
          .searchProjects(workspaces.first.id, query);
    });
