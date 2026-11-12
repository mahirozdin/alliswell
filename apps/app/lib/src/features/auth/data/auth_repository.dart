import 'dart:async';

import 'auth_api.dart';
import 'models.dart';
import 'token_storage.dart';

/// Single source of truth for the current session. Owns the API calls and the
/// persisted copy; every change (login, register, rotation, logout, forced
/// sign-out after a failed refresh) is pushed on [sessionChanges].
class AuthRepository {
  AuthRepository({
    required this._api,
    required this._storage,
    this._onSessionUser,
    this._deviceId,
    this._onSessionRevoked,
  });

  final AuthApi _api;
  final TokenStorage _storage;

  /// Runs when a session is about to start for a person — a sign-in for
  /// somebody other than the current session's user, or a session restored
  /// at app start ([restored]) — and BEFORE it is exposed, so nothing can read
  /// local data as theirs first. The replica's owner check lives here
  /// (OPH-355, `LocalDataGuard.claimFor`). Token rotations do not call it.
  final Future<void> Function(String userId, {required bool restored})?
  _onSessionUser;

  /// This install's notification-device id, sent with every sign-in and
  /// refresh so the server can bind the session family to it (OPH-447, #48).
  /// `null` — or a read that fails — sends nothing: the field is optional and
  /// must never cost a sign-in.
  final Future<String?> Function()? _deviceId;

  /// Runs once the session has been dropped because the server refused the
  /// refresh token as revoked — the device was removed elsewhere, a password
  /// changed, or the family was burned (OPH-447). Not awaited: a
  /// request is waiting on this refresh, and the local sign-out it starts
  /// (halting that same request's sync round among other things) must not
  /// wait on it in turn.
  final void Function()? _onSessionRevoked;

  /// The refresh answers that mean "this session family was revoked" —
  /// unlike a network error or a rate limit, which say nothing about it.
  ///
  /// Only `AUTH_REFRESH_REUSED`: the server never deletes a refresh token, it
  /// marks a revoked family `revoked_at`, so a removed device, a password
  /// change or a burned family always answers with it.
  /// `AUTH_INVALID_REFRESH_TOKEN` is also what a token that merely expired
  /// gets (and an unknown one), which proves nothing about removal — that
  /// session ends as before and its offline edits wait for the next sign-in.
  static const _revokedCodes = {'AUTH_REFRESH_REUSED'};

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
    if (stored != null) {
      await _onSessionUser?.call(stored.user.id, restored: true);
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
      deviceId: await _readDeviceId(),
    );
    await _setSession(session);
    return session;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    String? totpCode,
  }) async {
    final session = await _api.login(
      email: email,
      password: password,
      totpCode: totpCode,
      deviceId: await _readDeviceId(),
    );
    await _setSession(session);
    return session;
  }

  /// Sign in through Google or Apple. [idToken] comes from [SocialSignIn].
  Future<AuthSession> signInWithProvider({
    required String provider,
    required String idToken,
    String? totpCode,
  }) async {
    final session = await _api.oauth(
      provider: provider,
      idToken: idToken,
      totpCode: totpCode,
      deviceId: await _readDeviceId(),
    );
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
    final deviceId = await _readDeviceId();
    try {
      final next = await _api.refresh(
        current.tokens.refreshToken,
        deviceId: deviceId,
      );
      await _setSession(next);
      return next.tokens.accessToken;
    } on AuthException catch (e) {
      // Invalid/reused/expired token: this session is dead — force sign-out.
      await _clearSession();
      // Revoked, not merely unreachable: what this person left here goes the
      // way an explicit sign-out takes it (OPH-447).
      if (_revokedCodes.contains(e.code)) _onSessionRevoked?.call();
      return null;
    }
  }

  Future<String?> _readDeviceId() async {
    final read = _deviceId;
    if (read == null) return null;
    try {
      return await read();
    } on Object {
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
    if (_session?.user.id != session.user.id) {
      await _onSessionUser?.call(session.user.id, restored: false);
    }
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
