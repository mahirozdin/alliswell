import 'package:flutter/foundation.dart' show TargetPlatform;

/// Which gateway a platform's notifications go through (OPH-317).
///
/// A named decision rather than an inline `kIsWeb` check, so the same question
/// can be asked by a test and by the documentation gate. The provider calls
/// [gatewayKindFor]; nothing else decides this.
enum NotificationGatewayKind {
  /// `flutter_local_notifications` — the OS schedules, the device is the clock.
  local,

  /// The browser: permission, a push subscription, and a service worker that
  /// shows what the server sends, because a closed tab schedules nothing.
  web,
}

NotificationGatewayKind gatewayKindFor({required bool isWeb}) =>
    isWeb ? NotificationGatewayKind.web : NotificationGatewayKind.local;

/// What one platform can actually do about a reminder (OPH-317).
///
/// ── WHY THIS EXISTS ───────────────────────────────────────────────────────
///
/// `docs/NOTIFICATIONS.md` §3 described the web as needing Notification
/// permission, and no line of code asked for it. That was not a bug with a
/// fix; it was a document and a binary disagreeing for months, which is issue
/// #16. The fix closes that one instance. This closes the class: the table in
/// §3 is rendered from these rows by `npm run check:notify-matrix`, and CI
/// fails when the prose and the build part company again.
///
/// The rows are not a fixture generated from the code and then compared with
/// the code — that proves nothing. They are a DECLARATION, and two independent
/// things check it: a Dart test asserts each field against what the code
/// actually does on that platform, and the gate asserts the document says the
/// same. Neither side is allowed to be the only witness.
class NotificationPlatform {
  const NotificationPlatform({
    required this.id,
    required this.gateway,
    required this.localSchedule,
    required this.alarmKit,
    required this.serverPush,
    required this.inAppScreen,
  });

  /// The name the device registry stores (`notification_devices.platform`).
  final String id;

  final NotificationGatewayKind gateway;

  /// Can this platform ask the OS to wake it at an instant, with the app not
  /// running? The whole delivery model rests on this one answer (§0).
  final bool localSchedule;

  /// iOS 26+'s alarm lane: breaks through the mute switch, no entitlement.
  final bool alarmKit;

  /// How a server reaches this install, or null when it cannot.
  final String? serverPush;

  /// The in-app ring screen — every platform has it, and on the ones with no
  /// local schedule it is the only alarm surface there is.
  final bool inAppScreen;
}

/// Every platform the app ships to, in the order the registry lists them.
///
/// Kept beside [gatewayKindFor] rather than in the doc-gate script, because a
/// table that lives in `scripts/` is a table nobody reads while changing the
/// behaviour it describes.
const kNotificationMatrix = <NotificationPlatform>[
  NotificationPlatform(
    id: 'android',
    gateway: NotificationGatewayKind.local,
    localSchedule: true,
    alarmKit: false,
    // A silent data message wakes the app to sync (OPH-322), and a visible
    // push arrives when the device's own schedule is stale (OPH-320).
    serverPush: 'fcm',
    inAppScreen: true,
  ),
  NotificationPlatform(
    id: 'ios',
    gateway: NotificationGatewayKind.local,
    localSchedule: true,
    alarmKit: true,
    // Visible only: no data message, because there is no background mode and
    // a locked wake cannot read the session (ADR-0038 §8).
    serverPush: 'fcm',
    inAppScreen: true,
  ),
  NotificationPlatform(
    id: 'macos',
    gateway: NotificationGatewayKind.local,
    localSchedule: true,
    alarmKit: false,
    // `firebase_messaging` does support macOS, and a Mac left signed in is
    // exactly the device whose local schedule goes stale over a weekend.
    serverPush: 'fcm',
    inAppScreen: true,
  ),
  NotificationPlatform(
    id: 'windows',
    gateway: NotificationGatewayKind.local,
    localSchedule: true,
    alarmKit: false,
    serverPush: null,
    inAppScreen: true,
  ),
  NotificationPlatform(
    id: 'linux',
    gateway: NotificationGatewayKind.local,
    localSchedule: true,
    alarmKit: false,
    serverPush: null,
    inAppScreen: true,
  ),
  NotificationPlatform(
    id: 'web',
    gateway: NotificationGatewayKind.web,
    // The one `false` in this column, and the reason ADR-0038 §3 amends the
    // delivery model: no browser can schedule a notification for a closed tab.
    localSchedule: false,
    alarmKit: false,
    serverPush: 'webpush',
    inAppScreen: true,
  ),
];

/// The row for a registry platform id, or null for one we do not ship to.
NotificationPlatform? notificationPlatformFor(String? id) {
  for (final row in kNotificationMatrix) {
    if (row.id == id) return row;
  }
  return null;
}

/// Whether this platform can hold an FCM registration token at all.
///
/// The app ASKS this before it asks the plugin for a token, which is what
/// keeps the table honest: a row is not documentation about the code, it is
/// the code's own answer. Windows and Linux have no `firebase_messaging`
/// implementation, so a token request there is a caught exception and a device
/// row that never gains credentials — better not to ask.
bool platformCarriesFcmToken(String? id) =>
    notificationPlatformFor(id)?.serverPush == 'fcm';

/// The target platforms that map to a matrix row, for the test that checks the
/// declaration against the code. Web is not a [TargetPlatform].
const kMatrixTargets = <String, TargetPlatform>{
  'android': TargetPlatform.android,
  'ios': TargetPlatform.iOS,
  'macos': TargetPlatform.macOS,
  'windows': TargetPlatform.windows,
  'linux': TargetPlatform.linux,
};
