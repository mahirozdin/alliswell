import 'dart:async';

import 'auth_api.dart';
import 'models.dart';
import 'token_storage.dart';

/// Single source of truth for the current session. Owns the API calls and the
/// persisted copy; every change (login, register, rotation, logout, forced
/// sign-out after a failed refresh) is pushed on [sessionChanges].
class AuthRepository {
  AuthRepository({required this._api, required this._storage});

  final AuthApi _api;
  final TokenStorage _storage;

  final _sessionChanges = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;
  Future<String?>? _refreshing;

  AuthSession? get session => _session;
  String? get accessToken => _session?.tokens.accessToken;
  Stream<AuthSession?> get sessionChanges => _sessionChanges.stream;

  /// Loads the persisted session on app start (OPH-025). Expired refresh
  /// tokens are dropped eagerly; a near-expiry one settles on first API call.
  Future<AuthSession?> restore() async {
    var stored = await _storage.read();
    if (stored != null &&
        stored.tokens.refreshTokenExpiresAt.isBefore(DateTime.now())) {
      await _storage.clear();
      stored = null;
    }
    _session = stored;
    return stored;
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final session = await _api.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    await _setSession(session);
    return session;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _api.login(email: email, password: password);
    await _setSession(session);
    return session;
  }

  /// Rotates the refresh token and returns the new access token, or null when
  /// the session is gone (revoked family, expiry, no session). Concurrent
  /// callers share one in-flight rotation — the API treats a re-used refresh
  /// token as theft, so exactly one request may carry it.
  Future<String?> refreshAccessToken() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final run = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = run;
    return run;
  }

  Future<String?> _doRefresh() async {
    final current = _session;
    if (current == null) return null;
    try {
      final next = await _api.refresh(current.tokens.refreshToken);
      await _setSession(next);
      return next.tokens.accessToken;
    } on AuthException {
      // Invalid/reused/expired token: this session is dead — force sign-out.
      await _clearSession();
      return null;
    }
  }

  /// Revokes the server-side session (best effort) and always clears local
  /// state — logout must succeed even when offline.
  Future<void> logout({bool allDevices = false}) async {
    final current = _session;
    if (current != null) {
      try {
        await _api.logout(current.tokens.refreshToken, allDevices: allDevices);
      } on Object {
        // Sign-out is a local-state guarantee; the server revoke is
        // best-effort. Swallow ANYTHING (offline, already-revoked, or an
        // unexpected decode error) so `_clearSession` below always runs —
        // never leave the app holding a session the server already killed
        // (OPH-100).
      }
    }
    await _clearSession();
  }

  Future<void> _setSession(AuthSession session) async {
    _session = session;
    await _storage.save(session);
    _sessionChanges.add(session);
  }

  Future<void> _clearSession() async {
    _session = null;
    await _storage.clear();
    _sessionChanges.add(null);
  }

  void dispose() {
    _sessionChanges.close();
  }
}
