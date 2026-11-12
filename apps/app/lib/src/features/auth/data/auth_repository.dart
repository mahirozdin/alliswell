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
  /// changed, or the family was burned (OPH-447) — with the revoked session's
  /// user id. Not awaited by the refresh: a request is waiting on it, and the
  /// local sign-out this starts (halting that same request's sync round among
  /// other things) must not wait on it in turn. The next session to start
  /// waits for it instead ([_settleRevocation]), so the cleanup only ever
  /// touches what the revoked session left.
  ///
  /// [replaced] — a sign-in was already under way when the refusal came, and
  /// its session is about to replace the revoked one. That sign-in may have
  /// named this install by its client id already, and its own owner check
  /// (`claimFor`) decides the replica — which carries that id over — so the
  /// cleanup leaves the replica to it. It runs inside the sign-in, before the
  /// new session is exposed, never after (signin-binds-discarded-client-id,
  /// revocation-cleanup-crosses-sessions).
  final Future<void> Function(String userId, {required bool replaced})?
  _onSessionRevoked;

  /// The cleanup [_onSessionRevoked] started and has not finished, if any.
  Future<void>? _revocationCleanup;

  /// Sign-ins between their start and their end, whatever the outcome.
  int _signIns = 0;

  /// The user of a session revoked while a sign-in was under way: cleaned up
  /// by that sign-in before it exposes its session, or — when it fails — as
  /// soon as no sign-in is left ([_releaseDeferredRevocation]).
  String? _deferredRevocation;

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
      await _settleRevocation();
      await _onSessionUser?.call(stored.user.id, restored: true);
    }
    _session = stored;
    return stored;
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
  }) => _signIn(
    (deviceId) => _api.register(
      email: email,
      password: password,
      displayName: displayName,
      deviceId: deviceId,
    ),
  );

  Future<AuthSession> login({
    required String email,
    required String password,
    String? totpCode,
  }) => _signIn(
    (deviceId) => _api.login(
      email: email,
      password: password,
      totpCode: totpCode,
      deviceId: deviceId,
    ),
  );

  /// Sign in through Google or Apple. [idToken] comes from [SocialSignIn].
  Future<AuthSession> signInWithProvider({
    required String provider,
    required String idToken,
    String? totpCode,
  }) => _signIn(
    (deviceId) => _api.oauth(
      provider: provider,
      idToken: idToken,
      totpCode: totpCode,
      deviceId: deviceId,
    ),
  );

  /// One sign-in, from naming the device to exposing the session.
  ///
  /// A revoked session's cleanup discards the replica and with it this
  /// install's client id, so the id is read only once a cleanup already
  /// running is over: read before, the sign-in would bind its family to an id
  /// the cleanup then throws away, and nothing would ever list it
  /// (signin-binds-discarded-client-id). A refusal that comes while this is
  /// under way defers its cleanup to [_setSession] instead of starting it.
  Future<AuthSession> _signIn(
    Future<AuthSession> Function(String? deviceId) request,
  ) async {
    _signIns++;
    try {
      await _settleRevocation();
      final session = await request(await _readDeviceId());
      await _setSession(session);
      return session;
    } finally {
      _signIns--;
      _releaseDeferredRevocation();
    }
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
      // A sign-in or sign-out that landed while this was on the wire owns
      // the session now: the rotation of the one it replaced must not bring
      // that one back.
      if (!identical(_session, current)) return null;
      await _setSession(next);
      return next.tokens.accessToken;
    } on AuthException catch (e) {
      // No answer about the token — the bounded auth client timed out, the
      // network dropped, the server was down or busy: the session stays, the
      // caller sees its 401 and retries later (refresh-timeout-signout).
      if (_isUnanswered(e)) return null;
      // The refusal is about [current]. A session that replaced it meanwhile
      // is not this refusal's to end, nor its leftovers this cleanup's
      // (revocation-cleanup-crosses-sessions).
      if (!identical(_session, current)) return null;
      // Invalid/reused/expired token: this session is dead — force sign-out.
      // Cleared synchronously up to its first await, and the cleanup is
      // registered before anything else can run: a sign-in that starts now
      // finds it and waits for it.
      final cleared = _clearSession();
      // Revoked, not merely unreachable: what this person left here goes the
      // way an explicit sign-out takes it (OPH-447).
      final cleanup = _onSessionRevoked;
      if (cleanup != null && _revokedCodes.contains(e.code)) {
        if (_signIns > 0) {
          // A sign-in is under way: started now, the cleanup could outlast
          // it and halt, cancel and wipe what the new session already owns.
          // That sign-in runs it before it exposes its session.
          _deferredRevocation = current.user.id;
        } else {
          _trackRevocation(
            cleared.then((_) => cleanup(current.user.id, replaced: false)),
          );
        }
      }
      await cleared;
      return null;
    }
  }

  /// A refresh failure that says nothing about the refresh token: no answer
  /// at all (`NETWORK_ERROR`, a timeout included), a server error, a request
  /// timeout or a rate limit. Only the server's refusal of the token ends the
  /// session.
  static bool _isUnanswered(AuthException e) {
    final status = e.statusCode;
    return status == null || status == 408 || status == 429 || status >= 500;
  }

  void _trackRevocation(Future<void> cleanup) {
    late final Future<void> tracked;
    tracked = cleanup
        .catchError((Object _) {
          // Best effort, like a sign-out's own steps; never a reason to keep
          // the next session waiting forever.
        })
        .whenComplete(() {
          if (identical(_revocationCleanup, tracked)) _revocationCleanup = null;
        });
    _revocationCleanup = tracked;
  }

  /// Waits for a revoked session's cleanup before another session starts.
  Future<void> _settleRevocation() async {
    for (
      var pending = _revocationCleanup;
      pending != null;
      pending = _revocationCleanup
    ) {
      await pending;
    }
  }

  /// Runs, inside the sign-in that is replacing it, the cleanup of a session
  /// revoked while that sign-in was under way. Callers check
  /// [_deferredRevocation] synchronously first: even an empty `await` yields,
  /// and a refusal could slip in between it and the session's exposure.
  Future<void> _runDeferredRevocation() async {
    final userId = _deferredRevocation;
    final cleanup = _onSessionRevoked;
    _deferredRevocation = null;
    if (userId == null || cleanup == null) return;
    _trackRevocation(cleanup(userId, replaced: true));
    await _settleRevocation();
  }

  /// The last sign-in ended without taking over a deferred revocation — it
  /// failed — so the revoked session's cleanup runs as it would have.
  void _releaseDeferredRevocation() {
    final userId = _deferredRevocation;
    final cleanup = _onSessionRevoked;
    if (_signIns > 0 || userId == null || cleanup == null) return;
    _deferredRevocation = null;
    // A session that is current now was never the revoked one.
    if (_session != null) return;
    _trackRevocation(cleanup(userId, replaced: false));
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
      await _settleRevocation();
      while (_deferredRevocation != null) {
        await _runDeferredRevocation();
      }
      await _onSessionUser?.call(session.user.id, restored: false);
    }
    // A refusal that came during the hook: its cleanup finishes before this
    // session is exposed, so it can never reach this session's engines or
    // alarms (revocation-cleanup-crosses-sessions).
    while (_deferredRevocation != null) {
      await _runDeferredRevocation();
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
