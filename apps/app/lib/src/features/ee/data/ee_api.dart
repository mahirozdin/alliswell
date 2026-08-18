import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'ee_models.dart';

/// REST client for instance entitlement discovery (EE-008). One endpoint,
/// registered unconditionally server-side — a CE instance answers an empty
/// 200. A 404 only means the server predates the endpoint, which is the same
/// honest truth: nothing enabled here.
class EeApi {
  const EeApi(this._dio);
  final Dio _dio;

  Future<EeStatus> status() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/v1/ee/status');
      return EeStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return EeStatus.none;
      throw asApiException(e);
    }
  }
}
