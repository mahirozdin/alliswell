import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'project.dart';

/// HTTP calls for `/api/v1/**/projects` — uses the authenticated dio
/// ([apiClientProvider]) so tokens attach and refresh transparently.
class ProjectsApi {
  const ProjectsApi(this._dio);

  final Dio _dio;

  Future<List<Project>> list(String workspaceId, {String? status}) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/projects',
        queryParameters: {'status': ?status},
      ),
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((p) => Project.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<Project> create(String workspaceId, Map<String, dynamic> body) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/projects',
        data: body,
      ),
    );
    return Project.fromJson(res.data!);
  }

  Future<Project> update(String projectId, Map<String, dynamic> patch) async {
    final res = await _run(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/v1/projects/$projectId',
        data: patch,
      ),
    );
    return Project.fromJson(res.data!);
  }

  Future<void> delete(String projectId) async {
    await _run(() => _dio.delete<void>('/api/v1/projects/$projectId'));
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
