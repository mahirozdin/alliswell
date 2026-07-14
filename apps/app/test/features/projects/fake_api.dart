import 'package:dio/dio.dart';

import '../auth/test_support.dart';

/// In-memory AllisWell API for project/task widget tests: serves /me and a
/// stateful projects collection the way apps/api does.
class FakeApi {
  final String workspaceId = '01WSAAAAAAAAAAAAAAAAAAAAAA';
  final List<Map<String, dynamic>> projects = [];
  final List<String> requests = [];
  int _seq = 0;

  Map<String, dynamic> seedProject({
    required String name,
    String colorRgb = '#2563EB',
    String status = 'active',
    bool isFavorite = false,
    String? description,
  }) {
    final project = _project({
      'name': name,
      'colorRgb': colorRgb,
      'status': status,
      'isFavorite': isFavorite,
      'description': ?description,
    });
    projects.add(project);
    return project;
  }

  Future<ResponseBody> handle(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    final path = options.uri.path;
    requests.add('${options.method} $path');

    if (path == '/api/v1/me') {
      return jsonBody(200, {
        'user': {
          'id': 'user-1',
          'email': 'mahir@example.com',
          'displayName': 'Mahir',
          'timezone': 'Europe/Istanbul',
          'locale': 'tr-TR',
          'createdAt': '2026-07-14T00:00:00.000Z',
        },
        'workspaces': [
          {
            'id': workspaceId,
            'name': "Mahir's Space",
            'slug': 'mahir-s-space',
            'colorRgb': '#2563EB',
            'icon': null,
            'role': 'owner',
          },
        ],
      });
    }

    if (path == '/api/v1/workspaces/$workspaceId/projects') {
      if (options.method == 'GET') return jsonBody(200, {'items': projects});
      if (options.method == 'POST') {
        final project = _project(body ?? const {});
        projects.add(project);
        return jsonBody(201, project);
      }
    }

    final single = RegExp(r'^/api/v1/projects/([^/]+)$').firstMatch(path);
    if (single != null) {
      final index = projects.indexWhere((p) => p['id'] == single.group(1));
      if (index < 0) {
        return jsonBody(404, {
          'statusCode': 404,
          'code': 'PROJECT_NOT_FOUND',
          'error': 'Not Found',
          'message': 'Project not found',
        });
      }
      switch (options.method) {
        case 'GET':
          return jsonBody(200, projects[index]);
        case 'PATCH':
          projects[index] = {
            ...projects[index],
            ...?body,
            'revision': (projects[index]['revision'] as int) + 1,
          };
          return jsonBody(200, projects[index]);
        case 'DELETE':
          projects.removeAt(index);
          return ResponseBody.fromString('', 204);
      }
    }

    return jsonBody(404, {
      'statusCode': 404,
      'code': 'NOT_FOUND',
      'error': 'Not Found',
      'message': 'No fake route for $path',
    });
  }

  Map<String, dynamic> _project(Map<String, dynamic> body) {
    _seq += 1;
    return {
      'id': 'PRJ$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'name': body['name'] ?? 'Untitled',
      'description': body['description'],
      'colorRgb': body['colorRgb'] ?? '#2563EB',
      'icon': null,
      'status': body['status'] ?? 'active',
      'startAt': null,
      'dueAt': null,
      'sortOrder': 0,
      'isFavorite': body['isFavorite'] ?? false,
      'revision': 1,
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:00:00.000Z',
    };
  }
}
