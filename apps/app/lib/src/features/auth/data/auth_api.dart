import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'models.dart';

/// What `GET /auth/providers` answers: the social sign-ins a server has a
/// client for (OPH-392).
typedef ServerSignInProviders = ({bool google, bool apple});

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

  /// [totpCode] is the authenticator or recovery code, sent only on the retry
  /// after the server answered `AUTH_MFA_REQUIRED` (OPH-283, OPH-381).
  Future<AuthSession> login({
    required String email,
    required String password,
    String? totpCode,
  }) => _post('/api/v1/auth/login', {
    'email': email,
    'password': password,
    'totpCode': ?totpCode,
  }).then(AuthSession.fromJson);

  /// Exchange a Google/Apple ID token for an AllisWell session (ADR-0026).
  ///
  /// The provider's token never becomes the session: the server verifies it,
  /// decides which account it belongs to and mints our own tokens. That is what
  /// keeps a self-hosted deployment — which has no Firebase and may have no
  /// Google client at all — working exactly like this one.
  ///
  /// The provider's token is the first factor only: an account with an
  /// authenticator answers `AUTH_MFA_REQUIRED`, and the SAME [idToken] comes
  /// back with [totpCode] — the native provider sheet is not run twice
  /// (OPH-381).
  Future<AuthSession> oauth({
    required String provider,
    required String idToken,
    String? totpCode,
  }) => _post('/api/v1/auth/oauth', {
    'provider': provider,
    'idToken': idToken,
    'totpCode': ?totpCode,
  }).then(AuthSession.fromJson);

  Future<AuthSession> refresh(String refreshToken) => _post(
    '/api/v1/auth/refresh',
    {'refreshToken': refreshToken},
  ).then(AuthSession.fromJson);

  /// Which social sign-ins this server can complete (OPH-392, E-23). A server
  /// older than the question answers 404 — the caller treats any failure as
  /// "unknown", not as "none".
  Future<ServerSignInProviders> signInProviders() async {
    try {
      final res = await _dio.get<dynamic>('/api/v1/auth/providers');
      final data = res.data;
      final map = data is Map<String, dynamic> ? data : const {};
      return (google: map['google'] == true, apple: map['apple'] == true);
    } on DioException catch (e) {
      throw _asAuthException(e);
    }
  }

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

  /// One mapping for every API failure (`asApiException`), so a codeless
  /// 429 carries its wait here too (OPH-357, UI-AUDIT #24).
  AuthException _asAuthException(DioException e) {
    final api = asApiException(e);
    return AuthException(
      api.code,
      api.message,
      statusCode: api.statusCode,
      retryAfter: api.retryAfter,
    );
  }
}
