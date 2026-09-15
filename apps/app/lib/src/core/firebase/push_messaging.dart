import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../features/devices/device_registry.dart';
import '../../notifications/platform_matrix.dart';

import 'firebase_bootstrap.dart';

/// The FCM registration token, and nothing else (OPH-319, ADR-0038 §6).
///
/// ── IT IS OPTIONAL THE SAME WAY EVERY OTHER FIREBASE PIECE IS ─────────────
///
/// `google-services.json` and `GoogleService-Info.plist` are gitignored
/// (ADR-0025), so on a fresh clone Firebase never initialises, [AwFirebase
/// .isConfigured] stays false, and this asks the plugin for nothing at all.
/// No token, no registration, no push — and the app behaves exactly as it did
/// before any of this existed, which is a thing a test can assert rather than
/// a promise.
///
/// ── AND IT IS NEVER USED ON THE WEB ───────────────────────────────────────
///
/// A browser is reached with VAPID (`web/push_host_web.dart`), and ADR-0025 §5
/// keeps "web has no implicit config" true. Asking `firebase_messaging` for a
/// token on web would want a second set of credentials passed in at build
/// time for a channel the browser already has.
///
/// ── WHY IT IS A CLASS AND NOT A CALL ──────────────────────────────────────
///
/// A token is not a value you fetch once: the SDK rotates it (a restore to a
/// new device, an app data clear, a key change), and a rotated token that
/// nobody wrote down is a device the server keeps sending to and never
/// reaches. So the stream is the point, and the first token is just its
/// earliest value.
class AwPushMessaging {
  /// Everything is injectable so a VM test can drive both branches. `kIsWeb`
  /// is a const `false` there and `AwFirebase.isConfigured` cannot be made
  /// true without a real project, so without these seams the two states that
  /// matter most — a browser, and a fresh clone — would be unreachable code.
  AwPushMessaging({
    FirebaseMessaging? plugin,
    bool? isWeb,
    bool Function()? isConfigured,
    String? platformId,
  }) : _messaging = plugin,
       _isWeb = isWeb ?? kIsWeb,
       _isConfigured = isConfigured ?? _firebaseConfigured,
       _platformId =
           platformId ??
           awDevicePlatform(isWeb: kIsWeb, target: defaultTargetPlatform);

  static bool _firebaseConfigured() => AwFirebase.isConfigured;

  final FirebaseMessaging? _messaging;
  final bool _isWeb;
  final bool Function() _isConfigured;
  final String? _platformId;

  /// Whether this build can produce a token at all. False on web, on any build
  /// without Firebase credentials, and on a platform the plugin does not
  /// implement — all three supported states.
  ///
  /// The platform half is read from [kNotificationMatrix] (OPH-317) rather
  /// than listed here, so the table in `docs/NOTIFICATIONS.md` §3 is not a
  /// description of this line: it is the same declaration this line obeys.
  bool get isAvailable =>
      !_isWeb && _isConfigured() && platformCarriesFcmToken(_platformId);

  FirebaseMessaging get _plugin => _messaging ?? FirebaseMessaging.instance;

  /// This install's token, or null when there is none to have. Never throws:
  /// a platform that has no messaging (a desktop build, a device with no Play
  /// services) is not an error, it is a device we reach some other way.
  Future<String?> token() async {
    if (!isAvailable) return null;
    try {
      return await _plugin.getToken();
    } on Object catch (error) {
      debugPrint('AllisWell: no push token ($error)');
      return null;
    }
  }

  /// Every later token for this install. Empty when unavailable, so a caller
  /// needs no guard of its own.
  Stream<String> get tokenRefreshes {
    if (!isAvailable) return const Stream<String>.empty();
    try {
      return _plugin.onTokenRefresh;
    } on Object catch (error) {
      debugPrint('AllisWell: token refreshes unavailable ($error)');
      return const Stream<String>.empty();
    }
  }

  /// Forget this install's token — called on sign-out, BEFORE the session that
  /// could delete the row is gone. Deleting it here means a signed-out phone
  /// stops being reachable even if the row outlives the request.
  Future<void> forgetToken() async {
    if (!isAvailable) return;
    try {
      await _plugin.deleteToken();
    } on Object catch (error) {
      // Best-effort, like the rest of sign-out: the local guarantee is that
      // this device stops using the token, and it does either way.
      debugPrint('AllisWell: could not delete the push token ($error)');
    }
  }
}
