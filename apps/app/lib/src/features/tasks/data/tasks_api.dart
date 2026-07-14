import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'task.dart';

class TaskListPage {
  const TaskListPage({required this.items, this.nextCursor});

  final List<Task> items;
  final String? nextCursor;
}

/// HTTP calls for `/api/v1/**/tasks` and sub-resources.
class TasksApi {
  const TasksApi(this._dio);

  final Dio _dio;

  Future<TaskListPage> list(
    String workspaceId, {
    List<String>? statuses,
    String? projectId,
    String? parentTaskId,
    String? tagId,
    DateTime? dueFrom,
    DateTime? dueTo,
    bool? urgent,
    int? limit,
    String? cursor,
  }) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/tasks',
        queryParameters: {
          'status': ?statuses,
          'projectId': ?projectId,
          'parentTaskId': ?parentTaskId,
          'tagId': ?tagId,
          'dueFrom': ?dueFrom?.toUtc().toIso8601String(),
          'dueTo': ?dueTo?.toUtc().toIso8601String(),
          'urgent': ?urgent?.toString(),
          'limit': ?limit?.toString(),
          'cursor': ?cursor,
        },
        // Fastify expects repeated keys for array filters: status=a&status=b.
        options: Options(listFormat: ListFormat.multi),
      ),
    );
    final items = ((res.data?['items'] as List?) ?? const [])
        .map((t) => Task.fromJson(t as Map<String, dynamic>))
        .toList();
    return TaskListPage(
      items: items,
      nextCursor: res.data?['nextCursor'] as String?,
    );
  }

  Future<Task> create(String workspaceId, Map<String, dynamic> body) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/tasks',
        data: body,
      ),
    );
    return Task.fromJson(res.data!);
  }

  Future<Task> get(String taskId) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>('/api/v1/tasks/$taskId'),
    );
    return Task.fromJson(res.data!);
  }

  Future<Task> update(String taskId, Map<String, dynamic> patch) async {
    final res = await _run(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId',
        data: patch,
      ),
    );
    return Task.fromJson(res.data!);
  }

  Future<Task> complete(String taskId) => _transition(taskId, 'complete');

  Future<Task> reopen(String taskId) => _transition(taskId, 'reopen');

  Future<Task> snooze(String taskId, {String? preset, DateTime? until}) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/snooze',
        data: {
          'preset': ?preset,
          'snoozeUntil': ?until?.toUtc().toIso8601String(),
        },
      ),
    );
    return Task.fromJson(res.data!);
  }

  Future<Task> setTags(String taskId, List<String> tagIds) async {
    final res = await _run(
      () => _dio.put<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/tags',
        data: {'tagIds': tagIds},
      ),
    );
    return Task.fromJson(res.data!);
  }

  Future<ChecklistItem> addChecklistItem(String taskId, String title) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/checklist',
        data: {'title': title},
      ),
    );
    return ChecklistItem.fromJson(res.data!);
  }

  Future<ChecklistItem> setChecklistItemDone(
    String taskId,
    String itemId, {
    required bool isDone,
  }) async {
    final res = await _run(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/checklist/$itemId',
        data: {'isDone': isDone},
      ),
    );
    return ChecklistItem.fromJson(res.data!);
  }

  Future<void> deleteChecklistItem(String taskId, String itemId) async {
    await _run(
      () => _dio.delete<void>('/api/v1/tasks/$taskId/checklist/$itemId'),
    );
  }

  Future<Task> _transition(String taskId, String action) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>('/api/v1/tasks/$taskId/$action'),
    );
    return Task.fromJson(res.data!);
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
