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

  /// The whole team's feed (EE-130), for somebody holding `team.view_audit`.
  ///
  /// Every filter is optional and an absent one is OMITTED rather than sent
  /// empty: the server's querystring schema is `additionalProperties: false`
  /// with typed fields, so `verb=''` is a 400 and `verb` absent is "no filter".
  /// Those are different requests and only one of them is what a cleared
  /// dropdown means.
  Future<EeHistoryPage> teamFeed({
    String? verb,
    String? actorId,
    String? entityType,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/audit',
        queryParameters: {
          'limit': limit,
          'cursor': ?cursor,
          'verb': ?verb,
          'actorId': ?actorId,
          'entityType': ?entityType,
          'from': ?from?.toUtc().toIso8601String(),
          'to': ?to?.toUtc().toIso8601String(),
        },
      );
      return EeHistoryPage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      // 403 is NOT swallowed here, unlike the 404 above. "You may not read
      // this team's history" is a fact the screen must show, because the
      // alternative is an empty list that reads as "nothing has happened" —
      // and on an audit screen that is the most misleading empty state there
      // is.
      if (e.response?.statusCode == 404) return const EeHistoryPage(items: []);
      throw asApiException(e);
    }
  }
}
