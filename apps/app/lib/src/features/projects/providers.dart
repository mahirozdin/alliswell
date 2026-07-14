import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/project.dart';
import 'data/projects_api.dart';

final projectsApiProvider = Provider<ProjectsApi>(
  (ref) => ProjectsApi(ref.watch(apiClientProvider)),
);

/// Projects of the current workspace, server-ordered (sort_order, created_at).
/// Mutations re-fetch — the server is the source of truth for ordering and
/// revisions (local-first caching lands with Epic 06).
final projectsControllerProvider =
    AsyncNotifierProvider<ProjectsController, List<Project>>(
      ProjectsController.new,
    );

class ProjectsController extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final workspaces = await ref.watch(workspacesProvider.future);
    if (workspaces.isEmpty) return const [];
    return ref.watch(projectsApiProvider).list(workspaces.first.id);
  }

  Future<String> _workspaceId() async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    return workspaces.first.id;
  }

  Future<void> _refetch() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> createProject(Map<String, dynamic> body) async {
    await ref.read(projectsApiProvider).create(await _workspaceId(), body);
    await _refetch();
  }

  Future<void> updateProject(String id, Map<String, dynamic> patch) async {
    await ref.read(projectsApiProvider).update(id, patch);
    await _refetch();
  }

  Future<void> toggleFavorite(Project project) =>
      updateProject(project.id, {'isFavorite': !project.isFavorite});

  Future<void> deleteProject(String id) async {
    await ref.read(projectsApiProvider).delete(id);
    await _refetch();
  }
}
