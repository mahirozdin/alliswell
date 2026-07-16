import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/project.dart';
import 'data/project_store.dart';

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
}
