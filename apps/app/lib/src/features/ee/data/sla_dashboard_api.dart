import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'sla_dashboard_models.dart';

/// The SLA dashboard client (EE-098).
///
/// One GET, and the answer is computed entirely on the server — from the
/// pre-aggregated counters, scoped to the workspaces the caller is actually
/// in. There is no local equivalent and deliberately so: a compliance figure
/// drawn from one device's replica would be a percentage of whatever that
/// phone happened to have synced, which is the kind of number that looks
/// authoritative and is not.
class EeSlaDashboardApi {
  const EeSlaDashboardApi(this._dio);
  final Dio _dio;

  static const _path = '/api/v1/ee/team/sla/dashboard';

  /// Null means "not yours" or "no team here" — the same shape the catalogue
  /// client uses, and for the same reason: it is not an error to be shown.
  Future<EeSlaDashboard?> load() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_path);
      final data = res.data;
      return data == null ? null : EeSlaDashboard.fromJson(data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }
}
