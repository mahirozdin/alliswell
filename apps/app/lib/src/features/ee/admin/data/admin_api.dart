import 'package:dio/dio.dart';

import '../../../../core/api_exception.dart';
import 'admin_models.dart';

/// REST client for `/api/v1/ee/admin/*` (EE-033).
///
/// It carries the OPERATOR's token, which is a different audience from the
/// one the rest of the app uses (`ee-admin` vs `alliswell-app`). That is why
/// this client is separate rather than a few extra methods on `EeApi`: the two
/// realms must not be able to borrow each other's credentials by sharing a
/// Dio instance and its interceptor.
class AdminApi {
  const AdminApi(this._dio);
  final Dio _dio;

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<AdminSession> signIn({
    required String email,
    required String password,
    required String totpCode,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/admin/auth/login',
        data: {'email': email, 'password': password, 'totpCode': totpCode},
      );
      return _sessionFrom(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<AdminSession> refresh(String refreshToken) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/admin/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return _sessionFrom(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<void> signOut(String refreshToken) async {
    try {
      await _dio.post<void>(
        '/api/v1/ee/admin/auth/logout',
        data: {'refreshToken': refreshToken, 'all': true},
      );
    } on DioException {
      // Signing out is a local truth first: a server that cannot be reached
      // must not keep somebody looking at an operator console.
    }
  }

  AdminSession _sessionFrom(Map<String, dynamic> body) {
    final tokens = body['tokens'] as Map<String, dynamic>? ?? const {};
    final admin = body['admin'] as Map<String, dynamic>? ?? const {};
    return AdminSession(
      email: admin['email'] as String? ?? '',
      accessToken: tokens['accessToken'] as String? ?? '',
      refreshToken: tokens['refreshToken'] as String? ?? '',
      refreshExpiresAt:
          DateTime.tryParse(tokens['refreshTokenExpiresAt'] as String? ?? '') ??
          DateTime.now().add(const Duration(hours: 12)),
    );
  }

  Future<InstanceUsage> usage(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/admin/usage',
        options: _auth(token),
      );
      return InstanceUsage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<List<AdminTeam>> teams(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/admin/teams',
        options: _auth(token),
      );
      return [
        for (final row in (res.data?['items'] as List<dynamic>? ?? const []))
          AdminTeam.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Creating a tenant — the one thing the console promised and could not do.
  ///
  /// `seats` and `packageId` are both optional and mean different things when
  /// omitted: no package named puts the team on whichever one is marked
  /// default, and no seat count leaves the package's own limit in force. A
  /// seat count given HERE is an exception to the package, which is why it is
  /// not defaulted to some number here.
  Future<AdminTeam> createTeam(
    String token, {
    required String name,
    required String slug,
    int? seats,
    String? packageId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/admin/teams',
        options: _auth(token),
        data: <String, dynamic>{
          'name': name,
          'slug': slug,
          'seats': ?seats,
          'packageId': ?packageId,
        },
      );
      return AdminTeam.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<AdminTeam> teamAction(
    String token,
    String teamId,
    String action,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/admin/teams/$teamId/$action',
        options: _auth(token),
      );
      return AdminTeam.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<void> scheduleTeamDeletion(String token, String teamId) async {
    try {
      await _dio.delete<Map<String, dynamic>>(
        '/api/v1/ee/admin/teams/$teamId',
        options: _auth(token),
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<MintedInvite> invite(String token, String teamId, String email) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/admin/teams/$teamId/invites',
        data: {'email': email},
        options: _auth(token),
      );
      final body = res.data ?? const {};
      return MintedInvite(
        email: email,
        token: body['token'] as String? ?? '',
        code: body['code'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<List<AdminPackage>> packages(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/admin/packages',
        options: _auth(token),
      );
      return [
        for (final row in (res.data?['items'] as List<dynamic>? ?? const []))
          AdminPackage.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<List<LimitKeyInfo>> limitKeys(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/admin/limit-keys',
        options: _auth(token),
      );
      return [
        for (final row in (res.data?['items'] as List<dynamic>? ?? const []))
          LimitKeyInfo.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<AdminPackage> savePackage(
    String token, {
    String? id,
    required String name,
    required Map<String, int?> limits,
    bool? isDefault,
  }) async {
    try {
      final data = <String, dynamic>{'name': name, 'limits': limits};
      if (isDefault != null) data['isDefault'] = isDefault;
      final res = id == null
          ? await _dio.post<Map<String, dynamic>>(
              '/api/v1/ee/admin/packages',
              data: data,
              options: _auth(token),
            )
          : await _dio.patch<Map<String, dynamic>>(
              '/api/v1/ee/admin/packages/$id',
              data: data,
              options: _auth(token),
            );
      return AdminPackage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<AdminLeadPage> leads(
    String token, {
    String? status,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/admin/sales/leads',
        queryParameters: {
          'limit': limit,
          'status': ?status,
          // Passed back VERBATIM. It is the previous page's last id, not an
          // offset, so the page it returns is stable while rows arrive.
          'cursor': ?cursor,
        },
        options: _auth(token),
      );
      return AdminLeadPage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<AdminLead> lead(String token, String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/admin/sales/leads/$id',
        options: _auth(token),
      );
      return AdminLead.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Sends only what changed. The server treats a no-op as a no-op and writes
  /// nothing — including no history row — so an unchanged save is free.
  Future<AdminLead> patchLead(
    String token,
    String id, {
    String? status,
    String? notes,
    bool clearNotes = false,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/api/v1/ee/admin/sales/leads/$id',
        data: {
          'status': ?status,
          // `clearNotes` is not the same as "no note given": one asks the
          // server to empty the column, the other says nothing about it. A
          // null-aware element cannot express that difference, so this stays
          // an explicit branch.
          if (clearNotes) 'notes': null else 'notes': ?notes,
        },
        options: _auth(token),
      );
      return AdminLead.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// A data-subject erasure. Idempotent on the server, so a second press is
  /// harmless rather than a second entry in anybody's history.
  Future<void> eraseLead(String token, String id) async {
    try {
      await _dio.delete<void>(
        '/api/v1/ee/admin/sales/leads/$id',
        options: _auth(token),
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
