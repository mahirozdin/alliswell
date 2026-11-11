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
import 'dart:convert';

import 'package:flutter/services.dart';

import 'alarm_log.dart';
import 'alarmkit_identity.dart';

/// How many alarms the AlarmKit lane may hold at once (OPH-182).
///
/// Apple does not document a per-app ceiling, and `AlarmManager` answers a
/// `maximumLimitReached` error rather than a number. So we stay well under any
/// plausible limit with the NEAREST few urgent alarms, let the rest keep the
/// notification chain, and write both facts to the alarm log — the real ceiling
/// is something the log will tell us before a user does.
const int kMaxAlarmKitAlarms = 8;

/// One AlarmKit alarm we want to exist on iOS 26+. Unlike the notification
/// chain, an AlarmKit alarm is a SINGLE entry per occurrence — AlarmKit does
/// the ring-until-answered presentation natively, so there is no pre-scheduled
/// re-alert chain to model. [id] is the occurrence id (members + instant,
/// NOTIFICATIONS.md §2b.3) so set-diffing cancels it on acknowledge and
/// replaces it when the time moves; [fp] fingerprints the presentation.
class AlarmKitAlarm {
  AlarmKitAlarm({
    required this.id,
    required this.members,
    required this.fp,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.taskId,
    required this.reminderId,
    List<String>? reminderIds,
    this.stopLabel = '',
    this.snoozeLabel = '',
    this.snoozePreset = '',
    this.soundName,
  }) : reminderIds = reminderIds ?? [reminderId];

  /// `alarmKitOccurrenceId(members, alarmKitFireAtMs(fireAt))`.
  final int id;

  /// The task ids this alarm rings for, sorted and unique. The member key is
  /// the task id, never the reminder id (§2b.3).
  final List<String> members;

  /// `alarmKitFingerprint(...)` of title, body, sound, labels and preset: a
  /// change here rebuilds the alarm under the same [id].
  final int fp;
  final String title;
  final String body;

  /// Absolute UTC instant the alarm rings.
  final DateTime fireAt;
  final String taskId;
  final String reminderId;

  /// Every reminder row this occurrence rings for (a snoozed task's remind and
  /// due rows land on one instant). The notification lane skips all of them.
  final List<String> reminderIds;

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
  /// Part of the fingerprint, so changing the sound reschedules.
  final String? soundName;

  Map<String, Object?> toArgs() => {
    'id': id,
    'members': members,
    'fp': fp,
    'title': title,
    'body': body,
    'fireAtMs': alarmKitFireAtMs(fireAt),
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

/// Where an AlarmKit alarm is in its life (`Alarm.State`, §2b.3).
enum AlarmKitAlarmState {
  scheduled,
  countdown,
  paused,
  alerting;

  /// An unknown future state reads as [scheduled]: the conservative answer,
  /// because only [alerting] protects an alarm from the plan pass.
  static AlarmKitAlarmState parse(Object? raw) => switch (raw) {
    'countdown' => countdown,
    'paused' => paused,
    'alerting' => alerting,
    _ => scheduled,
  };
}

/// One row of `scheduledAlarms` (§2b.3): an alarm the OS holds, joined with
/// its App Group ledger record. A row without a ledger record (an alarm from a
/// build before the contract, or an older bridge that only knows
/// `scheduledIds`) has no [members], `fp == 0` and [hasLedger] false.
class AlarmKitScheduled {
  const AlarmKitScheduled({
    required this.id,
    this.fp = 0,
    this.state = AlarmKitAlarmState.scheduled,
    this.members = const [],
    this.fireAtMs,
    this.origin = 'dart',
    this.eventId,
  });

  final int id;
  final int fp;
  final AlarmKitAlarmState state;
  final List<String> members;

  /// Null only on an older bridge, which cannot say when its alarm rings.
  final int? fireAtMs;

  /// `dart` (written by `schedule`) or `native` (a native snooze, [eventId]
  /// set — the event that must be applied before the alarm may be touched).
  final String origin;
  final String? eventId;

  bool get hasLedger => members.isNotEmpty;

  static AlarmKitScheduled? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    if (id == null) return null;
    return AlarmKitScheduled(
      id: id,
      fp: _int(raw['fp']) ?? 0,
      state: AlarmKitAlarmState.parse(raw['state']),
      members: _strings(raw['members']),
      fireAtMs: _int(raw['fireAtMs']),
      origin: raw['origin'] as String? ?? 'dart',
      eventId: raw['eventId'] as String?,
    );
  }
}

/// One queued press (§2b.3 "Action event", queue entry v2): Ertele / Onayla on
/// the AlarmKit alert, or a widget's completion. Pulled, never pushed; it stays
/// in the native queue until [AlarmKitHost.ackActions] names its [eventId].
class AlarmKitActionEvent {
  const AlarmKitActionEvent({
    required this.eventId,
    required this.action,
    required this.taskIds,
    required this.pressedAtMs,
    this.origin = 'alarmkit',
    this.untilMs,
    this.preset,
    this.occurrenceFireAtMs,
    this.alarmId,
    this.newId,
    this.scheduleOutcome,
    this.stopOutcome,
    this.reminderId,
  });

  /// Unique; the key of `action_receipts`.
  final String eventId;

  /// `snooze` · `acknowledge` · `complete`.
  final String action;
  final List<String> taskIds;
  final int pressedAtMs;

  /// `alarmkit` · `widget`.
  final String origin;

  /// The native snooze target, floored to the second — written unchanged.
  final int? untilMs;

  /// Only on an entry converted from v1 (no [untilMs]).
  final String? preset;
  final int? occurrenceFireAtMs;
  final int? alarmId;
  final int? newId;

  /// `ok` · `limitReached` · `failed` (native snooze only).
  final String? scheduleOutcome;

  /// `stopped` · `cancelled` · `failed` (native snooze only).
  final String? stopOutcome;

  /// Dart-only: the legacy path's `payload.reminderId` (macOS, an older
  /// bridge). Never sent by a v2 native side.
  final String? reminderId;

  static AlarmKitActionEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final eventId = raw['eventId'];
    final action = raw['action'];
    final pressedAtMs = _int(raw['pressedAtMs']);
    if (eventId is! String || eventId.isEmpty) return null;
    if (action is! String || pressedAtMs == null) return null;
    return AlarmKitActionEvent(
      eventId: eventId,
      action: action,
      taskIds: _strings(raw['taskIds']).toSet().toList(),
      pressedAtMs: pressedAtMs,
      origin: raw['origin'] as String? ?? 'alarmkit',
      untilMs: _int(raw['untilMs']),
      preset: raw['preset'] as String?,
      occurrenceFireAtMs: _int(raw['occurrenceFireAtMs']),
      alarmId: _int(raw['alarmId']),
      newId: _int(raw['newId']),
      scheduleOutcome: raw['scheduleOutcome'] as String?,
      stopOutcome: raw['stopOutcome'] as String?,
    );
  }
}

/// What `stop` did (§2b.3): `AlarmManager.stop`, `cancel` when stop threw.
class AlarmKitStopResult {
  const AlarmKitStopResult({
    this.stopped = false,
    this.cancelled = false,
    this.error,
  });

  final bool stopped;
  final bool cancelled;
  final String? error;
}

/// One row of the App Group failure ring `aw.alarmkit.failures` (§2b.3): a
/// native snooze stage that went wrong while Dart was not running.
class AlarmKitFailure {
  const AlarmKitFailure({
    required this.eventId,
    required this.atMs,
    required this.stage,
    required this.code,
    this.message = '',
  });

  final String eventId;
  final int atMs;

  /// `schedule` · `stop` · `cancel` · `fallback`.
  final String stage;

  /// `maximumLimitReached` · `other`.
  final String code;
  final String message;

  static AlarmKitFailure? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final atMs = _int(raw['atMs']);
    if (atMs == null) return null;
    return AlarmKitFailure(
      eventId: raw['eventId'] as String? ?? '',
      atMs: atMs,
      stage: raw['stage'] as String? ?? 'other',
      code: raw['code'] as String? ?? 'other',
      message: raw['message'] as String? ?? '',
    );
  }
}

int? _int(Object? raw) => switch (raw) {
  final int v => v,
  final num v => v.toInt(),
  _ => null,
};

List<String> _strings(Object? raw) => raw is List
    ? [
        for (final v in raw)
          if (v is String) v,
      ]
    : const [];

/// The seam between the AlarmKit LANE logic (pure, tested) and the native iOS
/// 26+ bridge (`ios/Runner/AlarmKitBridge.swift`), contract v2
/// (NOTIFICATIONS.md §2b.3). Widget/unit tests swap in a fake; no platform
/// channel leaks into the logic layer.
///
/// Nothing is pushed down the channel: native only says "there is something
/// to pull" ([actionsPending]) and Dart pulls, so a press made while the app
/// was dead cannot be lost to a listener that did not exist yet.
abstract class AlarmKitHost {
  /// True only where AlarmKit exists — an iOS 26+ build. Cheap, prompts
  /// nothing; false everywhere else so the lane stays dormant.
  Future<bool> isSupported();

  /// Prompts the first time only; afterwards the OS answers from its record.
  /// Returns whether we may schedule alarms. When this is false the scheduler
  /// keeps URGENT alarms on the notification lane rather than dropping them.
  Future<bool> requestAuthorization();

  /// The current grant, read WITHOUT prompting (round 19 K4).
  ///
  /// The scheduler consulted [requestAuthorization] exactly once, at start, and
  /// cached the answer for the whole session. Revoke the permission in iOS
  /// Settings and every urgent alarm kept being routed to a lane that would
  /// refuse it — silence on both lanes, which is the failure this round is
  /// about. Cheap enough to ask on every apply, and it must never prompt:
  /// a permission dialog appearing because a task's due date changed would be
  /// its own bug.
  Future<bool> isAuthorized();

  /// Every alarm the OS holds, joined with the ledger. A bridge without the
  /// method degrades to [scheduledIds] rows with no ledger fields.
  Future<List<AlarmKitScheduled>> scheduledAlarms();

  /// The ids of [scheduledAlarms], for older callers.
  Future<Set<int>> scheduledIds();

  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm);

  Future<void> cancel(int id);

  /// Silences a ringing alarm (`AlarmManager.stop`, `cancel` if that throws).
  Future<AlarmKitStopResult> stop(int id);

  /// The queued presses, sorted by `pressedAtMs`. NOT removed: the caller
  /// applies each one and then names it in [ackActions].
  Future<List<AlarmKitActionEvent>> pullPendingActions();

  /// Removes these entries from the native queue — only after their write
  /// committed. Unknown ids are ignored.
  Future<void> ackActions(List<String> eventIds);

  /// Removes the `aw.fallback.<eventId>` notifications a failed native snooze
  /// left behind, once Dart's own plan covers the new time.
  Future<void> clearFallbacks(List<String> eventIds);

  /// The native failure ring; the returned rows are removed.
  Future<List<AlarmKitFailure>> pullFailures();

  /// "Pull now": one tick for every new listener (the host attaching), then
  /// one per native `onActionsPending`.
  Stream<void> get actionsPending;
}

/// Native failures land in the device's alarm log — the honest record of
/// what went wrong while the app was not running (§2b.3).
extension AlarmKitNativeFailures on AlarmKitHost {
  Future<void> copyNativeFailures(AlarmLog log) async {
    final failures = await pullFailures();
    for (final f in failures) {
      await log.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail: [
          'native ${f.stage}: ${f.code}',
          if (f.message.isNotEmpty) f.message,
          if (f.eventId.isNotEmpty) '(event ${f.eventId})',
        ].join(' '),
        at: DateTime.fromMillisecondsSinceEpoch(f.atMs, isUtc: true),
      );
    }
  }
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
  Future<bool> isAuthorized() async => false;

  @override
  Future<List<AlarmKitScheduled>> scheduledAlarms() async => const [];

  @override
  Future<Set<int>> scheduledIds() async => const <int>{};

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) async =>
      const AlarmKitScheduleResult.ok();

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<AlarmKitStopResult> stop(int id) async =>
      const AlarmKitStopResult(error: 'unsupported');

  @override
  Future<List<AlarmKitActionEvent>> pullPendingActions() async => const [];

  @override
  Future<void> ackActions(List<String> eventIds) async {}

  @override
  Future<void> clearFallbacks(List<String> eventIds) async {}

  @override
  Future<List<AlarmKitFailure>> pullFailures() async => const [];

  @override
  Stream<void> get actionsPending => const Stream.empty();
}

/// The real bridge over `MethodChannel('alliswell/alarmkit')`. Degrades to
/// "unsupported" on any channel absence or failure — AlarmKit trouble must
/// never break the app (the alarm falls back to the notification lane).
///
/// The constructor calls nothing: Dart pulls when a listener attaches to
/// [actionsPending]. The one exception to "nothing is pushed" is the legacy
/// path of §2b.3 — a bridge without `pullPendingActions` (macOS, an older
/// build) still answers `drainPendingActions` by pushing `onAlarmAction`;
/// those pushes are buffered here and handed out by the next pull.
class MethodChannelAlarmKitHost implements AlarmKitHost {
  MethodChannelAlarmKitHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('alliswell/alarmkit') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final StreamController<void> _pending = StreamController<void>.broadcast();

  /// Legacy pushes not yet pulled, and whether this bridge is legacy at all.
  final List<AlarmKitActionEvent> _legacy = [];
  final Set<String> _legacyIds = {};
  bool _legacyBridge = false;
  int _legacySeq = 0;

  Future<Object?> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onActionsPending':
        _pending.add(null);
      case 'onAlarmAction':
        final event = _fromLegacyPush(call.arguments);
        if (event != null) {
          _legacy.add(event);
          _legacyIds.add(event.eventId);
          _pending.add(null);
        }
    }
    return null;
  }

  /// A legacy push — `actionId` `acknowledge`, `complete` or `snooze:<preset>`
  /// plus a JSON `payload` with `taskId` and `reminderId` — as a v2 event with
  /// a fresh id (§2b.3 legacy path).
  AlarmKitActionEvent? _fromLegacyPush(Object? arguments) {
    final args = arguments is Map ? arguments : const {};
    final actionId = args['actionId'] as String? ?? '';
    Map<String, Object?> payload;
    try {
      payload = (jsonDecode(args['payload'] as String? ?? '') as Map)
          .cast<String, Object?>();
    } catch (_) {
      return null; // not ours / corrupted
    }
    final taskId = payload['taskId'];
    if (taskId is! String || taskId.isEmpty) return null;
    final snooze = actionId.startsWith('snooze:');
    final action = snooze ? 'snooze' : actionId;
    if (!snooze && action != 'acknowledge' && action != 'complete') {
      return null;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final reminderId = payload['reminderId'];
    return AlarmKitActionEvent(
      eventId: 'legacy|$now|${_legacySeq++}',
      action: action,
      taskIds: [taskId],
      pressedAtMs: now,
      origin: action == 'complete' ? 'widget' : 'alarmkit',
      preset: snooze ? actionId.substring('snooze:'.length) : null,
      reminderId: reminderId is String && reminderId.isNotEmpty
          ? reminderId
          : null,
    );
  }

  @override
  Stream<void> get actionsPending => Stream<void>.multi((listener) {
    // The host attaching is itself a reason to pull (§2b.3).
    listener.add(null);
    final sub = _pending.stream.listen(listener.add);
    listener.onCancel = sub.cancel;
  });

  @override
  Future<bool> isSupported() => _flag('isSupported');

  @override
  Future<bool> requestAuthorization() => _flag('requestAuthorization');

  @override
  Future<bool> isAuthorized() => _flag('isAuthorized');

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
  Future<List<AlarmKitScheduled>> scheduledAlarms() async {
    try {
      final rows = await _channel.invokeListMethod<Object?>('scheduledAlarms');
      return [
        for (final row in rows ?? const <Object?>[])
          ?AlarmKitScheduled.fromMap(row),
      ];
    } on MissingPluginException {
      // An older bridge: ids only, no ledger fields.
      return [
        for (final id in await _legacyScheduledIds()) AlarmKitScheduled(id: id),
      ];
    } on PlatformException {
      return const [];
    }
  }

  Future<List<int>> _legacyScheduledIds() async {
    try {
      return await _channel.invokeListMethod<int>('scheduledIds') ??
          const <int>[];
    } on MissingPluginException {
      return const <int>[];
    } on PlatformException {
      return const <int>[];
    }
  }

  @override
  Future<Set<int>> scheduledIds() async => {
    for (final alarm in await scheduledAlarms()) alarm.id,
  };

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
  Future<AlarmKitStopResult> stop(int id) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('stop', {
        'id': id,
      });
      return AlarmKitStopResult(
        stopped: raw?['stopped'] == true,
        cancelled: raw?['cancelled'] == true,
        error: raw?['error'] as String?,
      );
    } on MissingPluginException {
      return const AlarmKitStopResult(error: 'missing-plugin');
    } on PlatformException catch (error) {
      return AlarmKitStopResult(error: error.code);
    }
  }

  @override
  Future<List<AlarmKitActionEvent>> pullPendingActions() async {
    final out = <AlarmKitActionEvent>[];
    if (!_legacyBridge) {
      try {
        final rows = await _channel.invokeListMethod<Object?>(
          'pullPendingActions',
        );
        out.addAll([
          for (final row in rows ?? const <Object?>[])
            ?AlarmKitActionEvent.fromMap(row),
        ]);
      } on MissingPluginException {
        _legacyBridge = true;
      } on PlatformException {
        // Transient; the next resume pulls again.
      }
    }
    if (_legacyBridge) {
      // §2b.3 legacy path: the drain answers with `onAlarmAction` pushes,
      // which arrive as their own calls and announce themselves.
      try {
        await _channel.invokeMethod<void>('drainPendingActions');
      } on MissingPluginException {
        // No bridge at all.
      } on PlatformException {
        // Transient.
      }
    }
    out.addAll(_legacy);
    _legacy.clear();
    // A stable sort: equal press times keep the native queue's order.
    final indexed = out.indexed.toList()
      ..sort((a, b) {
        final byTime = a.$2.pressedAtMs.compareTo(b.$2.pressedAtMs);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, event) in indexed) event];
  }

  @override
  Future<void> ackActions(List<String> eventIds) async {
    // A legacy event left the native queue when it was drained.
    final native = [
      for (final id in eventIds)
        if (!_legacyIds.remove(id)) id,
    ];
    if (native.isEmpty || _legacyBridge) return;
    await _invokeQuietly('ackActions', {'eventIds': native});
  }

  @override
  Future<void> clearFallbacks(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    await _invokeQuietly('clearFallbacks', {'eventIds': eventIds});
  }

  @override
  Future<List<AlarmKitFailure>> pullFailures() async {
    try {
      final rows = await _channel.invokeListMethod<Object?>('pullFailures');
      return [
        for (final row in rows ?? const <Object?>[])
          ?AlarmKitFailure.fromMap(row),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<void> _invokeQuietly(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // An older bridge: nothing to remove.
    } on PlatformException {
      // Transient; the entry is pulled again and its receipt makes it a no-op.
    }
  }
}
