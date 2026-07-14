import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/data/projects_api.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';

import '../auth/test_support.dart';

void main() {
  test('Project.fromJson maps the API shape, colors parse with fallback', () {
    final project = Project.fromJson({
      'id': 'p1',
      'workspaceId': 'ws1',
      'name': 'Launch',
      'description': null,
      'colorRgb': '#FF8800',
      'icon': null,
      'status': 'active',
      'startAt': null,
      'dueAt': '2026-08-01T12:00:00.000Z',
      'sortOrder': 3,
      'isFavorite': true,
      'revision': 7,
    });
    expect(project.name, 'Launch');
    expect(project.dueAt, DateTime.parse('2026-08-01T12:00:00.000Z'));
    expect(project.isFavorite, isTrue);
    expect(project.color, const Color(0xFFFF8800));

    expect(colorFromRgbHex('garbage'), const Color(0xFF2563EB)); // fallback
  });

  test('WorkspaceSummary.fromJson tolerates missing color', () {
    final ws = WorkspaceSummary.fromJson({
      'id': 'w1',
      'name': 'Space',
      'slug': 'space',
      'colorRgb': null,
      'icon': null,
      'role': 'owner',
    });
    expect(ws.colorRgb, '#2563EB');
    expect(ws.role, 'owner');
  });

  test('ProjectsApi hits the documented endpoints and maps errors', () async {
    final adapter = FakeHttpClientAdapter((options, body) async {
      if (options.method == 'GET') {
        expect(options.uri.path, '/api/v1/workspaces/ws1/projects');
        expect(options.uri.queryParameters['status'], 'active');
        return jsonBody(200, {'items': []});
      }
      expect(body, {'name': 'X'});
      return jsonBody(403, {
        'statusCode': 403,
        'code': 'AUTH_WORKSPACE_FORBIDDEN',
        'error': 'Forbidden',
        'message': 'nope',
      });
    });
    final api = ProjectsApi(fakeDio(adapter));

    expect(await api.list('ws1', status: 'active'), isEmpty);
    await expectLater(
      api.create('ws1', {'name': 'X'}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'AUTH_WORKSPACE_FORBIDDEN',
        ),
      ),
    );
  });
}
