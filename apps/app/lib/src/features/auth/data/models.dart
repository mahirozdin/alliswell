/// Auth domain models mirroring the API contracts (apps/api routes/auth.js).
library;

class AuthUser {
  const AuthUser({required this.id, required this.email, this.displayName});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
  );

  final String id;
  final String email;
  final String? displayName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
  };
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessTokenExpiresInSec,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['accessToken'] as String,
    accessTokenExpiresInSec: json['accessTokenExpiresInSec'] as int,
    refreshToken: json['refreshToken'] as String,
    refreshTokenExpiresAt: DateTime.parse(
      json['refreshTokenExpiresAt'] as String,
    ),
  );

  final String accessToken;
  final int accessTokenExpiresInSec;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'accessTokenExpiresInSec': accessTokenExpiresInSec,
    'refreshToken': refreshToken,
    'refreshTokenExpiresAt': refreshTokenExpiresAt.toIso8601String(),
  };
}

/// A signed-in identity: the user plus their current token pair.
class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    tokens: AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>),
  );

  final AuthUser user;
  final AuthTokens tokens;

  AuthSession withTokens(AuthTokens next) =>
      AuthSession(user: user, tokens: next);

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'tokens': tokens.toJson(),
  };
}

/// Stable machine-readable failure from the API (`code` field) or transport.
class AuthException implements Exception {
  const AuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AuthException($code): $message';
}
