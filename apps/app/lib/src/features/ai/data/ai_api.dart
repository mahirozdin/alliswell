import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'ai_models.dart';

/// REST client for the AI settings surface (OPH-220). Follows the
/// GoogleIntegrationsApi shape: direct-to-API (not the sync protocol), because
/// AI connections are per-user server state, not a synced entity (AGENTS §4).
class AiApi {
  const AiApi(this._dio);
  final Dio _dio;

  Future<AiStatus> status(String workspaceId) => _run(() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/ai/status',
      );
      return AiStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      // A 404 is the honest "AI is disabled on this server" — not an error.
      if (e.response?.statusCode == 404) return AiStatus.disabled;
      rethrow;
    }
  });

  Future<List<AiConnection>> connections(String workspaceId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/ai/connections',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((c) => AiConnection.fromJson(c as Map<String, dynamic>))
        .toList();
  });

  Future<AiConnection> connect(
    String workspaceId, {
    required String provider,
    String? authMode,
    String? apiKey,
    String? baseUrl,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/ai/connections',
      data: {
        'provider': provider,
        'authMode': ?authMode,
        'apiKey': ?apiKey,
        'baseUrl': ?baseUrl,
        // The create is unreachable without the consent walk — this is its
        // durable server-side trace (DESIGN §24 AI8).
        'consentAcknowledged': true,
      },
    );
    return AiConnection.fromJson(res.data!);
  });

  Future<AiConnection> updateModels(
    String connectionId, {
    String? defaultChatModel,
    String? defaultFastModel,
  }) => _run(() async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/ai/connections/$connectionId',
      data: {
        'defaultChatModel': ?defaultChatModel,
        'defaultFastModel': ?defaultFastModel,
      },
    );
    return AiConnection.fromJson(res.data!);
  });

  Future<void> remove(String connectionId) =>
      _run(() => _dio.delete<void>('/api/v1/ai/connections/$connectionId'));

  Future<AiConnectionTest> test(String connectionId) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/ai/connections/$connectionId/test',
    );
    return AiConnectionTest.fromJson(res.data ?? const {});
  });

  /// Extraction (OPH-219): one utterance → a schema-validated proposal.
  Future<AiProposal> extract(
    String workspaceId, {
    required String text,
    required String source, // bubble | share | quick_add | voice
    String? defaultTaskTime,
    String? locale,
    List<String>? projectNames,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/ai/extract',
      data: {
        'text': text,
        'source': source,
        'defaultTaskTime': ?defaultTaskTime,
        'locale': ?locale,
        'projectNames': ?projectNames,
      },
    );
    return AiProposal.fromJson(res.data!);
  });

  /// Records the human verdict on a proposal (OPH-219). Idempotent server-side,
  /// so the offline report queue can retry safely.
  Future<void> decideAction(
    String actionId, {
    required bool accepted,
    List<Map<String, String>>? entityRefs,
  }) => _run(() async {
    await _dio.post<void>(
      '/api/v1/ai/actions/$actionId/decision',
      data: {'accepted': accepted, 'entityRefs': ?entityRefs},
    );
  });

  Future<AiModelCatalog> models(String workspaceId, {String? connectionId}) =>
      _run(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/api/v1/workspaces/$workspaceId/ai/models',
          queryParameters: {'connectionId': ?connectionId},
        );
        return AiModelCatalog.fromJson(res.data ?? const {});
      });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
