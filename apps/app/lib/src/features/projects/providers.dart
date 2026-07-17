import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/project.dart';
import 'data/project_store.dart';

/// Projects list toggle: show the active projects or the archived ones
/// (OPH-110). Archived projects are hidden from the default view.
class ProjectsShowArchived extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final projectsShowArchivedProvider =
    NotifierProvider<ProjectsShowArchived, bool>(ProjectsShowArchived.new);

/// Local-first store (OPH-054): reads watch the drift replica, writes are
/// optimistic + outbox'd.
final projectStoreProvider = Provider<ProjectStore>(
  (ref) => ProjectStore(
    ref.watch(databaseProvider),
    () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);

/// Projects of the current workspace (sort_order, created_at) — live from the
/// local replica; the sync engine converges with the server in the background.
final projectsControllerProvider =
    StreamNotifierProvider<ProjectsController, List<Project>>(
      ProjectsController.new,
    );

/// Projects keyed by id, for O(1) name+color lookups on task rows — the
/// project badge (OPH-104) resolves a task's project without a per-row query.
final projectsByIdProvider = Provider<Map<String, Project>>((ref) {
  final projects = ref.watch(projectsControllerProvider).value ?? const [];
  return {for (final project in projects) project.id: project};
});

class ProjectsController extends StreamNotifier<List<Project>> {
  @override
  Stream<List<Project>> build() async* {
    ref.watch(syncEngineProvider);
    final workspaces = await ref.watch(workspacesProvider.future);
    if (workspaces.isEmpty) {
      yield const [];
      return;
    }
    yield* ref.watch(projectStoreProvider).watchAll(workspaces.first.id);
  }

  Future<String> _workspaceId() async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    return workspaces.first.id;
  }

  Future<void> createProject(Map<String, dynamic> body) async {
    await ref.read(projectStoreProvider).create(await _workspaceId(), body);
  }

  Future<void> updateProject(String id, Map<String, dynamic> patch) =>
      ref.read(projectStoreProvider).update(id, patch);

  Future<void> toggleFavorite(Project project) =>
      updateProject(project.id, {'isFavorite': !project.isFavorite});

  Future<void> deleteProject(String id) =>
      ref.read(projectStoreProvider).delete(id);

  /// Archive/unarchive (OPH-110). With no cascade it is a plain optimistic
  /// status flip through the outbox (works offline). WITH a cascade it is a
  /// multi-entity server transaction, so it goes over REST and we pull to
  /// converge the replica — hence it needs a connection.
  Future<void> archiveProject(
    String id, {
    bool includeTasks = false,
    bool includeNotes = false,
  }) => _transition(
    id,
    endpoint: 'archive',
    status: 'archived',
    includeTasks: includeTasks,
    includeNotes: includeNotes,
  );

  Future<void> unarchiveProject(
    String id, {
    bool includeTasks = false,
    bool includeNotes = false,
  }) => _transition(
    id,
    endpoint: 'unarchive',
    status: 'active',
    includeTasks: includeTasks,
    includeNotes: includeNotes,
  );

  Future<void> _transition(
    String id, {
    required String endpoint,
    required String status,
    required bool includeTasks,
    required bool includeNotes,
  }) async {
    if (!includeTasks && !includeNotes) {
      await updateProject(id, {'status': status});
      return;
    }
    await ref.read(apiClientProvider).post(
      '/api/v1/projects/$id/$endpoint',
      data: {'includeTasks': includeTasks, 'includeNotes': includeNotes},
    );
    await ref.read(syncEngineProvider)?.syncNow();
  }
}
