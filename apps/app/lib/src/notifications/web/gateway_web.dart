import 'dart:async';

import '../gateway.dart';
import 'alert_cache.dart';
import 'push_host.dart';
import '../web_alert_mode.dart';

/// The browser's notification gateway (OPH-313, ADR-0038).
///
/// ── WHAT THIS REPLACES ────────────────────────────────────────────────────
///
/// `notificationsGatewayProvider` handed web the same gateway as a phone, and
/// `flutter_local_notifications` has no web implementation — so every
/// call died in a `MissingPluginException`, the scheduler caught it and wrote a
/// `degraded` row, and the app carried on as if it had scheduled something. The
/// user's report — a reminder that pops up without ringing — was impossible on
/// a surface that could not put anything in front of them at all.
///
/// ── IT DOES NOT SCHEDULE, AND THAT IS THE HONEST PART ─────────────────────
///
/// No browser can schedule a local notification: Notification Triggers went
/// through two Chrome origin trials and was abandoned. So on the web the SERVER
/// is the clock — the one platform where that is true (ADR-0038) — and this
/// gateway's job is to make that possible and to say so when it is not.
///
/// `schedule`/`cancel`/`pendingIds` therefore keep an in-memory set and touch
/// no OS at all. That is not pretending: the scheduler's whole algorithm is set
/// arithmetic over ids, it needs `pendingIds` to converge or it re-plans
/// forever, and what actually fires arrives from the server through the service
/// worker. The set is deliberately NOT persisted — it describes this tab's
/// session, and a stale set read at startup would claim deliveries nobody owns.
///
/// ── AND WHAT IT REFUSES TO PRETEND ────────────────────────────────────────
///
/// Permission granted is not the same as reachable. A browser can hold the
/// permission while the instance has no VAPID keys, or while the subscription
/// has been revoked — and in both cases nothing arrives once the tab is closed.
/// That is why `alarmSupport` reports `webPushReady` separately, and why
/// `AlarmProblem.webPushOff` exists: a banner going quiet because permission
/// is granted would be the silent failure NOTIFICATIONS §3 forbids.
class WebNotificationsGateway implements NotificationsGateway {
  WebNotificationsGateway({
    required this.host,

    /// The instance's VAPID public key, or null when this server does not do
    /// push at all — `/api/v1/push/public-key` 404s there by design (OPH-310).
    required this.readVapidKey,

    /// Called after a successful subscribe, so the device registry can send it
    /// on without this gateway needing to know the API exists.
    this.onSubscriptionChanged,

    /// Where the service worker will look for what a notification should say.
    required this.cache,

    /// What it shows when that lookup misses — the same pair privacy mode
    /// produces, so the two read identically.
    required this.fallback,

    /// How loud this browser is (OPH-316). A function, not a value: the
    /// gateway is built once per session and the setting changes under it.
    /// Read at write time and stored WITH the words, because the service
    /// worker must not be the place a preference lives.
    this.alertMode = _defaultAlertMode,
  }) {
    _clicks = host.notificationClicks.listen(
      (payload) => emit(NotificationEvent(payload: payload)),
    );
  }

  final WebPushHost host;
  final Future<String?> Function() readVapidKey;
  final void Function()? onSubscriptionChanged;
  final AlertCache cache;
  final AlertText fallback;
  final WebAlertMode Function() alertMode;

  StreamSubscription<String>? _clicks;

  /// The earliest fire time written for each reminder, so the order the
  /// scheduler happens to call `schedule` in cannot decide which slot's words
  /// the worker finds.
  final Map<String, DateTime> _earliest = <String, DateTime>{};

  final Set<int> _planned = <int>{};
  final StreamController<NotificationEvent> _events =
      StreamController<NotificationEvent>.broadcast();

  WebPushSubscription? _subscription;

  /// What this browser is registered as, if anything. The device registry
  /// reads it; OPH-314's service worker is what turns a push into a window.
  Future<WebPushSubscription?> subscription() async {
    _subscription ??= await host.currentSubscription();
    return _subscription;
  }

  @override
  Future<void> initialize() async {
    // The only thing worth doing up front: put the fallback in place before a
    // push can arrive and find nothing. Every permission probe below asks the
    // browser directly, because one the user changed in another tab must not
    // be remembered.
    await cache.putFallback(fallback);
  }

  @override
  Future<bool> requestPermissions() async {
    if (!host.isSupported) return false;

    final permission = await host.requestPermission();
    if (permission != WebPushPermission.granted) return false;

    // Asked BEFORE subscribing on purpose: without a key there is nothing to
    // subscribe with, and a browser left holding permission it cannot use is
    // the state the banner has to be able to describe.
    final key = await readVapidKey();
    if (key == null) return false;

    _subscription = await host.subscribe(key);
    if (_subscription == null) return false;

    onSubscriptionChanged?.call();
    return true;
  }

  /// Whether this browser plays a sound even for a notification that asked
  /// not to (OPH-316). The setting says so; nothing here can fix it.
  bool get ignoresSilence => host.ignoresSilence;

  /// Makes the browser agree with the setting (OPH-316).
  ///
  /// `off` drops the subscription, which is the only honest way to deliver
  /// nothing: a push subscription is `userVisibleOnly`, so a worker that
  /// receives and shows nothing gets the browser's generic card instead — the
  /// user would be told LESS while believing they had turned it off. Coming
  /// back on re-subscribes, and the toggle itself is the user gesture Safari
  /// requires for the permission prompt.
  Future<void> applyAlertMode(WebAlertMode mode) async {
    if (!host.isSupported) return;
    if (mode == WebAlertMode.off) {
      if (_subscription == null && await host.currentSubscription() == null) {
        return;
      }
      await host.unsubscribe();
      _subscription = null;
      onSubscriptionChanged?.call();
      return;
    }
    if (await subscription() != null) return; // already reachable
    await requestPermissions();
  }

  @override
  Future<AlarmSupport> alarmSupport() async {
    if (!host.isSupported) {
      return const AlarmSupport(
        notificationsEnabled: false,
        criticalAlertsEnabled: false,
        webPushReady: false,
      );
    }

    final permission = await host.permission();
    final granted = permission == WebPushPermission.granted;
    final subscribed = granted && (await subscription()) != null;

    return AlarmSupport(
      notificationsEnabled: granted,
      // No browser has anything like Apple's critical alerts.
      criticalAlertsEnabled: false,
      // Every Darwin question stays null: web cannot answer them, and a guess
      // would put a wrong sentence in the Settings row.
      webPushReady: subscribed,
    );
  }

  @override
  Future<ScheduledDelivery> scheduleTestAlarm({
    required String title,
    required String body,
    required Duration after,
    String? soundName,
  }) async {
    // The rehearsal is the one thing the browser CAN do on its own, because it
    // happens while the tab is open. It proves the notification appears, which
    // is the question a report about a silent alarm is actually asking.
    Timer(after, () => unawaited(host.showNotification(title, body: body)));
    return const ScheduledDelivery(
      sound: kOsDefaultSoundName,
      level: 'webPush',
    );
  }

  @override
  Future<Set<int>> pendingIds() async => Set<int>.from(_planned);

  @override
  Future<ScheduledDelivery> schedule(PlannedNotification notification) async {
    _planned.add(notification.id);
    await _remember(notification);
    return ScheduledDelivery(
      sound: notification.soundName ?? kOsDefaultSoundName,
      level: 'webPush',
    );
  }

  /// Writes what this alert should say, if it belongs to a reminder a push
  /// could name.
  ///
  /// Nothing is removed on cancel, on purpose: a reminder's chain has several
  /// slots and cancelling one says nothing about the reminder. A stale entry
  /// costs nothing — a push only arrives for something the server believes is
  /// due — and the web cache prunes by age on every write.
  Future<void> _remember(PlannedNotification notification) async {
    final reminderId = notification.reminderId;
    if (reminderId == null) return;
    // Delivery is off: there is no subscription for the server to reach, so
    // there is nothing for the worker to look up either. Turning it back on
    // re-schedules (the mode is a watched input), which re-writes these.
    if (alertMode() == WebAlertMode.off) return;
    final known = _earliest[reminderId];
    if (known != null && !notification.fireAt.isBefore(known)) return;
    _earliest[reminderId] = notification.fireAt;
    await cache.put(
      reminderId,
      AlertText(
        title: notification.title,
        body: notification.body,
        fireAt: notification.fireAt,
        silent: alertMode().silences,
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    _planned.remove(id);
  }

  @override
  Stream<NotificationEvent> get events => _events.stream;

  /// Feeds a tap that reached us from the service worker. Wiring the message
  /// channel is OPH-314's half; the seam is here so that lands as one line.
  void emit(NotificationEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> dispose() async {
    await _clicks?.cancel();
    await _events.close();
  }
}

/// Silent unless the app says otherwise — the value a gateway built without
/// a setting behind it (tests, the rehearsal path) should have.
WebAlertMode _defaultAlertMode() => WebAlertMode.silent;
