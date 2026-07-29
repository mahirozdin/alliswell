import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../i18n/i18n.dart';
import 'actions.dart';
import 'gateway.dart';

const _normalCategoryId = 'aw_reminder';
const _urgentCategoryId = 'aw_urgent';

/// The bundled alarm bed and the two short tones now come from the sound
/// catalogue (`alarm_sound.dart`) and arrive per-notification as
/// [PlannedNotification.soundName] — the scheduler resolves the user's choice
/// (OPH-181) before planning, so this layer only carries it to the plugin.

/// The urgent channel is VERSIONED **and per-sound**: Android channels are
/// immutable after creation (sound/attributes can never change), so a new sound
/// means a new id (OPH-181) — `urgent_alarms_v2_<sound>`. v1 (`urgent_alarms`)
/// and the soundless v2 are deleted at initialize; do NOT reuse an old id —
/// recreating a deleted one resurrects its frozen settings.
const _urgentChannelId = 'urgent_alarms_v2';
const _legacyUrgentChannelId = 'urgent_alarms';

/// FLAG_INSISTENT: loop the sound until the notification is opened or
/// dismissed — what makes the urgent channel behave like an alarm clock, not
/// a ding (docs/NOTIFICATIONS.md §1).
const _androidInsistentFlag = 4;

/// The real OS adapter (OPH-061, plan: docs/NOTIFICATIONS.md). Exactness and
/// loudness choices live HERE — the logic layer is device-free and tested:
///
/// - urgent → Android `alarmClock` schedule on the v2 alarm channel
///   (USAGE_ALARM routes to the alarm stream: rings through a muted ringer
///   and default DND, insistent loop, full-screen intent where granted);
///   iOS `timeSensitive` + the 28 s alarm sound, upgraded to `critical` +
///   full volume ONLY when Apple's critical-alerts entitlement is granted
///   and the user allowed it (checked, never assumed — an unentitled
///   critical sound payload can silence the notification entirely).
/// - normal reminders → `exactAllowWhileIdle`; iOS `timeSensitive` (a
///   user-scheduled reminder is time-sensitive by definition — `.active`
///   was buried silently by every Focus mode, feedback round 6).
class LocalNotificationsGateway implements NotificationsGateway {
  LocalNotificationsGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _events = StreamController<NotificationEvent>.broadcast();
  bool _initialized = false;

  /// Responses that arrived before anyone was listening (OPH-214).
  ///
  /// The only listener is `notificationSchedulerProvider`, which is not born
  /// until HomeShell is mounted and the workspace has resolved — but a press on
  /// a notification action LAUNCHES the app, so the response is ready long
  /// before that. A plain broadcast controller drops anything sent to nobody,
  /// which is precisely how the snooze button came to do nothing: the work was
  /// computed, then thrown away.
  ///
  /// So they queue here and drain to the first listener. Deferring rather than
  /// dropping also keeps the router out of it until the app is actually
  /// standing up, which is where a tap-to-open was crashing.
  final _pending = <NotificationEvent>[];
  bool _delivered = false;

  /// Cached critical-alerts grant (iOS/macOS). Refreshed on initialize and
  /// on every permission request; consulted per-schedule.
  bool _criticalEnabled = false;

  @override
  Stream<NotificationEvent> get events {
    // `onListen` fires on EVERY new subscriber; only the first one gets the
    // backlog, or a second listener would re-run actions that already ran.
    _events.onListen = () {
      if (_delivered) return;
      _delivered = true;
      final queued = [..._pending];
      _pending.clear();
      // Microtask: the subscription is not wired up until this callback
      // returns, so emitting synchronously would still hit nobody.
      scheduleMicrotask(() {
        for (final event in queued) {
          if (!_events.isClosed) _events.add(event);
        }
      });
    };
    return _events.stream;
  }

  /// Feeds a response through the real queue-or-send path, for tests that must
  /// prove a press arriving BEFORE the app is listening still lands (OPH-214).
  @visibleForTesting
  void debugEmit(NotificationEvent event) => _emit(event);

  /// Every response goes through here, so "queue it or send it" is decided in
  /// exactly one place.
  void _emit(NotificationEvent event) {
    if (_events.hasListener) {
      _events.add(event);
    } else {
      _pending.add(event);
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    // Category/action labels freeze per app run (registered once with the
    // OS); a mid-run language switch applies on next launch.
    final darwinCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        _normalCategoryId,
        actions: [
          DarwinNotificationAction.plain(
            kActionComplete,
            'notif.action.complete'.tr(),
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}30_min',
            'notif.action.snooze30m'.tr(),
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}1_hour',
            'notif.action.snooze1h'.tr(),
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}tomorrow_morning',
            'notif.action.snoozeTomorrow'.tr(),
          ),
        ],
      ),
      DarwinNotificationCategory(
        _urgentCategoryId,
        actions: [
          DarwinNotificationAction.plain(
            kActionAcknowledge,
            'notif.action.acknowledge'.tr(),
          ),
          DarwinNotificationAction.plain(
            kActionComplete,
            'notif.action.complete'.tr(),
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}5_min',
            'notif.action.snooze5m'.tr(),
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}30_min',
            'notif.action.snooze30m'.tr(),
          ),
          // OPH-178: silence for good, without completing the task. Last on
          // purpose — iOS surfaces the first few actions and this is the
          // heaviest one; the ring screen and the task detail carry it too.
          DarwinNotificationAction.plain(kActionMute, 'notif.action.mute'.tr()),
        ],
      ),
    ];

    final darwinSettings = DarwinInitializationSettings(
      // Permissions are requested explicitly in requestPermissions().
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: darwinCategories,
    );

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: LinuxInitializationSettings(
          defaultActionName: 'notif.action.open'.tr(),
        ),
      ),
      onDidReceiveNotificationResponse: (response) => _emit(
        NotificationEvent(
          actionId: response.actionId,
          payload: response.payload,
        ),
      ),
    );

    // OPH-214: the response that STARTED the app. `initialize`'s callback only
    // covers presses while the process is alive; a cold start hands the
    // response over here, and nothing in this repo was ever asking for it —
    // which is why an action pressed on a killed app did nothing at all, in
    // silence. Queued like any other, so it lands when the app can act on it.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response != null) {
      _emit(
        NotificationEvent(
          actionId: response.actionId,
          payload: response.payload,
        ),
      );
    }

    // The soundless v1 channel must not linger next to v2 in system settings.
    await _android?.deleteNotificationChannel(
      channelId: _legacyUrgentChannelId,
    );

    _criticalEnabled = await _probeCritical();
    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  MacOSFlutterLocalNotificationsPlugin? get _macos => _plugin
      .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
      >();

  Future<bool> _probeCritical() async {
    try {
      final options =
          await _ios?.checkPermissions() ?? await _macos?.checkPermissions();
      return options?.isCriticalEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final android = _android;
    if (android != null) {
      final notifications = await android.requestNotificationsPermission();
      // Android 14+ denies exact alarms by default (NOTIFICATIONS.md §1) —
      // this deep-links the user to the "Alarms & reminders" special access.
      final exact = await android.requestExactAlarmsPermission();
      return (notifications ?? true) && (exact ?? true);
    }
    // `critical: true` is safe without Apple's entitlement: the standard
    // permission flow is unaffected and the extra critical-alerts prompt
    // simply never appears. Behavior is gated on the PROBE, never on this
    // request (NOTIFICATIONS.md §2).
    final ios = _ios;
    if (ios != null) {
      final granted =
          await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: true,
          ) ??
          true;
      _criticalEnabled = await _probeCritical();
      return granted;
    }
    final macos = _macos;
    if (macos != null) {
      final granted =
          await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: true,
          ) ??
          true;
      _criticalEnabled = await _probeCritical();
      return granted;
    }
    return true;
  }

  @override
  Future<AlarmSupport> alarmSupport() async {
    final android = _android;
    if (android != null) {
      final enabled = await android.areNotificationsEnabled() ?? true;
      final exact = await android.canScheduleExactNotifications() ?? false;
      return AlarmSupport(
        notificationsEnabled: enabled,
        criticalAlertsEnabled: false,
        exactAlarmsEnabled: exact,
      );
    }
    try {
      final options =
          await _ios?.checkPermissions() ?? await _macos?.checkPermissions();
      if (options != null) {
        return AlarmSupport(
          notificationsEnabled: options.isEnabled,
          criticalAlertsEnabled: options.isCriticalEnabled,
        );
      }
    } catch (_) {
      // fall through to the optimistic default below
    }
    return const AlarmSupport(
      notificationsEnabled: true,
      criticalAlertsEnabled: false,
    );
  }

  @override
  Future<Set<int>> pendingIds() async =>
      (await _plugin.pendingNotificationRequests()).map((r) => r.id).toSet();

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<ScheduledDelivery> schedule(PlannedNotification notification) async {
    final urgent = notification.urgent;
    // One decision, made in one pure place (OPH-176): the loudness contract.
    final delivery = awDeliveryFor(
      urgent: urgent,
      criticalEnabled: _criticalEnabled,
      soundName: notification.soundName,
    );
    // Android channels are IMMUTABLE (NOTIFICATIONS §1 [12]): a different sound
    // needs a different channel id, or the old sound plays forever. One channel
    // per (lane, sound); stale ones are pruned below.
    final channelId = urgent
        ? '${_urgentChannelId}_${notification.soundName ?? 'default'}'
        : 'reminders_${notification.soundName ?? 'default'}';

    final androidActions = urgent
        ? <AndroidNotificationAction>[
            AndroidNotificationAction(
              kActionAcknowledge,
              'notif.action.acknowledge'.tr(),
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              '${kActionSnoozePrefix}5_min',
              'notif.action.snooze5m'.tr(),
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              '${kActionSnoozePrefix}30_min',
              'notif.action.snooze30m'.tr(),
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              kActionMute,
              'notif.action.mute'.tr(),
              showsUserInterface: true,
            ),
          ]
        : <AndroidNotificationAction>[
            AndroidNotificationAction(
              kActionComplete,
              'notif.action.complete'.tr(),
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              '${kActionSnoozePrefix}30_min',
              'notif.action.snooze30m'.tr(),
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              '${kActionSnoozePrefix}1_hour',
              'notif.action.snooze1h'.tr(),
              showsUserInterface: true,
            ),
          ];

    final android = AndroidNotificationDetails(
      channelId,
      urgent
          ? 'notif.channel.urgentName'.tr()
          : 'notif.channel.remindersName'.tr(),
      channelDescription: urgent
          ? 'notif.channel.urgentDesc'.tr()
          : 'notif.channel.remindersDesc'.tr(),
      importance: Importance.max,
      priority: Priority.high,
      category: urgent
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      // USAGE_ALARM routes the sound to the alarm stream — it rings at alarm
      // volume even when the ringer is muted, and default DND lets alarms
      // through (AOSP ZenModeFiltering; NOTIFICATIONS.md §1).
      sound: notification.soundName == null
          ? null
          : RawResourceAndroidNotificationSound(notification.soundName!),
      audioAttributesUsage: urgent
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      additionalFlags: urgent
          ? Int32List.fromList(const [_androidInsistentFlag])
          : null,
      // Android 14+ gates this behind special access; the OS downgrades to a
      // heads-up notification when not granted (NOTIFICATIONS.md §1).
      fullScreenIntent: urgent,
      actions: androidActions,
    );

    // iOS: critical delivery ONLY when the entitlement + user grant exist —
    // an unentitled critical-sound payload degrades to standard delivery and
    // can lose the sound outright, so it is never sent blind.
    final critical = delivery.level == 'critical';
    final iosDetails = DarwinNotificationDetails(
      categoryIdentifier: urgent ? _urgentCategoryId : _normalCategoryId,
      sound: notification.soundName,
      criticalSoundVolume: critical ? 1.0 : null,
      interruptionLevel: critical
          ? InterruptionLevel.critical
          : InterruptionLevel.timeSensitive,
    );
    // macOS Runner does not bundle the caf (no alarm-sound resource there
    // yet) — a named-but-missing sound file means NO sound, so it stays on
    // the default sound at time-sensitive level.
    final macosDetails = DarwinNotificationDetails(
      categoryIdentifier: urgent ? _urgentCategoryId : _normalCategoryId,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.zonedSchedule(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      // Absolute UTC instant — wall-clock math happened upstream.
      scheduledDate: tz.TZDateTime.from(notification.fireAt.toUtc(), tz.UTC),
      notificationDetails: NotificationDetails(
        android: android,
        iOS: iosDetails,
        macOS: macosDetails,
        linux: const LinuxNotificationDetails(),
      ),
      androidScheduleMode: urgent
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.exactAllowWhileIdle,
      payload: notification.payload,
    );
    return delivery;
  }
}
