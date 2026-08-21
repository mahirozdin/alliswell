import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'team_admin_models.dart';

/// The team-admin client (EE-042): team info, the management roster, and
/// invitations.
///
/// Every endpoint here answers 404 to somebody who is not in the team and 403
/// to a member who is not an admin — so the app never has to guess what to
/// show. It asks, and the server's answer is the permission model.
class EeTeamAdminApi {
  const EeTeamAdminApi(this._dio);
  final Dio _dio;

  static const _team = '/api/v1/ee/team';

  /// The team, and where the caller stands in it. Answers null when this
  /// server serves no team at this address — which is not an error, just a
  /// plain instance.
  Future<EeTeamInfo?> info() => _run(() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_team);
      return EeTeamInfo.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  });

  Future<EeTeamRoster> members() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('$_team/members');
    return EeTeamRoster.fromJson(res.data ?? const {});
  });

  Future<void> setRole({
    required String userId,
    required String role,
    String? customRoleId,
    bool clearCustomRole = false,
  }) => _run(() async {
    await _dio.patch<Map<String, dynamic>>(
      '$_team/members/$userId/role',
      data: {
        'role': role,
        // Absent leaves it alone, null CLEARS it — so the two intents need
        // two spellings, and a bool is the only honest way to say "null".
        'customRoleId': ?customRoleId,
        if (clearCustomRole) 'customRoleId': null,
      },
    );
  });

  // ── Roles (EE-053) ───────────────────────────────────────────────────────

  Future<List<EeRole>> roles() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('$_team/roles');
    return ((res.data?['roles'] as List?) ?? const [])
        .map((r) => EeRole.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  /// The full vocabulary — what a grant matrix draws its rows from.
  Future<List<EePermissionDef>> catalogue() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/ee/permissions');
    return ((res.data?['permissions'] as List?) ?? const [])
        .map((p) => EePermissionDef.fromJson(p as Map<String, dynamic>))
        .toList();
  });

  Future<void> createRole({
    required String name,
    required String anchor,
    required List<String> grants,
  }) => _run(() async {
    await _dio.post<Map<String, dynamic>>(
      '$_team/roles',
      data: {'name': name, 'anchor': anchor, 'grants': grants},
    );
  });

  /// Full sets, not deltas: the server translates. A client that computed
  /// departures from the defaults would be reimplementing a rule it cannot
  /// see (PERMISSIONS.md, EE-048).
  Future<void> updateRole({
    required String roleKey,
    String? name,
    List<String>? grants,
  }) => _run(() async {
    await _dio.patch<Map<String, dynamic>>(
      '$_team/roles/$roleKey',
      data: {'name': ?name, 'grants': ?grants},
    );
  });

  Future<void> deleteRole(String roleKey) => _run(() async {
    await _dio.delete<Map<String, dynamic>>('$_team/roles/$roleKey');
  });

  Future<void> deactivate(String userId) => _run(() async {
    await _dio.post<Map<String, dynamic>>('$_team/members/$userId/deactivate');
  });

  Future<void> reactivate(String userId) => _run(() async {
    await _dio.post<Map<String, dynamic>>('$_team/members/$userId/reactivate');
  });

  Future<void> remove(String userId) => _run(() async {
    await _dio.delete<Map<String, dynamic>>('$_team/members/$userId');
  });

  Future<List<EeInvite>> invites() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('$_team/invites');
    return ((res.data?['items'] as List?) ?? const [])
        .map((e) => EeInvite.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  });

  /// Mints one. The response is the only time the link and the code exist
  /// outside somebody's memory — there is no endpoint that reads them back.
  Future<EeMintedInvite> invite({
    required String email,
    String role = 'member',
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_team/invites',
      data: {'email': email, 'role': role},
    );
    return EeMintedInvite.fromJson(res.data ?? const {});
  });

  Future<void> revokeInvite(String inviteId) => _run(() async {
    await _dio.delete<Map<String, dynamic>>('$_team/invites/$inviteId');
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
