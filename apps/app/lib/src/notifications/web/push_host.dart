import 'push_host_stub.dart'
    if (dart.library.js_interop) 'push_host_web.dart'
    as impl;

/// The browser, behind an interface (OPH-313).
///
/// Everything above this line is ordinary Dart that a VM test can drive; below
/// it is `package:web` and a real browser. The split is the same one
/// `sound_store.dart` uses in this very folder, and it exists because the part
/// worth testing — what to do when permission is refused, when the server has
/// no keys, when the browser cannot do any of this — is logic, not interop.
abstract class WebPushHost {
  /// Does this browser have Notification, a service worker AND a push manager?
  /// Safari on iOS has them only for a web app added to the Home Screen.
  bool get isSupported;

  /// Whether this browser makes a sound even when a notification asks not to.
  ///
  /// Firefox ignores `silent` on the Notification API and plays its sound
  /// anyway. That cannot be fixed from here, so the SETTING says it — the one
  /// place the user can still do something about it (turn delivery off, or
  /// mute the site). Learning it at alarm time, from an alarm that made noise
  /// in an open-plan office, is the failure OPH-316 exists to prevent.
  bool get ignoresSilence;

  Future<WebPushPermission> permission();

  /// Must be called from a user gesture — Safari requires it, and asking on
  /// page load is a bad habit everywhere else.
  Future<WebPushPermission> requestPermission();

  Future<WebPushSubscription?> currentSubscription();

  /// @param applicationServerKey the instance's VAPID public key, base64url.
  Future<WebPushSubscription?> subscribe(String applicationServerKey);

  Future<void> unsubscribe();

  /// Notification clicks the service worker forwarded, as the payload JSON
  /// `handleNotificationEvent` already parses. Empty off the web.
  Stream<String> get notificationClicks;

  /// Shows one now. The rehearsal alarm uses it; the real ones come from the
  /// server, through the service worker.
  Future<void> showNotification(
    String title, {
    String? body,
    bool silent = true,
  });
}

enum WebPushPermission {
  granted,
  denied,

  /// Not answered yet — the only state in which asking does anything.
  prompt,
}

/// What a browser hands back when it subscribes: an address and the two keys
/// that encrypt a payload to it (RFC 8291). The server stores all three
/// (OPH-311) and never echoes the keys back.
class WebPushSubscription {
  const WebPushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}

/// The real browser on web; a host that supports nothing everywhere else.
WebPushHost createWebPushHost() => impl.createWebPushHost();
