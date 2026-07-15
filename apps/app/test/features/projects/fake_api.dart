import 'package:dio/dio.dart';

import '../auth/test_support.dart';

/// In-memory AllisWell API for project/task widget tests: serves /me plus
/// stateful projects/tasks/tags collections the way apps/api does — including
/// the sync protocol (`/sync/pull` + `/sync/push`) the local-first app speaks
/// since OPH-054.
class FakeApi {
  final String workspaceId = '01WSAAAAAAAAAAAAAAAAAAAAAA';
  final List<Map<String, dynamic>> projects = [];
  final List<Map<String, dynamic>> tasks = [];
  final List<Map<String, dynamic>> tags = [];
  final List<Map<String, dynamic>> notes = [];
  final List<String> requests = [];

  /// Workspace revision + tombstones for the pull endpoint.
  int revision = 0;
  final List<Map<String, String>> deleted = [];
  int _seq = 0;

  void _bump() => revision += 1;

  Map<String, dynamic> seedNote({
    required String title,
    String plainText = '',
    bool isPinned = false,
    bool isArchived = false,
    String? projectId,
    List<Map<String, dynamic>>? contentDelta,
  }) {
    final note = _note({
      'title': title,
      'contentDelta':
          contentDelta ??
          [
            {'insert': '$plainText\n'},
          ],
      'projectId': projectId,
      'isPinned': isPinned,
    });
    note['isArchived'] = isArchived;
    notes.add(note);
    _bump();
    return note;
  }

  Map<String, dynamic> seedTag({required String name}) {
    _seq += 1;
    final tag = {
      'id': 'TAG$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'name': name,
      'slug': name.toLowerCase(),
      'colorRgb': '#64748B',
      'icon': null,
      'revision': 1,
    };
    tags.add(tag);
    _bump();
    return tag;
  }

  Map<String, dynamic> seedTask({
    required String title,
    String status = 'open',
    String priority = 'none',
    bool isUrgent = false,
    String? dueAt,
    List<String> tagIds = const [],
    List<Map<String, dynamic>> checklist = const [],
  }) {
    final task = _task({
      'title': title,
      'status': status,
      'priority': priority,
      'isUrgent': isUrgent,
      'dueAt': dueAt,
      'tagIds': tagIds,
      'checklist': checklist,
    });
    tasks.add(task);
    _bump();
    return task;
  }

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
    _bump();
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

    if (path == '/api/v1/sync/pull') return _syncPull(options);
    if (path == '/api/v1/sync/push' && options.method == 'POST') {
      return _syncPush(body ?? const {});
    }

    if (path == '/api/v1/workspaces/$workspaceId/projects') {
      if (options.method == 'GET') return jsonBody(200, {'items': projects});
      if (options.method == 'POST') {
        final project = _project(body ?? const {});
        projects.add(project);
        return jsonBody(201, project);
      }
    }

    if (path == '/api/v1/workspaces/$workspaceId/tags' &&
        options.method == 'GET') {
      return jsonBody(200, {'items': tags});
    }

    if (path == '/api/v1/workspaces/$workspaceId/notes') {
      if (options.method == 'GET') {
        final params = options.uri.queryParameters;
        var items = params['archived'] != null
            ? notes
                  .where(
                    (n) =>
                        (n['isArchived'] == true) ==
                        (params['archived'] == 'true'),
                  )
                  .toList()
            : notes.where((n) => n['isArchived'] != true).toList();
        if (params['pinned'] == 'true') {
          items = items.where((n) => n['isPinned'] == true).toList();
        }
        final q = params['q']?.toLowerCase();
        if (q != null && q.isNotEmpty) {
          items = items
              .where(
                (n) => ('${n['title']} ${n['plainText']}')
                    .toLowerCase()
                    .contains(q),
              )
              .toList();
        }
        return jsonBody(200, {'items': items, 'nextCursor': null});
      }
      if (options.method == 'POST') {
        final note = _note(body ?? const {});
        notes.add(note);
        return jsonBody(201, note);
      }
    }

    final projectNotes = RegExp(
      r'^/api/v1/projects/([^/]+)/notes$',
    ).firstMatch(path);
    if (projectNotes != null && options.method == 'GET') {
      final items = notes
          .where((n) => n['projectId'] == projectNotes.group(1))
          .toList();
      return jsonBody(200, {'items': items, 'nextCursor': null});
    }

    final singleNote = RegExp(r'^/api/v1/notes/([^/]+)$').firstMatch(path);
    if (singleNote != null) {
      final index = notes.indexWhere((n) => n['id'] == singleNote.group(1));
      if (index < 0) return _notFound('NOTE_NOT_FOUND');
      switch (options.method) {
        case 'GET':
          return jsonBody(200, notes[index]);
        case 'PATCH':
          notes[index] = {
            ...notes[index],
            ...?body,
            'revision': (notes[index]['revision'] as int) + 1,
          };
          return jsonBody(200, notes[index]);
        case 'DELETE':
          notes.removeAt(index);
          return ResponseBody.fromString('', 204);
      }
    }

    if (path == '/api/v1/workspaces/$workspaceId/tasks') {
      if (options.method == 'GET') {
        return jsonBody(200, {
          'items': _filteredTasks(options.uri.queryParametersAll),
          'nextCursor': null,
        });
      }
      if (options.method == 'POST') {
        final task = _task(body ?? const {});
        tasks.add(task);
        return jsonBody(201, task);
      }
    }

    final taskAction = RegExp(
      r'^/api/v1/tasks/([^/]+)/(complete|reopen|snooze|tags|checklist)(?:/([^/]+))?$',
    ).firstMatch(path);
    if (taskAction != null) {
      return _handleTaskAction(
        options.method,
        taskAction.group(1)!,
        taskAction.group(2)!,
        taskAction.group(3),
        body,
      );
    }

    final singleTask = RegExp(r'^/api/v1/tasks/([^/]+)$').firstMatch(path);
    if (singleTask != null) {
      final index = tasks.indexWhere((t) => t['id'] == singleTask.group(1));
      if (index < 0) return _notFound('TASK_NOT_FOUND');
      switch (options.method) {
        case 'GET':
          return jsonBody(200, tasks[index]);
        case 'PATCH':
          tasks[index] = {
            ...tasks[index],
            ...?body,
            'revision': (tasks[index]['revision'] as int) + 1,
          };
          if (body?['status'] == 'completed') {
            tasks[index]['completedAt'] = '2026-07-14T12:00:00.000Z';
          }
          return jsonBody(200, tasks[index]);
        case 'DELETE':
          tasks.removeAt(index);
          return ResponseBody.fromString('', 204);
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

  List<Map<String, dynamic>> _filteredTasks(Map<String, List<String>> query) {
    final statuses = query['status'];
    final projectId = query['projectId']?.first;
    final dueFrom = query['dueFrom']?.first;
    final dueTo = query['dueTo']?.first;
    return tasks.where((t) {
      if (statuses != null && !statuses.contains(t['status'])) return false;
      if (projectId != null && t['projectId'] != projectId) return false;
      final due = t['dueAt'] as String?;
      if (dueFrom != null && (due == null || due.compareTo(dueFrom) < 0)) {
        return false;
      }
      if (dueTo != null && (due == null || due.compareTo(dueTo) > 0)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<ResponseBody> _handleTaskAction(
    String method,
    String taskId,
    String action,
    String? itemId,
    Map<String, dynamic>? body,
  ) async {
    final index = tasks.indexWhere((t) => t['id'] == taskId);
    if (index < 0) return _notFound('TASK_NOT_FOUND');
    final task = tasks[index];

    switch (action) {
      case 'complete':
        task['status'] = 'completed';
        task['completedAt'] = '2026-07-14T12:00:00.000Z';
        return jsonBody(200, task);
      case 'reopen':
        task['status'] = 'open';
        task['completedAt'] = null;
        return jsonBody(200, task);
      case 'snooze':
        task['snoozedUntil'] =
            body?['snoozeUntil'] ?? '2026-07-15T06:00:00.000Z';
        return jsonBody(200, task);
      case 'tags':
        task['tagIds'] = (body?['tagIds'] as List?)?.cast<String>() ?? [];
        return jsonBody(200, task);
      case 'checklist':
        final checklist = (task['checklist'] as List)
            .cast<Map<String, dynamic>>();
        if (method == 'POST') {
          _seq += 1;
          final item = {
            'id': 'CHK$_seq'.padRight(26, '0'),
            'taskId': taskId,
            'title': body?['title'],
            'isDone': false,
            'sortOrder': checklist.length,
            'revision': 1,
          };
          checklist.add(item);
          return jsonBody(201, item);
        }
        final itemIndex = checklist.indexWhere((i) => i['id'] == itemId);
        if (itemIndex < 0) return _notFound('CHECKLIST_ITEM_NOT_FOUND');
        if (method == 'PATCH') {
          checklist[itemIndex] = {...checklist[itemIndex], ...?body};
          return jsonBody(200, checklist[itemIndex]);
        }
        if (method == 'DELETE') {
          checklist.removeAt(itemIndex);
          return ResponseBody.fromString('', 204);
        }
    }
    return _notFound('NOT_FOUND');
  }

  // ── Sync protocol (OPH-054c): full-state snapshots + tombstones ───────────

  Future<ResponseBody> _syncPull(RequestOptions options) async {
    final since = int.parse(options.uri.queryParameters['sinceRevision']!);
    final changes = <Map<String, dynamic>>[];
    if (since < revision) {
      void snapshot(String type, Map<String, dynamic> data) {
        changes.add({
          'revision': revision,
          'entityType': type,
          'entityId': data['id'],
          'operation': 'update',
          'data': data,
        });
      }

      for (final p in projects) {
        snapshot('project', p);
      }
      for (final t in tags) {
        snapshot('tag', t);
      }
      for (final t in tasks) {
        snapshot('task', t);
        for (final item in (t['checklist'] as List? ?? const [])) {
          snapshot('checklist_item', {
            ...(item as Map).cast<String, dynamic>(),
            'taskId': t['id'],
          });
        }
      }
      for (final n in notes) {
        snapshot('note', {'links': const [], ...n});
      }
      for (final d in deleted) {
        changes.add({
          'revision': revision,
          'entityType': d['entityType'],
          'entityId': d['entityId'],
          'operation': 'delete',
          'data': null,
        });
      }
    }
    return jsonBody(200, {
      'workspaceId': workspaceId,
      'fromRevision': since,
      'toRevision': since > revision ? since : revision,
      'hasMore': false,
      'changes': changes,
    });
  }

  Future<ResponseBody> _syncPush(Map<String, dynamic> body) async {
    final mutations = ((body['mutations'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final results = <Map<String, dynamic>>[];
    for (final m in mutations) {
      _bump();
      _applyMutation(m);
      results.add({
        'clientMutationId': m['clientMutationId'],
        'status': 'applied',
        'revision': revision,
        'errorCode': null,
        'replayed': false,
        'discardedFields': const <String>[],
      });
    }
    return jsonBody(200, {
      'workspaceId': workspaceId,
      'toRevision': revision,
      'results': results,
    });
  }

  void _applyMutation(Map<String, dynamic> m) {
    final entityId = m['entityId'] as String;
    final operation = m['operation'] as String;
    final patch = ((m['patch'] as Map?) ?? const {}).cast<String, dynamic>();

    List<Map<String, dynamic>>? collection = switch (m['entityType']) {
      'project' => projects,
      'task' => tasks,
      'note' => notes,
      'tag' => tags,
      _ => null,
    };

    switch (m['entityType']) {
      case 'checklist_item':
        _applyChecklistMutation(entityId, operation, patch);
      case 'project' || 'task' || 'note' || 'tag':
        final index = collection!.indexWhere((e) => e['id'] == entityId);
        if (operation == 'create') {
          if (index >= 0) return;
          collection.add(switch (m['entityType']) {
            'project' => _project({...patch, 'id': entityId}),
            'task' => _task({...patch, 'id': entityId}),
            'note' => {
              'links': const [],
              ..._note({...patch, 'id': entityId}),
            },
            _ => {
              'id': entityId,
              'workspaceId': workspaceId,
              'name': patch['name'],
              'slug': (patch['name'] as String).toLowerCase(),
              'colorRgb': patch['colorRgb'] ?? '#64748B',
              'icon': null,
              'revision': 1,
            },
          });
        } else if (operation == 'update' && index >= 0) {
          final merged = {...collection[index], ...patch};
          merged['revision'] = (collection[index]['revision'] as int) + 1;
          if (m['entityType'] == 'task' && patch.containsKey('status')) {
            merged['completedAt'] = patch['status'] == 'completed'
                ? '2026-07-14T12:00:00.000Z'
                : null;
          }
          if (m['entityType'] == 'note' && patch.containsKey('contentDelta')) {
            final plain = ((patch['contentDelta'] as List?) ?? const [])
                .map((op) => (op as Map)['insert'])
                .whereType<String>()
                .join()
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            merged['plainText'] = plain;
            merged['snippet'] = plain;
          }
          collection[index] = merged;
        } else if (operation == 'delete' && index >= 0) {
          collection.removeAt(index);
          deleted.add({
            'entityType': m['entityType'] as String,
            'entityId': entityId,
          });
        }
    }
  }

  void _applyChecklistMutation(
    String entityId,
    String operation,
    Map<String, dynamic> patch,
  ) {
    if (operation == 'create') {
      final task = tasks.firstWhere(
        (t) => t['id'] == patch['taskId'],
        orElse: () => const {},
      );
      if (task.isEmpty) return;
      (task['checklist'] as List).add({
        'id': entityId,
        'taskId': patch['taskId'],
        'title': patch['title'],
        'isDone': false,
        'sortOrder': patch['sortOrder'] ?? 0,
        'revision': 1,
      });
      return;
    }
    for (final task in tasks) {
      final checklist = ((task['checklist'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final index = checklist.indexWhere((i) => i['id'] == entityId);
      if (index < 0) continue;
      if (operation == 'update') {
        checklist[index] = {...checklist[index], ...patch};
      } else {
        checklist.removeAt(index);
        deleted.add({'entityType': 'checklist_item', 'entityId': entityId});
      }
      return;
    }
  }

  Future<ResponseBody> _notFound(String code) async => jsonBody(404, {
    'statusCode': 404,
    'code': code,
    'error': 'Not Found',
    'message': code,
  });

  Map<String, dynamic> _task(Map<String, dynamic> body) {
    _seq += 1;
    return {
      'id': (body['id'] as String?) ?? 'TSK$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'projectId': body['projectId'],
      'parentTaskId': body['parentTaskId'],
      'title': body['title'] ?? 'Untitled',
      'description': body['description'],
      'status': body['status'] ?? 'open',
      'priority': body['priority'] ?? 'none',
      'colorRgb': null,
      'startAt': null,
      'dueAt': body['dueAt'],
      'scheduledStartAt': null,
      'scheduledEndAt': null,
      'remindAt': body['remindAt'],
      'snoozedUntil': null,
      'timezone': 'Europe/Istanbul',
      'isUrgent': body['isUrgent'] ?? false,
      'requiresAcknowledgement': body['isUrgent'] ?? false,
      'repeatRule': null,
      'estimatedMinutes': null,
      'actualMinutes': null,
      'sortOrder': 0,
      'completedAt': null,
      'revision': 1,
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:00:00.000Z',
      'tagIds': (body['tagIds'] as List?)?.cast<String>() ?? <String>[],
      'checklist':
          (body['checklist'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _note(Map<String, dynamic> body) {
    _seq += 1;
    final delta = (body['contentDelta'] as List?)?.cast<Map<String, dynamic>>();
    final plain = (delta ?? const [])
        .map((op) => op['insert'])
        .whereType<String>()
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return {
      'id': (body['id'] as String?) ?? 'NOT$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'projectId': body['projectId'],
      'createdFromTaskId': null,
      'title': body['title'] ?? 'Untitled',
      'snippet': plain,
      'plainText': plain,
      'contentDelta': delta,
      'contentMarkdown': body['contentMarkdown'],
      'isPinned': body['isPinned'] ?? false,
      'isArchived': false,
      'links': <Map<String, dynamic>>[],
      'revision': 1,
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:00:00.000Z',
    };
  }

  Map<String, dynamic> _project(Map<String, dynamic> body) {
    _seq += 1;
    return {
      'id': (body['id'] as String?) ?? 'PRJ$_seq'.padRight(26, '0'),
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
