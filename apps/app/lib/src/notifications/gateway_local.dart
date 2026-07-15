import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'actions.dart';
import 'gateway.dart';

const _normalCategoryId = 'aw_reminder';
const _urgentCategoryId = 'aw_urgent';

/// The real OS adapter (OPH-061, plan: docs/NOTIFICATIONS.md). Exactness
/// choices live HERE: urgent alarms ride `AndroidScheduleMode.alarmClock`
/// (never deferred, Doze-exempt) and iOS `timeSensitive`; normal reminders
/// use `exactAllowWhileIdle`. Only this file touches the plugin — the logic
/// layer is device-free and fully tested.
class LocalNotificationsGateway implements NotificationsGateway {
  LocalNotificationsGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _events = StreamController<NotificationEvent>.broadcast();
  bool _initialized = false;

  @override
  Stream<NotificationEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    final darwinCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        _normalCategoryId,
        actions: [
          DarwinNotificationAction.plain(kActionComplete, 'Tamamla'),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}30_min',
            '30 dk ertele',
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}1_hour',
            '1 saat ertele',
          ),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}tomorrow_morning',
            'Yarın sabah',
          ),
        ],
      ),
      DarwinNotificationCategory(
        _urgentCategoryId,
        actions: [
          DarwinNotificationAction.plain(kActionAcknowledge, 'Onayla'),
          DarwinNotificationAction.plain(kActionComplete, 'Tamamla'),
          DarwinNotificationAction.plain('${kActionSnoozePrefix}5_min', '5 dk'),
          DarwinNotificationAction.plain(
            '${kActionSnoozePrefix}30_min',
            '30 dk',
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
        linux: const LinuxInitializationSettings(defaultActionName: 'Aç'),
      ),
      onDidReceiveNotificationResponse: (response) => _events.add(
        NotificationEvent(
          actionId: response.actionId,
          payload: response.payload,
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final notifications = await android.requestNotificationsPermission();
      // Android 14+ denies exact alarms by default (NOTIFICATIONS.md §1) —
      // this deep-links the user to the "Alarms & reminders" special access.
      final exact = await android.requestExactAlarmsPermission();
      return (notifications ?? true) && (exact ?? true);
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (macos != null) {
      return await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    return true;
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
            const AndroidNotificationAction(
              kActionAcknowledge,
              'Onayla',
              showsUserInterface: true,
            ),
            const AndroidNotificationAction(
              '${kActionSnoozePrefix}5_min',
              '5 dk',
              showsUserInterface: true,
            ),
            const AndroidNotificationAction(
              '${kActionSnoozePrefix}30_min',
              '30 dk',
              showsUserInterface: true,
            ),
          ]
        : <AndroidNotificationAction>[
            const AndroidNotificationAction(
              kActionComplete,
              'Tamamla',
              showsUserInterface: true,
            ),
            const AndroidNotificationAction(
              '${kActionSnoozePrefix}30_min',
              '30 dk',
              showsUserInterface: true,
            ),
            const AndroidNotificationAction(
              '${kActionSnoozePrefix}1_hour',
              '1 saat',
              showsUserInterface: true,
            ),
          ];

    final android = AndroidNotificationDetails(
      urgent ? 'urgent_alarms' : 'reminders',
      urgent ? 'Acil alarmlar' : 'Hatırlatıcılar',
      channelDescription: urgent
          ? 'Onay gerektiren ısrarcı alarmlar'
          : 'Görev hatırlatıcıları',
      importance: Importance.max,
      priority: Priority.high,
      category: urgent
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      // Android 14+ gates this behind special access; the OS downgrades to a
      // heads-up notification when not granted (NOTIFICATIONS.md §1).
      fullScreenIntent: urgent,
      actions: androidActions,
    );

    final darwin = DarwinNotificationDetails(
      categoryIdentifier: urgent ? _urgentCategoryId : _normalCategoryId,
      interruptionLevel: urgent
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
    );

    await _plugin.zonedSchedule(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      // Absolute UTC instant — wall-clock math happened upstream.
      scheduledDate: tz.TZDateTime.from(notification.fireAt.toUtc(), tz.UTC),
      notificationDetails: NotificationDetails(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: const LinuxNotificationDetails(),
      ),
      androidScheduleMode: urgent
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.exactAllowWhileIdle,
      payload: notification.payload,
    );
  }
}
