/// iOS 26+ AlarmKit lane (OPH-141, NOTIFICATIONS.md §2b).
///
/// AlarmKit is Apple's sanctioned way for a third-party app to ring an alarm
/// that breaks through the mute switch AND the current Focus — no critical-
/// alerts entitlement, only user authorization. On iOS 26+ it takes over the
/// URGENT lane; iOS < 26 and non-urgent reminders stay on OPH-139's
/// time-sensitive notifications.
///
/// This is the same seam shape notifications use: pure lane logic
/// ([planAlarmKitAlarms]) decides WHAT should exist, a fakeable [AlarmKitHost]
/// is the only thing that touches the native bridge, and the scheduler diffs
/// desired-vs-scheduled by content-hash id so acknowledge/complete/snooze
/// cancels an AlarmKit alarm exactly like it cancels a notification.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'gateway.dart';

/// How many alarms the AlarmKit lane may hold at once (OPH-182).
///
/// Apple does not document a per-app ceiling, and `AlarmManager` answers a
/// `maximumLimitReached` error rather than a number. So we stay well under any
/// plausible limit with the NEAREST few urgent alarms, let the rest keep the
/// notification chain, and write both facts to the alarm log — the real ceiling
/// is something the log will tell us before a user does.
const int kMaxAlarmKitAlarms = 8;

/// One AlarmKit alarm we want to exist on iOS 26+. Unlike the notification
/// chain, an AlarmKit alarm is a SINGLE entry per reminder — AlarmKit does the
/// ring-until-answered presentation natively, so there is no pre-scheduled
/// re-alert chain to model. [id] is a content hash (same scheme as
/// [PlannedNotification]) so set-diffing cancels it on acknowledge.
class AlarmKitAlarm {
  const AlarmKitAlarm({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.taskId,
    required this.reminderId,
    this.stopLabel = '',
    this.snoozeLabel = '',
    this.snoozePreset = '',
    this.soundName,
  });

  final int id;
  final String title;
  final String body;

  /// Absolute UTC instant the alarm rings.
  final DateTime fireAt;
  final String taskId;
  final String reminderId;

  /// The alert's two buttons, already in the user's language (OPH-182). The
  /// bridge cannot localize: it has no access to the app's translations, and a
  /// Swift-side literal is how the alert ended up Turkish-only for everyone.
  final String stopLabel;
  final String snoozeLabel;

  /// Which snooze the secondary button applies, as a preset id — the FIRST of
  /// the user's own snooze order (OPH-179 N4). The press comes back as
  /// `snooze:<preset>`, so the model, the task row and every other device learn
  /// about it exactly as they would from the in-app ring screen.
  final String snoozePreset;

  /// The installed iOS sound file (OPH-181), or null for the system alarm sound.
  /// Part of the id seed, so changing the sound reschedules.
  final String? soundName;

  Map<String, Object?> toArgs() => {
    'id': id,
    'title': title,
    'body': body,
    'fireAtMs': fireAt.toUtc().millisecondsSinceEpoch,
    'taskId': taskId,
    'reminderId': reminderId,
    'stopLabel': stopLabel,
    'snoozeLabel': snoozeLabel,
    'snoozePreset': snoozePreset,
    'soundName': soundName,
  };
}

/// What the native side made of a [AlarmKitHost.schedule] call. A failure is
/// never silent: the scheduler writes [reason] to the alarm log, and the alarm
/// keeps its notification chain instead of being quietly dropped.
class AlarmKitScheduleResult {
  const AlarmKitScheduleResult.ok() : reason = null;
  const AlarmKitScheduleResult.failed(this.reason);

  /// Null when the alarm was accepted. `limit_reached` is the undocumented
  /// per-app ceiling; anything else is the platform error verbatim.
  final String? reason;

  bool get ok => reason == null;
}

/// The seam between the AlarmKit LANE logic (pure, tested) and the native iOS
/// 26+ bridge (`ios/Runner/AlarmKitBridge.swift`). Widget/unit tests swap in a
/// fake; no platform channel leaks into the logic layer.
abstract class AlarmKitHost {
  /// True only where AlarmKit exists — an iOS 26+ build. Cheap, prompts
  /// nothing; false everywhere else so the lane stays dormant.
  Future<bool> isSupported();

  /// Prompts the first time only; afterwards the OS answers from its record.
  /// Returns whether we may schedule alarms. When this is false the scheduler
  /// keeps URGENT alarms on the notification lane rather than dropping them.
  Future<bool> requestAuthorization();

  Future<Set<int>> scheduledIds();

  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm);

  Future<void> cancel(int id);

  /// Onayla / Ertele presses on the AlarmKit alert, surfaced as the same
  /// [NotificationEvent] the notification lane emits, so one handler serves
  /// both ([handleNotificationEvent]).
  Stream<NotificationEvent> get events;
}

/// The no-AlarmKit default: every platform except iOS 26+. Reports unsupported
/// and no-ops everything, so the scheduler leaves the URGENT lane on
/// notifications (OPH-139). Also the safe fake for platform-less tests.
class UnsupportedAlarmKitHost implements AlarmKitHost {
  const UnsupportedAlarmKitHost();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> requestAuthorization() async => false;

  @override
  Future<Set<int>> scheduledIds() async => const <int>{};

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) async =>
      const AlarmKitScheduleResult.ok();

  @override
  Future<void> cancel(int id) async {}

  @override
  Stream<NotificationEvent> get events => const Stream.empty();
}

/// The real bridge over `MethodChannel('alliswell/alarmkit')`. Degrades to
/// "unsupported" on any channel absence or failure — AlarmKit trouble must
/// never break the app (the alarm falls back to the notification lane).
class MethodChannelAlarmKitHost implements AlarmKitHost {
  MethodChannelAlarmKitHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('alliswell/alarmkit') {
    _channel.setMethodCallHandler(_onNativeCall);
    // Onayla/Ertele work while the app is NOT running: iOS performs the alert's
    // intent in a background launch, which parks the action in the shared app
    // group. Ask for it the moment a handler exists — otherwise the first thing
    // this lane loses is the acknowledgement of the alarm that actually woke
    // someone up.
    unawaited(_drainPendingActions());
  }

  Future<void> _drainPendingActions() async {
    try {
      await _channel.invokeMethod<void>('drainPendingActions');
    } on MissingPluginException {
      // No bridge here (iOS < 26 build, or another platform).
    } on PlatformException {
      // Transient; the next foreground drains again.
    }
  }

  final MethodChannel _channel;
  final StreamController<NotificationEvent> _events =
      StreamController<NotificationEvent>.broadcast();

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'onAlarmAction') {
      final args =
          (call.arguments as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      _events.add(
        NotificationEvent(
          actionId: args['actionId'] as String?,
          payload: args['payload'] as String?,
        ),
      );
    }
    return null;
  }

  @override
  Future<bool> isSupported() => _flag('isSupported');

  @override
  Future<bool> requestAuthorization() => _flag('requestAuthorization');

  Future<bool> _flag(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false; // iOS < 26 / non-Apple: the channel isn't registered.
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Set<int>> scheduledIds() async {
    try {
      final ids = await _channel.invokeListMethod<int>('scheduledIds');
      return ids?.toSet() ?? const <int>{};
    } on MissingPluginException {
      return const <int>{};
    } on PlatformException {
      return const <int>{};
    }
  }

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) async {
    try {
      await _channel.invokeMethod<void>('schedule', alarm.toArgs());
      return const AlarmKitScheduleResult.ok();
    } on MissingPluginException {
      // no AlarmKit here — the notification lane already covers this alarm.
      return const AlarmKitScheduleResult.failed('missing-plugin');
    } on PlatformException catch (error) {
      // `limit_reached` is the undocumented per-app ceiling; everything else is
      // transient and the next replica change re-applies.
      return AlarmKitScheduleResult.failed(error.code);
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on MissingPluginException {
      // nothing to cancel.
    } on PlatformException {
      // transient.
    }
  }

  @override
  Stream<NotificationEvent> get events => _events.stream;
}
