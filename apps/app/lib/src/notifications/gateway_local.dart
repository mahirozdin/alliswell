import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../i18n/i18n.dart';
import 'actions.dart';
import 'gateway.dart';

const _normalCategoryId = 'aw_reminder';
const _urgentCategoryId = 'aw_urgent';

/// Bundled alarm bed (28 s — under iOS's 30 s cap, past which the system
/// falls back to the default sound). iOS: `Runner/Resources/aw_alarm.caf`
/// (ima4, in the pbxproj); Android: `res/raw/aw_alarm.m4a`.
const _iosAlarmSound = 'aw_alarm.caf';
const _androidAlarmSound = 'aw_alarm';

/// The urgent channel is VERSIONED: Android channels are immutable after
/// creation (sound/attributes can never change), so shipping the real alarm
/// sound + alarm audio usage required a new id. v1 (`urgent_alarms`) is
/// deleted at initialize; do NOT reuse old ids — recreating a deleted id
/// resurrects its frozen settings.
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

  /// Cached critical-alerts grant (iOS/macOS). Refreshed on initialize and
  /// on every permission request; consulted per-schedule.
  bool _criticalEnabled = false;

  @override
  Stream<NotificationEvent> get events => _events.stream;

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
      onDidReceiveNotificationResponse: (response) => _events.add(
        NotificationEvent(
          actionId: response.actionId,
          payload: response.payload,
        ),
      ),
    );

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
  Future<void> schedule(PlannedNotification notification) async {
    final urgent = notification.urgent;

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
      urgent ? _urgentChannelId : 'reminders',
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
      sound: urgent
          ? const RawResourceAndroidNotificationSound(_androidAlarmSound)
          : null,
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
    final critical = urgent && _criticalEnabled;
    final iosDetails = DarwinNotificationDetails(
      categoryIdentifier: urgent ? _urgentCategoryId : _normalCategoryId,
      sound: urgent ? _iosAlarmSound : null,
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
  }
}
