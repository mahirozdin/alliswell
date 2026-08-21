import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'units_models.dart';

/// The units client (EE-057).
///
/// Its own class rather than more methods on [EeTeamAdminApi], because the
/// audience is different: the team-admin surface answers only to admins, and
/// this one also answers to a delegated unit manager who is an ordinary team
/// member everywhere else.
///
/// The LIST endpoint is the gate. It returns the units the caller may act on —
/// all of them for an admin, the delegated ones for a manager — and 403 for
/// somebody with no business here. So the app never has to model "may I?"
/// itself: it asks, and an empty hand is the answer.
class EeUnitsApi {
  const EeUnitsApi(this._dio);
  final Dio _dio;

  static const _units = '/api/v1/ee/team/units';

  /// The units this caller may act on, or **null** when they may act on none.
  ///
  /// Null rather than an exception, and rather than an empty list: an admin
  /// with no units yet legitimately gets `[]` and must still see the screen
  /// (that is where the first unit gets opened). The two answers mean
  /// different things and the caller draws different screens for them.
  Future<List<EeUnit>?> list() => _run(() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_units);
      return ((res.data?['units'] as List?) ?? const [])
          .map((u) => EeUnit.fromJson(u as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 403 — nothing to manage. 404 — no team at this address at all.
      if (code == 403 || code == 404) return null;
      rethrow;
    }
  });

  Future<List<EeUnitMember>> members(String unitId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('$_units/$unitId/members');
    return ((res.data?['members'] as List?) ?? const [])
        .map((m) => EeUnitMember.fromJson(m as Map<String, dynamic>))
        .toList();
  });

  /// Who could still join this unit — active team members not already in it.
  /// Scoped to a unit the caller manages: a delegated manager cannot read the
  /// team roster, so without this the "add someone" picker would be empty.
  Future<List<EeUnitMember>> candidates(String unitId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_units/$unitId/candidates',
    );
    return ((res.data?['candidates'] as List?) ?? const [])
        .map((m) => EeUnitMember.fromJson(m as Map<String, dynamic>))
        .toList();
  });

  Future<void> create(String name) => _run(() async {
    await _dio.post<Map<String, dynamic>>(_units, data: {'name': name});
  });

  Future<void> rename(String unitId, String name) => _run(() async {
    await _dio.patch<Map<String, dynamic>>(
      '$_units/$unitId',
      data: {'name': name},
    );
  });

  Future<void> setArchived(String unitId, {required bool archived}) =>
      _run(() async {
        await _dio.post<Map<String, dynamic>>(
          '$_units/$unitId/${archived ? 'archive' : 'unarchive'}',
        );
      });

  Future<void> addMember(String unitId, String userId) => _run(() async {
    await _dio.post<Map<String, dynamic>>(
      '$_units/$unitId/members',
      data: {'userId': userId},
    );
  });

  Future<void> removeMember(String unitId, String userId) => _run(() async {
    await _dio.delete<void>('$_units/$unitId/members/$userId');
  });

  /// Appointing a manager is TEAM authority — a delegated manager calling this
  /// gets a 403 from the server, which is why the screen only offers it when
  /// the caller could actually carry it out.
  Future<void> setMemberRole(String unitId, String userId, String role) =>
      _run(() async {
        await _dio.patch<Map<String, dynamic>>(
          '$_units/$unitId/members/$userId',
          data: {'role': role},
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
