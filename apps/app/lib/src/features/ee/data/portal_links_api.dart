import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'portal_links_models.dart';

/// The public-link client (EE-106), behind `portal.manage_links`.
///
/// Shaped after `EeSlaAdminApi`: `load()` returns null for 403/404 — "not
/// yours" or "no team here" — because neither is an error to put in front of
/// somebody, and every mutation returns nothing so the controller re-reads.
///
/// [create] is the exception that proves the rule: it is the one call in this
/// client that returns a value, and the value is a credential. Everything else
/// hands back `void` precisely so no other path can start carrying one.
class EePortalLinksApi {
  const EePortalLinksApi(this._dio);
  final Dio _dio;

  static const _links = '/api/v1/ee/team/portal/links';

  Future<EePortalLinksData?> load() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_links);
      return EePortalLinksData.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  /// Mints a link. The returned URL is the only copy that will ever exist.
  Future<EePortalLinkCreated> create({
    required String serviceId,
    String? unitId,
    int? ttlHours,
    Map<String, dynamic>? formSchema,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      _links,
      data: {
        'serviceId': serviceId,
        // Null-aware entries: an absent key means "leave it to the server's
        // default", which is a different request from sending null.
        'unitId': ?unitId,
        'ttlHours': ?ttlHours,
        'formSchema': ?formSchema,
      },
    );
    return EePortalLinkCreated.fromJson(res.data ?? const {});
  });

  Future<void> revoke(String id) =>
      _run(() => _dio.post<void>('$_links/$id/revoke'));

  Future<void> extend(String id, int ttlHours) => _run(
    () => _dio.post<void>('$_links/$id/extend', data: {'ttlHours': ttlHours}),
  );

  Future<void> setEnabled(String id, bool enabled) =>
      _run(() => _dio.patch<void>('$_links/$id', data: {'enabled': enabled}));

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      // The server's sentences reach the screen intact — "Two or more units
      // answer this service. Choose which one this link should reach." is the
      // whole reason that refusal exists, and a generic message would throw
      // away the only actionable thing about it.
      throw asApiException(e);
    }
  }
}
