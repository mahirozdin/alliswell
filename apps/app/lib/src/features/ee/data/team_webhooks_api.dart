import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'team_webhooks_models.dart';

/// The outgoing-endpoint client (EE-175/EE-176), behind `webhooks.manage`.
///
/// Shaped after `EeTeamAiApi`: `load()` returns null for 403/404 — "not yours"
/// or "no team here" — because neither is an error to put in front of
/// somebody.
///
/// TWO METHODS RETURN A SECRET AND NO OTHERS DO, which mirrors the server
/// exactly: create and rotate mint one, nothing can read one back. There is no
/// `get(id)`, and that absence is the client-side half of the same promise.
class EeTeamWebhooksApi {
  const EeTeamWebhooksApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/webhooks';

  Future<EeWebhooksData?> load() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_base);
      return EeWebhooksData.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  Future<EeWebhookMinted> create({
    required String url,
    required List<String> eventClasses,
  }) => _run(
    () => _dio.post<Map<String, dynamic>>(
      _base,
      data: {'url': url, 'eventClasses': eventClasses},
    ),
  );

  Future<EeWebhookMinted> update(
    String id, {
    String? url,
    List<String>? eventClasses,
    bool? enabled,
    bool? rotateSecret,
  }) => _run(
    () => _dio.patch<Map<String, dynamic>>(
      '$_base/$id',
      data: {
        'url': ?url,
        'eventClasses': ?eventClasses,
        'enabled': ?enabled,
        'rotateSecret': ?rotateSecret,
      },
    ),
  );

  Future<void> remove(String id) async {
    try {
      await _dio.delete<void>('$_base/$id');
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Queues a REAL delivery. The screen shows the row it produced rather than
  /// a green tick, because "did my endpoint receive it" is the question and a
  /// tick is not an answer to it.
  Future<String?> sendTest(String id) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('$_base/$id/test');
      return res.data?['deliveryId'] as String?;
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<List<EeWebhookDelivery>> deliveries(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$id/deliveries');
      return ((res.data?['items'] as List<dynamic>?) ?? const [])
          .map((e) => EeWebhookDelivery.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(e);
    }
  }

  Future<EeWebhookMinted> _run(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) async {
    try {
      final res = await call();
      return EeWebhookMinted.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      // The server's sentences reach the screen intact. One of them is the
      // 503 about a missing EE_WEBHOOK_KEY, and replacing it with a generic
      // failure would hide the only actionable thing in it.
      throw asApiException(e);
    }
  }
}
