import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../features/auth/test_support.dart';
import '../features/projects/fake_api.dart';

/// A [FakeApi] whose `/sync/push` answers notes the way the real server does
/// after ADR-0072 (OPH-486/487) — so editor-level tests exercise the whole
/// client against the rules it is written for:
///
/// - a resend of a recorded `clientMutationId` replays its answer only when
///   the payload is the same; a different payload is processed as a new write;
/// - a content update applies when it has no base, base 0, a current base, a
///   body identical to the server's, or when every write since its base came
///   from the same client; otherwise it is refused as a conflict and the body
///   is kept as a `conflict` version (this fake does not merge).
///
/// [gate] holds a push open (a slow network); [loseNextAnswer] lets the server
/// apply a push and then drops the answer (a timeout after the fact).
class NoteSyncServer extends FakeApi {
  Completer<void>? gate;
  bool loseNextAnswer = false;

  /// clientMutationId → (payload, answer).
  final recorded = <String, ({String payload, Map<String, dynamic> answer})>{};

  /// Server-side versions: id, noteId, noteRevision, origin, clientId, body.
  final versions = <Map<String, dynamic>>[];

  /// workspace revision → client id that wrote it (null = REST/foreign).
  final writers = <int, String?>{};

  /// Every mutation the server processed, in order (replays excluded).
  final processed = <Map<String, dynamic>>[];

  int _v = 0;

  Map<String, dynamic>? note(String id) {
    for (final n in notes) {
      if (n['id'] == id) return n;
    }
    return null;
  }

  /// Another device (or a REST call) rewrites a note on the server.
  void foreignWrite(String noteId, String body, {String? clientId = 'OTHER'}) {
    final n = note(noteId)!;
    revision += 1;
    n['contentMarkdown'] = body;
    n['plainText'] = body;
    n['revision'] = revision;
    writers[revision] = clientId;
    _version(n, 'edit', clientId);
  }

  @override
  Future<ResponseBody> handle(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    if (options.uri.path == '/api/v1/sync/push' && options.method == 'POST') {
      final g = gate;
      final answer = _push(body!);
      if (g != null) await g.future;
      if (loseNextAnswer) {
        loseNextAnswer = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
      return answer;
    }
    return super.handle(options, body);
  }

  void _version(
    Map<String, dynamic> n,
    String origin,
    String? clientId, {
    String? body,
  }) {
    versions.add({
      'id': 'V${(++_v).toString().padLeft(25, '0')}',
      'noteId': n['id'],
      'noteRevision': n['revision'],
      'origin': origin,
      'clientId': clientId,
      'body': body ?? n['contentMarkdown'],
    });
  }

  bool _onlyOwnSince(String noteId, int base, String? clientId) {
    final since = versions
        .where((v) => v['noteId'] == noteId && v['origin'] != 'conflict')
        .map((v) => v['noteRevision'] as int)
        .where((r) => r > base);
    return since.every((r) => writers[r] == clientId);
  }

  ResponseBody _push(Map<String, dynamic> body) {
    final clientId = body['clientId'] as String?;
    final results = <Map<String, dynamic>>[];
    for (final m in (body['mutations'] as List).cast<Map<String, dynamic>>()) {
      final id = m['clientMutationId'] as String;
      final patch = ((m['patch'] as Map?) ?? const {}).cast<String, dynamic>();
      final payload = jsonEncode([
        m['operation'],
        m['entityId'],
        patch,
        m['baseRevision'],
      ]);
      final seen = recorded[id];
      if (seen != null && seen.payload == payload) {
        results.add({...seen.answer, 'replayed': true});
        continue;
      }
      processed.add(m);
      final answer = _apply(m, patch, clientId);
      recorded[id] = (
        payload: payload,
        answer: {'clientMutationId': id, ...answer},
      );
      results.add({...recorded[id]!.answer, 'replayed': false});
    }
    return jsonBody(200, {
      'workspaceId': workspaceId,
      'toRevision': revision,
      'results': results,
    });
  }

  Map<String, dynamic> _apply(
    Map<String, dynamic> m,
    Map<String, dynamic> patch,
    String? clientId,
  ) {
    if (m['entityType'] != 'note') {
      revision += 1;
      return {'status': 'applied', 'revision': revision, 'errorCode': null};
    }
    if (m['operation'] == 'create') {
      revision += 1;
      final n = <String, dynamic>{
        'id': m['entityId'],
        'workspaceId': workspaceId,
        'projectId': patch['projectId'],
        'createdFromTaskId': null,
        'title': patch['title'] ?? 'Untitled',
        'contentMarkdown': patch['contentMarkdown'] ?? '',
        'contentFormat': 'markdown',
        'plainText': patch['contentMarkdown'] ?? '',
        'snippet': patch['contentMarkdown'] ?? '',
        'isPinned': false,
        'isArchived': false,
        'links': <Map<String, dynamic>>[],
        'revision': revision,
        'createdAt': '2026-11-18T10:00:00.000Z',
        'updatedAt': '2026-11-18T10:00:00.000Z',
      };
      notes.add(n);
      writers[revision] = clientId;
      _version(n, 'create', clientId);
      return {'status': 'applied', 'revision': revision, 'errorCode': null};
    }
    final n = note(m['entityId'] as String)!;
    final base = m['baseRevision'] as int?;
    final current = n['revision'] as int;
    final incoming = patch['contentMarkdown'] as String?;
    final content = incoming != null || patch.containsKey('title');
    final applies =
        !content ||
        base == null ||
        base == 0 ||
        base >= current ||
        incoming == n['contentMarkdown'] ||
        _onlyOwnSince(n['id'] as String, base, clientId);
    if (!applies) {
      _version(n, 'conflict', clientId, body: incoming);
      return {
        'status': 'conflict',
        'errorCode': 'NOTE_CONTENT_CONFLICT',
        'conflictVersionId': versions.last['id'],
        'reason': 'OVERLAP',
        'revision': null,
      };
    }
    revision += 1;
    n.addAll(patch);
    n['plainText'] = n['contentMarkdown'] ?? '';
    n['revision'] = revision;
    writers[revision] = clientId;
    _version(n, 'edit', clientId);
    return {'status': 'applied', 'revision': revision, 'errorCode': null};
  }
}
