import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'team_ai_models.dart';

/// The team AI credential client (EE-111), behind `team.manage_ai_keys`.
///
/// Shaped after `EePortalLinksApi`: `load()` returns null for 403/404 — "not
/// yours" or "no team here" — because neither is an error to put in front of
/// somebody.
///
/// Every method returns `void` except the load. There is no `get(id)` and no
/// method that could return a key, and that is not an omission to fill in
/// later: no endpoint exists to back one. The class shape is the client-side
/// half of the same promise the serializer keeps.
class EeTeamAiApi {
  const EeTeamAiApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/ai';

  Future<EeTeamAiData?> load() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/connections');
      return EeTeamAiData.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  /// Stores (or replaces) the key for one provider. The plaintext travels
  /// exactly once, in this direction only.
  Future<void> save({
    required String provider,
    String? apiKey,
    String? baseUrl,
    String? chatModel,
    String? fastModel,
  }) => _run(
    () => _dio.post<void>(
      '$_base/connections',
      data: {
        'provider': provider,
        // Null-aware entries: an absent key means "leave it to the server's
        // default", which is a different request from sending null.
        'apiKey': ?apiKey,
        'baseUrl': ?baseUrl,
        'defaultChatModel': ?chatModel,
        'defaultFastModel': ?fastModel,
      },
    ),
  );

  Future<void> remove(String id) =>
      _run(() => _dio.delete<void>('$_base/connections/$id'));

  Future<void> setPersonalKeysAllowed(bool allowed) => _run(
    () => _dio.patch<void>(
      '$_base/policy',
      data: {'personalKeysAllowed': allowed},
    ),
  );

  Future<void> _run(Future<void> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      // The server's sentences reach the screen intact. One of them is the
      // operator-facing 503 about a missing EE_AI_TOKEN_KEY, and replacing it
      // with a generic failure would hide the only actionable thing in it.
      throw asApiException(e);
    }
  }
}
