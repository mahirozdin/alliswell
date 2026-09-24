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
  static const _categories = '/api/v1/ee/team/service-categories';

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

  /// EE-228 — a partial edit with exactly the keys given, nulls included.
  ///
  /// The setup screen sends only what changed: an approval rule the admin
  /// did not touch is not in the body, and the server leaves it as it was
  /// (EE-185's merge). When the rule IS touched all three of its parts go
  /// together, because the server validates the rule as a whole.
  Future<void> patch(String serviceId, Map<String, Object?> body) =>
      _run(() async {
        await _dio.patch<Map<String, dynamic>>(
          '$_services/$serviceId',
          data: body,
        );
      });

  /// Files a service on a shelf, or back at the root with null (EE-212).
  Future<void> setCategory(String serviceId, String? categoryId) =>
      _run(() async {
        await _dio.put<Map<String, dynamic>>(
          '$_services/$serviceId/category',
          data: {'categoryId': categoryId},
        );
      });

  /// The shelves. Null on 403/404, like [list]: "not yours" is not "none".
  Future<List<EeServiceCategory>?> categories() => _run(() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_categories);
      return ((res.data?['categories'] as List?) ?? const [])
          .map((c) => EeServiceCategory.fromJson(c as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      rethrow;
    }
  });

  Future<void> createCategory({
    required String name,
    String? parentId,
    String? icon,
  }) => _run(() async {
    await _dio.post<Map<String, dynamic>>(
      _categories,
      data: {'name': name, 'parentId': ?parentId, 'icon': ?icon},
    );
  });

  /// A partial edit; a null value CLEARS (a parent → back to the top, an
  /// icon → none).
  Future<void> updateCategory(String categoryId, Map<String, Object?> body) =>
      _run(() async {
        await _dio.patch<Map<String, dynamic>>(
          '$_categories/$categoryId',
          data: body,
        );
      });

  /// What sat on it falls back to the root — services AND sub-shelves.
  Future<void> deleteCategory(String categoryId) => _run(() async {
    await _dio.delete<Map<String, dynamic>>('$_categories/$categoryId');
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
