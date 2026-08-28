import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'services_models.dart';

/// The service catalogue client (EE-082).
///
/// Its own class rather than more methods on [EeUnitsApi], because the
/// audience is different: units answer to a delegated unit manager as well as
/// to an admin, while the catalogue is `services.manage` — team-wide, admins.
///
/// Like the units client, the LIST endpoint is the gate: 403 means "this is
/// not yours to shape" and 404 means "no team at this address". Both come back
/// as **null**, and null is not the same as `[]` — a fresh team legitimately
/// has no services yet and must still see the screen, because that is where
/// the first one is created.
class EeServicesApi {
  const EeServicesApi(this._dio);
  final Dio _dio;

  static const _services = '/api/v1/ee/team/services';

  Future<List<EeService>?> list() => _run(() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_services);
      return ((res.data?['services'] as List?) ?? const [])
          .map((s) => EeService.fromJson(s as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      rethrow;
    }
  });

  Future<void> create({
    required String name,
    String? description,
    Map<String, dynamic>? formSchema,
  }) => _run(() async {
    await _dio.post<Map<String, dynamic>>(
      _services,
      data: {
        'name': name,
        // `key: ?value` is the null-aware ELEMENT: the entry is omitted when
        // the value is null, which is what an absent optional field means here.
        'description': ?description,
        'formSchema': ?formSchema,
      },
    );
  });

  /// A partial edit. `clear` names the keys to set to null, because "absent"
  /// and "set to null" mean different things on the wire and JSON alone cannot
  /// tell them apart — the server distinguishes them too (clearing a
  /// description is a real act, not a missing field).
  Future<void> update(
    String serviceId, {
    String? name,
    String? description,
    Map<String, dynamic>? formSchema,
    Set<String> clear = const {},
  }) => _run(() async {
    await _dio.patch<Map<String, dynamic>>(
      '$_services/$serviceId',
      data: {
        'name': ?name,
        'description': ?description,
        'formSchema': ?formSchema,
        for (final key in clear) key: null,
      },
    );
  });

  Future<void> setArchived(String serviceId, {required bool archived}) =>
      _run(() async {
        await _dio.post<Map<String, dynamic>>(
          '$_services/$serviceId/${archived ? 'archive' : 'unarchive'}',
        );
      });

  /// The whole routing set in one call, matching the server's PUT: the act is
  /// "these units answer this service", and splitting it into add/remove would
  /// make one decision a sequence that can half-fail.
  Future<void> setUnits(String serviceId, List<String> unitIds) =>
      _run(() async {
        await _dio.put<Map<String, dynamic>>(
          '$_services/$serviceId/units',
          data: {'unitIds': unitIds},
        );
      });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
