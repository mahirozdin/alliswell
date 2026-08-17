import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'api_key_models.dart';

/// REST client for the API-keys screen (OPH-265, ADR-0032).
///
/// Direct-to-API like `AiApi`, NOT the sync protocol: a key list is per-user
/// server state, not a synced entity. It deliberately never reaches the local
/// replica — an offline copy of "which credentials exist" would be a second
/// place to leak from, and a stale one at that.
class ApiKeysApi {
  const ApiKeysApi(this._dio);
  final Dio _dio;

  Future<List<ApiKey>> list(String workspaceId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/api-keys',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((k) => ApiKey.fromJson(k as Map<String, dynamic>))
        .toList();
  });

  /// Mints a key. The response carries the secret ONCE — the caller shows it
  /// immediately and keeps nothing.
  Future<NewApiKey> create(
    String workspaceId, {
    required String name,
    int? expiresInDays,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/api-keys',
      data: {'name': name, 'expiresInDays': ?expiresInDays},
    );
    return NewApiKey.fromJson(res.data!);
  });

  Future<ApiKey> revoke(String keyId) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/api-keys/$keyId/revoke',
    );
    return ApiKey.fromJson(res.data!);
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
