import 'dart:async';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/workspaces/workspaces.dart';
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
/// (no pending timers, no platform channels). Today: haptic pulses. A looping
/// AUDIO bed rides the device audio tour (no in-Dart player yet — on mobile the
/// OS notification already carries the 28 s bed; NOTIFICATIONS.md §3).
abstract class AlarmFeedback {
  void start();
  void stop();
}

class HapticAlarmFeedback implements AlarmFeedback {
  Timer? _timer;

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

class SilentAlarmFeedback implements AlarmFeedback {
  const SilentAlarmFeedback();

  @override
  void start() {}

  @override
  void stop() {}
}

final alarmFeedbackProvider = Provider<AlarmFeedback>((ref) {
  final feedback = HapticAlarmFeedback();
  ref.onDispose(feedback.stop);
  return feedback;
});
