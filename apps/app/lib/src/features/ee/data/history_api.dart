import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'history_models.dart';

/// REST client for the history surface (EE-024/EE-026). History is
/// server-only — there is no replica to read, which is why every screen using
/// this shows a real error instead of an empty list when the server is
/// unreachable (the api_keys lesson).
class EeHistoryApi {
  const EeHistoryApi(this._dio);
  final Dio _dio;

  Future<EeHistoryPage> forEntity({
    required String entityType,
    required String entityId,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/history/$entityType/$entityId',
        queryParameters: {'limit': limit, 'cursor': ?cursor},
      );
      return EeHistoryPage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      // 404 is the house answer for "not your team" AND "no such history" —
      // indistinguishable on purpose, so the app treats it as "nothing here"
      // rather than showing an error that implies the thing exists.
      if (e.response?.statusCode == 404) return const EeHistoryPage(items: []);
      throw asApiException(e);
    }
  }
}
