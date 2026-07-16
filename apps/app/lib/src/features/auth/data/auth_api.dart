import 'package:dio/dio.dart';

import 'models.dart';

/// Raw HTTP calls to `/api/v1/auth/*`. No Authorization header is required by
/// these endpoints, so this client uses the bare (interceptor-free) dio — the
/// auth interceptor itself calls [refresh] and must not recurse.
class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
  }) => _post('/api/v1/auth/register', {
    'email': email,
    'password': password,
    if (displayName != null && displayName.isNotEmpty)
      'displayName': displayName,
  }).then(AuthSession.fromJson);

  Future<AuthSession> login({
    required String email,
    required String password,
  }) => _post('/api/v1/auth/login', {
    'email': email,
    'password': password,
  }).then(AuthSession.fromJson);

  Future<AuthSession> refresh(String refreshToken) => _post(
    '/api/v1/auth/refresh',
    {'refreshToken': refreshToken},
  ).then(AuthSession.fromJson);

  Future<void> logout(String refreshToken, {bool allDevices = false}) async {
    await _post('/api/v1/auth/logout', {
      'refreshToken': refreshToken,
    }, query: allDevices ? {'all': 'true'} : null);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        path,
        data: body,
        queryParameters: query,
      );
      // A 204 (e.g. logout) has no body; dio-web materializes that as the
      // empty STRING '', not null — so a blind `as Map` cast throws a
      // TypeError that isn't an AuthException and escapes the callers'
      // handling (OPH-100). Type-check instead of casting.
      final data = res.data;
      return data is Map<String, dynamic> ? data : const <String, dynamic>{};
    } on DioException catch (e) {
      throw _asAuthException(e);
    }
  }

  AuthException _asAuthException(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['code'] is String) {
      final message = data['message'];
      return AuthException(
        data['code'] as String,
        message is String ? message : 'Request failed',
      );
    }
    if (e.response != null) {
      return AuthException(
        'HTTP_${e.response!.statusCode}',
        'Unexpected server response',
      );
    }
    return const AuthException(
      'NETWORK_ERROR',
      'Could not reach the AllisWell server',
    );
  }
}
