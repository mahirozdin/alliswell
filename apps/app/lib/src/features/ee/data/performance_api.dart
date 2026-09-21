import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'performance_models.dart';

/// The performance panel's client (EE-205).
///
/// Online-only for `EeSlaDashboardApi`'s reason, restated because it is easy
/// to think a per-person breakdown could be computed on the device: it cannot.
/// A phone holds its own units' rows, so an agent's figures drawn locally
/// would be that agent's work *as one device happens to have synced it* —
/// authoritative-looking and wrong, and wrong about a person, which is the
/// worst place for this product to be approximately right.
class EePerformanceApi {
  const EePerformanceApi(this._dio);
  final Dio _dio;

  static const _path = '/api/v1/ee/team/tickets/performance';

  /// Null means "not yours" or "no team here" — not an error to be shown.
  Future<EePerformance?> load({int days = 30}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: {'days': days},
      );
      final data = res.data;
      return data == null ? null : EePerformance.fromJson(data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }
}
