import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'note.dart';

class NoteListPage {
  const NoteListPage({required this.items, this.nextCursor});

  final List<NoteRow> items;
  final String? nextCursor;
}

/// HTTP calls for `/api/v1/**/notes`.
class NotesApi {
  const NotesApi(this._dio);

  final Dio _dio;

  Future<NoteListPage> list(
    String workspaceId, {
    bool? pinned,
    bool? archived,
    bool? includeArchived,
    String? projectId,
    String? taskId,
    String? query,
    int? limit,
    String? cursor,
  }) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/notes',
        queryParameters: {
          'pinned': ?pinned?.toString(),
          'archived': ?archived?.toString(),
          'includeArchived': ?includeArchived?.toString(),
          'projectId': ?projectId,
          'taskId': ?taskId,
          'q': ?query,
          'limit': ?limit?.toString(),
          'cursor': ?cursor,
        },
      ),
    );
    return _page(res);
  }

  Future<NoteListPage> listForProject(String projectId) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>('/api/v1/projects/$projectId/notes'),
    );
    return _page(res);
  }

  Future<NoteDetail> create(
    String workspaceId,
    Map<String, dynamic> body,
  ) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/notes',
        data: body,
      ),
    );
    return NoteDetail.fromJson(res.data!);
  }

  Future<NoteDetail> get(String noteId) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>('/api/v1/notes/$noteId'),
    );
    return NoteDetail.fromJson(res.data!);
  }

  Future<NoteDetail> update(String noteId, Map<String, dynamic> patch) async {
    final res = await _run(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/v1/notes/$noteId',
        data: patch,
      ),
    );
    return NoteDetail.fromJson(res.data!);
  }

  Future<void> delete(String noteId) async {
    await _run(() => _dio.delete<void>('/api/v1/notes/$noteId'));
  }

  NoteListPage _page(Response<Map<String, dynamic>> res) {
    final items = ((res.data?['items'] as List?) ?? const [])
        .map((n) => NoteRow.fromJson(n as Map<String, dynamic>))
        .toList();
    return NoteListPage(
      items: items,
      nextCursor: res.data?['nextCursor'] as String?,
    );
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
