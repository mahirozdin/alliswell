import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'models.dart';

/// What `GET /auth/providers` answers: the social sign-ins a server has a
/// client for (OPH-392).
typedef ServerSignInProviders = ({bool google, bool apple});

/// How a server hands out password-reset links (OPH-406).
enum PasswordResetDelivery {
  /// By e-mail, to the address — if it has an account there.
  email,

  /// The server sends no mail: its operator issues the link by command.
  admin,
}

/// Raw HTTP calls to `/api/v1/auth/*`. No Authorization header is required by
/// these endpoints, so this client uses the bare (interceptor-free) dio — the
/// auth interceptor itself calls [refresh] and must not recurse.
///
/// Every door that starts or rotates a session family takes an optional
/// `deviceId` (OPH-447, #48): this install's notification-device id, which the
/// server binds the family to so "remove this device" elsewhere can revoke it.
/// The field never costs a sign-in — see [_postNamingDevice].
class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
    String? deviceId,
  }) => _postNamingDevice('/api/v1/auth/register', {
    'email': email,
    'password': password,
    if (displayName != null && displayName.isNotEmpty)
      'displayName': displayName,
  }, deviceId).then(AuthSession.fromJson);

  /// [totpCode] is the authenticator or recovery code, sent only on the retry
  /// after the server answered `AUTH_MFA_REQUIRED` (OPH-283, OPH-381).
  Future<AuthSession> login({
    required String email,
    required String password,
    String? totpCode,
    String? deviceId,
  }) => _postNamingDevice('/api/v1/auth/login', {
    'email': email,
    'password': password,
    'totpCode': ?totpCode,
  }, deviceId).then(AuthSession.fromJson);

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
    String? deviceId,
  }) => _postNamingDevice('/api/v1/auth/oauth', {
    'provider': provider,
    'idToken': idToken,
    'totpCode': ?totpCode,
  }, deviceId).then(AuthSession.fromJson);

  /// The server binds an unbound family to [deviceId] on a rotation and keeps
  /// a bound family's device as it is (OPH-434).
  Future<AuthSession> refresh(String refreshToken, {String? deviceId}) =>
      _postNamingDevice('/api/v1/auth/refresh', {
        'refreshToken': refreshToken,
      }, deviceId).then(AuthSession.fromJson);

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

  /// Asks for a reset link (OPH-406, ADR-0064). The answer is the same for
  /// every address — whether an account exists is never said — and describes
  /// only the server: [PasswordResetDelivery.email] when it mails links,
  /// [PasswordResetDelivery.admin] when its operator has to issue one.
  Future<PasswordResetDelivery> forgotPassword({
    required String email,
    String? locale,
  }) async {
    final data = await _post('/api/v1/auth/password/forgot', {
      'email': email,
      if (locale == 'tr' || locale == 'en') 'locale': locale,
    });
    return data['delivery'] == 'admin'
        ? PasswordResetDelivery.admin
        : PasswordResetDelivery.email;
  }

  /// Spends a reset link: sets [password] and ends every session of the
  /// account. A spent, expired or unknown link is `AUTH_RESET_INVALID`.
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await _post('/api/v1/auth/password/reset', {
      'token': token,
      'password': password,
    });
  }

  Future<void> logout(String refreshToken, {bool allDevices = false}) async {
    await _post('/api/v1/auth/logout', {
      'refreshToken': refreshToken,
    }, query: allDevices ? {'all': 'true'} : null);
  }

  /// [body] plus `deviceId` when there is one — and, when the server refuses
  /// the body's SHAPE, the same call once more without it.
  ///
  /// A server from before OPH-434 validates auth bodies with
  /// `additionalProperties: false`, so the unknown field is Fastify's 400
  /// `FST_ERR_VALIDATION`. Validation runs before the handler, so nothing was
  /// spent — not a refresh token, not a TOTP code — and repeating the call is
  /// safe. Any other answer is the real one and is passed on as it is.
  Future<Map<String, dynamic>> _postNamingDevice(
    String path,
    Map<String, dynamic> body,
    String? deviceId,
  ) async {
    if (deviceId == null) return _post(path, body);
    try {
      return await _post(path, {...body, 'deviceId': deviceId});
    } on AuthException catch (e) {
      if (!_isShapeRefusal(e)) rethrow;
      return _post(path, body);
    }
  }

  static bool _isShapeRefusal(AuthException e) =>
      e.statusCode == 400 &&
      (e.code == 'FST_ERR_VALIDATION' || e.code == 'HTTP_400');

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
