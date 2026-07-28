import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/workspaces/workspaces.dart';
import 'alarm_sound.dart';
import 'planner.dart';
import 'providers.dart';

/// Injectable "now" for the ring decision (OPH-143). Production reads the wall
/// clock; tests pin it — the same seam as `NotificationScheduler(clock:)` and
/// `TaskStore.snoozeUntilFor(now:)`.
final alarmClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Whether the foreground alarm overlay may take over the screen. True in
/// production; widget tests override it to false (see
/// `test/support/sync_overrides.dart`) so a due alarm never covers the app
/// under test — the OPH-111 `tourAutoStartProvider` idiom.
final alarmOverlayAutoShowProvider = Provider<bool>((_) => true);

/// Every alarm that may fire for the signed-in workspace (reminder rows ⋈ tasks
/// + synthetic task-derived alarms — see [ReminderStore.watchAlarms]). Public so
/// a container test can await the first emission.
final alarmFeedProvider = StreamProvider.autoDispose<List<AlarmInput>>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return Stream.value(const <AlarmInput>[]);
  return ref.watch(reminderStoreProvider).watchAlarms(workspace.id);
});

/// Effective fire instant: a snoozed alarm fires at [AlarmInput.snoozedUntil],
/// otherwise at [AlarmInput.remindAt] — the exact base the planner schedules on
/// (`planNotifications`), so the overlay and the OS notification agree.
DateTime alarmFireAt(AlarmInput a) =>
    (a.status == 'snoozed' ? a.snoozedUntil : null) ?? a.remindAt;

/// The URGENT alarm that should be ringing at [now] (earliest fire first), or
/// null. Only urgent alarms take over the screen (BLUEPRINT §8.2); normal
/// reminders stay in the OS tray. Pure — the DoD's "fake clock" is just [now].
AlarmInput? ringingAlarm(List<AlarmInput> alarms, DateTime now) {
  AlarmInput? best;
  DateTime? bestAt;
  for (final a in alarms) {
    if (!a.urgent) continue;
    final at = alarmFireAt(a);
    if (at.isAfter(now)) continue;
    if (best == null || at.isBefore(bestAt!)) {
      best = a;
      bestAt = at;
    }
  }
  return best;
}

/// The soonest urgent fire strictly after [now] — when to wake the timer wheel.
DateTime? nextUrgentFireAfter(List<AlarmInput> alarms, DateTime now) {
  DateTime? next;
  for (final a in alarms) {
    if (!a.urgent) continue;
    final at = alarmFireAt(a);
    if (!at.isAfter(now)) continue;
    if (next == null || at.isBefore(next)) next = at;
  }
  return next;
}

/// What the shell needs to know: the alarm currently ringing, if any.
class AlarmOverlayState {
  const AlarmOverlayState({this.ringing});

  final AlarmInput? ringing;
}

/// Drives the foreground ring overlay (OPH-143). Watches the alarm feed plus a
/// foreground timer wheel (NOTIFICATIONS.md §3) so an urgent alarm that comes
/// due WHILE the app is open rings without waiting for a DB emission. The OS
/// notification (OPH-139) stays the primary channel; this is the surface while
/// the app is open, and desktop/web's ONLY alarm surface.
class AlarmOverlayController extends Notifier<AlarmOverlayState> {
  Timer? _timer;

  /// Alarms the user just acted on: hide immediately and don't re-ring before
  /// the write lands (and, for an offline synthetic acknowledge that no-ops, at
  /// all). Cleared once an alarm leaves the feed.
  final Set<String> _handled = {};

  DateTime _now() => ref.read(alarmClockProvider)();

  List<AlarmInput> _feed() =>
      ref.read(alarmFeedProvider).value ?? const <AlarmInput>[];

  @override
  AlarmOverlayState build() {
    ref.onDispose(() => _timer?.cancel());
    if (!ref.watch(alarmOverlayAutoShowProvider)) {
      return const AlarmOverlayState();
    }
    return _evaluate(ref.watch(alarmFeedProvider).value ?? const []);
  }

  AlarmOverlayState _evaluate(List<AlarmInput> alarms) {
    _timer?.cancel();
    // Drop handled-ids whose alarm has left the feed, so a legitimately
    // re-armed alarm can ring again later.
    _handled.retainWhere((id) => alarms.any((a) => a.reminderId == id));

    final now = _now();
    final live = alarms.where((a) => !_handled.contains(a.reminderId)).toList();
    final ringing = ringingAlarm(live, now);
    if (ringing != null) return AlarmOverlayState(ringing: ringing);

    final next = nextUrgentFireAfter(alarms, now);
    if (next != null) {
      final wait = next.difference(now);
      _timer = Timer(wait.isNegative ? Duration.zero : wait, _tick);
    }
    return const AlarmOverlayState();
  }

  void _tick() => state = _evaluate(_feed());

  /// The overlay calls this after the user acknowledges / snoozes / completes:
  /// dismiss now; the feed confirms a beat later.
  void handled(String reminderId) {
    _handled.add(reminderId);
    state = _evaluate(_feed());
  }
}

final alarmOverlayControllerProvider =
    NotifierProvider<AlarmOverlayController, AlarmOverlayState>(
      AlarmOverlayController.new,
    );

/// Physical "insistence" for a ringing alarm — a seam so tests inject silence
/// (no pending timers, no platform channels). Production is a looping audio bed
/// PLUS haptic pulses (OPH-180, DESIGN §11 A3); on desktop and web this is the
/// only alarm surface there is (NOTIFICATIONS §3).
abstract class AlarmFeedback {
  void start();
  void stop();

  /// True when the audible half could NOT be started — a browser's autoplay
  /// policy, a missing plugin, a platform without audio. The ring screen offers
  /// a manual start instead of pretending the room is loud.
  ValueListenable<bool> get soundBlocked;
}

/// Haptics only. Kept as the fallback for surfaces with no audio, and as the
/// simplest possible implementation of the seam.
class HapticAlarmFeedback implements AlarmFeedback {
  Timer? _timer;
  final ValueNotifier<bool> _blocked = ValueNotifier(false);

  @override
  ValueListenable<bool> get soundBlocked => _blocked;

  @override
  void start() {
    HapticFeedback.heavyImpact();
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => HapticFeedback.heavyImpact(),
    );
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// The real thing: the 28 s bed on repeat, plus the haptic pulse (OPH-180).
class AudioAlarmFeedback implements AlarmFeedback {
  AudioAlarmFeedback(this._sound, {this.asset = kAlarmSoundAsset});

  final AlarmSoundPlayer _sound;
  final String asset;
  final HapticAlarmFeedback _haptics = HapticAlarmFeedback();
  final ValueNotifier<bool> _blocked = ValueNotifier(false);

  @override
  ValueListenable<bool> get soundBlocked => _blocked;

  @override
  void start() {
    _haptics.start();
    unawaited(_startSound());
  }

  Future<void> _startSound() async {
    try {
      await _sound.loop(asset);
      _blocked.value = false;
    } on Object {
      // Honest degradation: haptics keep going, the screen offers "start
      // sound", and we never claim an alarm was audible when it was not.
      _blocked.value = true;
    }
  }

  @override
  void stop() {
    _haptics.stop();
    unawaited(_sound.stop());
  }

  Future<void> dispose() async {
    stop();
    _blocked.dispose();
    await _sound.dispose();
  }
}

class SilentAlarmFeedback implements AlarmFeedback {
  const SilentAlarmFeedback();

  @override
  ValueListenable<bool> get soundBlocked => _never;

  @override
  void start() {}

  @override
  void stop() {}
}

/// A const-friendly "never blocked" listenable for [SilentAlarmFeedback].
final ValueNotifier<bool> _never = ValueNotifier<bool>(false);

/// How the alarm makes noise. Tests override with [SilentAlarmFeedback] (see
/// `test/support/sync_overrides.dart`) so no audio plugin or haptic timer
/// outlives a test body.
final alarmFeedbackProvider = Provider<AlarmFeedback>((ref) {
  final feedback = AudioAlarmFeedback(AudioPlayersAlarmSound());
  ref.onDispose(() => unawaited(feedback.dispose()));
  return feedback;
});
