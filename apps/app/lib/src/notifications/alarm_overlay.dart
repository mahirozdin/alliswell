import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tasks/providers.dart';
import 'alarm_sound.dart';
import '../core/persisted_prefs.dart';
import 'alarm_log.dart';
import 'alarmkit.dart';
import 'alarmkit_identity.dart';
import 'planner.dart';
import 'reminder_profile.dart';
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

/// Every alarm that may fire for the signed-in person (reminder rows ⋈ tasks
/// + synthetic task-derived alarms — see [ReminderStore.watchAlarmsIn]), over
/// the same [taskScopeProvider] Home reads. Public so a container test can
/// await the first emission.
final alarmFeedProvider = StreamProvider.autoDispose<List<AlarmInput>>((
  ref,
) async* {
  // Awaited, not read: "no alarms" while the scope is still loading would be
  // an answer, and the ring decision would act on it.
  final scope = await ref.watch(taskScopeProvider.selectAsync((s) => s));
  if (scope == null) {
    yield const <AlarmInput>[];
    return;
  }
  yield* ref.watch(reminderStoreProvider).watchAlarmsIn(scope);
});

/// Effective fire instant: a snoozed alarm fires at [AlarmInput.snoozedUntil],
/// otherwise at [AlarmInput.remindAt] — the exact base the planner schedules on
/// (`planNotifications`), so the overlay and the OS notification agree.
DateTime alarmFireAt(AlarmInput a) =>
    (a.status == 'snoozed' ? a.snoozedUntil : null) ?? a.remindAt;

/// How long after its instant an urgent alarm is still "ringing" (round 19 #2).
///
/// [ringingAlarm] had no lower bound at all: any urgent alarm whose instant had
/// passed counted as ringing, forever. Open the app three days later and an
/// alarm from Tuesday seized the screen and sounded the bed — which is exactly
/// the report ("a long-gone alarm suddenly goes off in red"), and it made the
/// real failure worse by looking like the alarm had finally worked.
///
/// The window is DERIVED from the user's own chain rather than being a
/// constant: an `insistent` profile re-alerts up to 40 minutes after the
/// instant, and a flat 15-minute window would have declared an alarm "missed"
/// while the OS was still ringing it. Five minutes of slack past the last slot,
/// never less than [_kMinStaleWindow].
const Duration _kMinStaleWindow = Duration(minutes: 15);

Duration alarmStaleWindowFor(ReminderProfile profile) {
  final last = profile.slots.isEmpty ? 0 : profile.slots.last;
  final derived = Duration(minutes: last + 5);
  return derived < _kMinStaleWindow ? _kMinStaleWindow : derived;
}

/// The window the overlay uses, and the one the user can override.
final alarmStaleWindowProvider = Provider<Duration>((ref) {
  final override = int.tryParse(ref.watch(alarmStaleWindowRawProvider));
  if (override != null && override > 0) return Duration(minutes: override);
  return alarmStaleWindowFor(ref.watch(reminderProfileProvider));
});

/// The URGENT alarm that should be ringing at [now] (earliest fire first), or
/// null. Only urgent alarms take over the screen (BLUEPRINT §8.2); normal
/// reminders stay in the OS tray. Pure — the DoD's "fake clock" is just [now].
///
/// [staleAfter] bounds it from below; see [alarmStaleWindowFor].
AlarmInput? ringingAlarm(
  List<AlarmInput> alarms,
  DateTime now, {
  Duration staleAfter = _kMinStaleWindow,
}) {
  AlarmInput? best;
  DateTime? bestAt;
  final floor = now.subtract(staleAfter);
  for (final a in alarms) {
    if (!a.urgent) continue;
    final at = alarmFireAt(a);
    if (at.isAfter(now)) continue;
    // Too long ago to be "ringing". It is not forgotten — see [missedAlarms].
    if (at.isBefore(floor)) continue;
    if (best == null || at.isBefore(bestAt!)) {
      best = a;
      bestAt = at;
    }
  }
  return best;
}

/// How far back a missed alarm is still worth a card.
///
/// Found by a test rather than reasoned out in advance, which is the honest
/// way to record it: without a bound, an urgent task overdue since March showed
/// a "missed alarm" card forever, and `tasks_flow_test` caught it as a
/// duplicated title on Home.
///
/// The card answers *"did I sleep through something?"* — a question with a
/// short shelf life. "What is overdue?" is a different question and the task
/// list already answers it; mirroring it here would be the same information in
/// two places, one of which never clears (§22's dead affordance, in card form).
const Duration kMissedAlarmLookBack = Duration(hours: 24);

/// Urgent alarms whose moment passed long enough ago that they are history
/// rather than an emergency — newest first.
///
/// The other half of the fix. Silently swallowing them would trade one wrong
/// behaviour for another: the user still needs to know last night's alarm was
/// never answered. They just should not be woken by it this morning.
List<AlarmInput> missedAlarms(
  List<AlarmInput> alarms,
  DateTime now, {
  Duration staleAfter = _kMinStaleWindow,
  Duration lookBack = kMissedAlarmLookBack,
}) {
  final ceiling = now.subtract(staleAfter);
  final floor = now.subtract(lookBack);
  final missed = [
    for (final a in alarms)
      if (a.urgent &&
          alarmFireAt(a).isBefore(ceiling) &&
          !alarmFireAt(a).isBefore(floor))
        a,
  ];
  missed.sort((a, b) => alarmFireAt(b).compareTo(alarmFireAt(a)));
  return missed;
}

/// The stale alarms for the signed-in workspace, ready for Home's card.
final missedAlarmsProvider = Provider<List<AlarmInput>>((ref) {
  final alarms = ref.watch(alarmFeedProvider).value ?? const <AlarmInput>[];
  return missedAlarms(
    alarms,
    ref.read(alarmClockProvider)(),
    staleAfter: ref.watch(alarmStaleWindowProvider),
  );
});

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

/// The identity of one ringing OCCURRENCE: the task plus the instant it fires
/// at (#46). Keyed on the instant, not on the reminder, so a snoozed alarm is a
/// new occurrence and rings again at its `snoozedUntil` in the same session —
/// a reminder-keyed "already handled" set swallowed it until the app restarted.
/// The shell keys the ring screen with it, so a different alarm never inherits
/// the previous screen's state.
String alarmOccurrenceKey(AlarmInput a) =>
    '${a.taskId}|${alarmFireAt(a).millisecondsSinceEpoch}';

/// A write the ring screen started that has to be repeatable: "Tekrar dene"
/// runs the same thing again (#46).
class AlarmPendingAction {
  const AlarmPendingAction(this.write, {this.onSaved});

  /// The store call: acknowledge, snooze, complete, mute.
  final Future<void> Function() write;

  /// What to say once it landed (the snooze confirmation) — never before.
  final void Function()? onSaved;
}

/// What the shell needs to know: the alarms ringing now, and whether this
/// device stays quiet while they do.
class AlarmOverlayState {
  const AlarmOverlayState({
    this.ringing = const [],
    this.silentHere = false,
    this.ringsOnLockScreen = false,
    this.failed = const {},
  });

  /// One element in this wave; the minute's whole group later (ADR-0068).
  final List<AlarmInput> ringing;

  /// The alarm shows here without the in-app sound: a browser set to
  /// Silent, or [ringsOnLockScreen].
  final bool silentHere;

  /// The shown occurrence already rings as an AlarmKit alert (iOS 26+, #46):
  /// the system owns the sound, so the app adds none of its own.
  final bool ringsOnLockScreen;

  /// Occurrences shown again because the write behind an action failed.
  final Set<String> failed;

  bool isFailed(AlarmInput a) => failed.contains(alarmOccurrenceKey(a));
}

/// Drives the foreground ring overlay (OPH-143). Watches the alarm feed plus a
/// foreground timer wheel (NOTIFICATIONS.md §3) so an urgent alarm that comes
/// due WHILE the app is open rings without waiting for a DB emission. The OS
/// notification (OPH-139) stays the primary channel; this is the surface while
/// the app is open, and desktop/web's ONLY alarm surface.
///
/// It is also the ONLY owner of the in-app sound ([AlarmFeedback], #46). The
/// ring screen used to start the bed in `initState` and stop it in `dispose`:
/// when one alarm's screen gave way to the next, the old screen's `dispose`
/// stopped the sound the new one had just started on the shared player. Now
/// the sound follows the occurrences: a newly shown one starts it, an empty
/// overlay and every [silence] / [handled] stop it.
class AlarmOverlayController extends Notifier<AlarmOverlayState> {
  Timer? _timer;

  /// Occurrences the user just acted on: hide immediately and don't re-ring
  /// before the write lands (and, for an offline synthetic acknowledge that
  /// no-ops, at all). Keyed by [alarmOccurrenceKey]; cleared once that
  /// occurrence leaves the feed.
  final Set<String> _handled = {};

  /// Occurrences that have been shown once — their sound was started then (or
  /// deliberately not). A re-shown occurrence never starts it again.
  final Set<String> _announced = {};

  /// Occurrences whose write failed, with the action "Tekrar dene" repeats.
  final Map<String, AlarmPendingAction> _failures = {};

  AlarmFeedback? _feedback;
  bool _sounding = false;

  /// Whether the in-app sound is playing right now.
  bool get sounding => _sounding;

  /// The ring screen's "the platform refused to play" signal (OPH-180).
  ValueListenable<bool> get soundBlocked => _sound().soundBlocked;

  // Read lazily: a screen that never rings never creates an audio player.
  AlarmFeedback _sound() {
    final existing = _feedback;
    if (existing != null) return existing;
    final AlarmFeedback created = ref.read(alarmFeedbackProvider);
    _feedback = created;
    return created;
  }

  DateTime _now() => ref.read(alarmClockProvider)();

  List<AlarmInput> _feed() =>
      ref.read(alarmFeedProvider).value ?? const <AlarmInput>[];

  @override
  AlarmOverlayState build() {
    // Only the timer here: build re-runs on every feed emission, and stopping
    // the sound in onDispose would cut it on each of them.
    ref.onDispose(() => _timer?.cancel());
    // A pass that scheduled, or an action that stopped, an AlarmKit alarm
    // changes who owns the sound of what is showing.
    ref.watch(alarmKitViewProvider);
    if (!ref.watch(alarmOverlayAutoShowProvider)) {
      return AlarmOverlayState(silentHere: ref.read(alarmOpensSilentProvider));
    }
    return _evaluate(ref.watch(alarmFeedProvider).value ?? const []);
  }

  AlarmOverlayState _evaluate(List<AlarmInput> alarms) {
    _timer?.cancel();
    final silentHere = ref.read(alarmOpensSilentProvider);
    if (!ref.read(alarmOverlayAutoShowProvider)) {
      return AlarmOverlayState(silentHere: silentHere);
    }
    // Drop keys whose occurrence has left the feed: a snoozed alarm is a new
    // occurrence, so it rings again at its new instant.
    final present = {for (final a in alarms) alarmOccurrenceKey(a)};
    _handled.retainWhere(present.contains);
    _announced.retainWhere(present.contains);
    _failures.removeWhere((key, _) => !present.contains(key));

    final now = _now();
    final live = alarms
        .where((a) => !_handled.contains(alarmOccurrenceKey(a)))
        .toList();
    final shown =
        ringingAlarm(
          live,
          now,
          staleAfter: ref.read(alarmStaleWindowProvider),
        ) ??
        // A failed write brings its alarm back even when it was opened from
        // the missed card, outside the ring window: say it, never lose it.
        live
            .where((a) => _failures.containsKey(alarmOccurrenceKey(a)))
            .firstOrNull;

    if (shown == null) {
      if (_sounding) _stopSound();
      final next = nextUrgentFireAfter(live, now);
      if (next != null) {
        final wait = next.difference(now);
        _timer = Timer(wait.isNegative ? Duration.zero : wait, _tick);
      }
      return AlarmOverlayState(silentHere: silentHere);
    }

    final key = alarmOccurrenceKey(shown);
    final failed = _failures.containsKey(key);
    // iOS 26+: the system alert already rings this occurrence; a second,
    // in-app sound on top of it is the #46 screenshot.
    final onLockScreen = _covering(shown).isNotEmpty;
    if (onLockScreen && _sounding) _stopSound();
    final quiet = silentHere || onLockScreen;
    if (_announced.add(key) && !failed && !quiet && !_sounding) {
      // A newly shown occurrence. A re-shown failed one stays quiet: its
      // sound comes back only through the no-interaction rule, never here.
      _sound().start();
      _sounding = true;
    }
    return AlarmOverlayState(
      ringing: [shown],
      silentHere: quiet,
      ringsOnLockScreen: onLockScreen,
      failed: failed ? {key} : const {},
    );
  }

  void _tick() => state = _evaluate(_feed());

  void _stopSound() {
    _feedback?.stop();
    _sounding = false;
  }

  /// Stop the in-app sound now, synchronously — the first thing every ring
  /// screen action does, before any await.
  void silence() => _stopSound();

  List<AlarmKitScheduled> _covering(AlarmInput alarm) =>
      alarmKitCovering(ref.read(alarmKitViewProvider), alarm);

  /// Whether [alarm]'s occurrence rings as an AlarmKit alert right now.
  bool ringsOnLockScreen(AlarmInput alarm) => _covering(alarm).isNotEmpty;

  /// Stop the AlarmKit alert of [alarm]'s occurrence (#46, iOS 26+) — every
  /// ring screen action calls it right after [silence], so answering in the
  /// app answers the system alert too. Fire-and-forget: the dismissal never
  /// waits for the bridge, and a failed stop is only logged. Nothing to stop
  /// (no AlarmKit here, or the occurrence is not on it) is a no-op.
  void stopAlarmKit(AlarmInput alarm) {
    final covering = _covering(alarm);
    if (covering.isEmpty) return;
    final host = ref.read(alarmKitHostProvider);
    AlarmLog? log;
    try {
      log = ref.read(alarmLogProvider);
    } on Object {
      // No database on this surface: the stop still goes out.
    }
    final view = ref.read(alarmKitViewProvider.notifier);
    for (final row in covering) {
      view.remove(row.id);
      unawaited(_stopAlarmKit(host, log, row, alarm));
    }
  }

  Future<void> _stopAlarmKit(
    AlarmKitHost host,
    AlarmLog? log,
    AlarmKitScheduled row,
    AlarmInput alarm,
  ) async {
    String? error;
    try {
      final result = await host.stop(row.id);
      error = result.error;
    } on Object catch (e) {
      error = '$e';
    }
    if (error == null) return;
    try {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        urgent: true,
        fireAt: alarmFireAt(alarm),
        taskId: alarm.taskId,
        reminderId: alarm.reminderId,
        detail: 'in-app stop of alarm ${row.id} failed: $error',
      );
    } on Object {
      // A diagnostic never fails an action.
    }
  }

  /// Start the in-app sound on request: the screen's "Sesi başlat", and a
  /// custom snooze whose pickers were cancelled.
  void startSound() {
    _sound().start();
    _sounding = true;
  }

  /// The ring screen calls this the moment the user acts: silence, dismiss;
  /// the feed confirms a beat later.
  void handled(AlarmInput alarm) {
    final key = alarmOccurrenceKey(alarm);
    _handled.add(key);
    _failures.remove(key);
    silence();
    state = _evaluate(_feed());
  }

  /// Await [action]'s write after the screen closed. True when it landed; on
  /// a throw the occurrence comes back with the error and stays silent
  /// (decision K-01: say it, the alarm comes back) — no snackbar.
  Future<bool> commit(AlarmInput alarm, AlarmPendingAction action) async {
    try {
      await action.write();
    } on Object catch (e) {
      debugPrint('alarm action failed: $e');
      final key = alarmOccurrenceKey(alarm);
      _handled.remove(key);
      _failures[key] = action;
      state = _evaluate(_feed());
      return false;
    }
    action.onSaved?.call();
    return true;
  }

  /// The action "Tekrar dene" repeats for [alarm], if its write failed.
  AlarmPendingAction? failedAction(AlarmInput alarm) =>
      _failures[alarmOccurrenceKey(alarm)];
}

/// The AlarmKit records in [view] that ring [alarm]'s occurrence (#46): a
/// scheduled or alerting alarm whose members hold the task and whose instant
/// is the occurrence's, floored to the second as the bridge stores it.
List<AlarmKitScheduled> alarmKitCovering(
  List<AlarmKitScheduled> view,
  AlarmInput alarm,
) {
  final fireAtMs = alarmKitFireAtMs(alarmFireAt(alarm));
  return [
    for (final row in view)
      if ((row.state == AlarmKitAlarmState.scheduled ||
              row.state == AlarmKitAlarmState.alerting) &&
          row.fireAtMs == fireAtMs &&
          row.members.contains(alarm.taskId))
        row,
  ];
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
