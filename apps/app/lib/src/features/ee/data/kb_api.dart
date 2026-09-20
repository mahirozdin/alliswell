import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'kb_models.dart';

/// The knowledge base (EE-195, EE-196).
///
/// Shaped after `EeAssetsApi`: a 403 or 404 on a LIST is an empty answer
/// rather than an error, because a desk that has not been given `kb.write`
/// still has a screen to draw — and drawing it as an error would tell a
/// reader the feature is broken when it is merely not theirs to edit.
///
/// A single article's 404 TRAVELS, for the reason the asset card's does: it
/// is reached by following a link, and a link that silently shows an empty
/// card is worse than one that says the article is gone.
class EeKbApi {
  const EeKbApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/kb/articles';
  static const _tickets = '/api/v1/ee/team/tickets';

  Future<List<EeKbArticle>> list({String? status, String? serviceId}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: {'status': ?status, 'serviceId': ?serviceId},
      );
      return ((res.data?['articles'] as List<dynamic>?) ?? const [])
          .map((e) => EeKbArticle.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(error);
    }
  }

  Future<EeKbArticle> get(String articleId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$articleId');
      return EeKbArticle.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  Future<EeKbArticle> create({
    required String title,
    required String symptom,
    String? environment,
    String? solution,
    String? serviceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _base,
        data: {
          'title': title,
          'symptom': symptom,
          'environment': ?environment,
          'solution': ?solution,
          'serviceId': ?serviceId,
        },
      );
      return EeKbArticle.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  Future<EeKbArticle> update(
    String articleId,
    Map<String, dynamic> patch,
  ) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '$_base/$articleId',
        data: patch,
      );
      return EeKbArticle.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// The lifecycle door. A refusal travels intact — `KB_SOLUTION_REQUIRED`
  /// and `PERM_DENIED` are the two a person will actually meet, and both say
  /// something worth reading.
  Future<EeKbArticle> setStatus(String articleId, String status) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$articleId/status',
        data: {'status': status},
      );
      return EeKbArticle.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  Future<void> delete(String articleId) async {
    try {
      await _dio.delete<void>('$_base/$articleId');
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// EE-196 — harvest an answer out of a solved request.
  Future<EeKbArticle> fromTicket(
    String ticketId, {
    String? commentId,
    String? title,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_tickets/$ticketId/kb-article',
        data: {'commentId': ?commentId, 'title': ?title},
      );
      return EeKbArticle.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// What this request has already produced.
  Future<List<EeKbArticle>> ofTicket(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_tickets/$ticketId/kb-articles',
      );
      return ((res.data?['articles'] as List<dynamic>?) ?? const [])
          .map((e) => EeKbArticle.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(error);
    }
  }
}
