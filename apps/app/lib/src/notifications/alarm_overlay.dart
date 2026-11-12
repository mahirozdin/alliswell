import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ulid.dart';
import '../features/tasks/providers.dart';
import '../sync/providers.dart';
import 'actions.dart';
import 'alarm_sound.dart';
import '../core/persisted_prefs.dart';
import 'alarm_log.dart';
import 'alarmkit.dart';
import 'alarmkit_identity.dart';
import 'gateway.dart';
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

/// Every URGENT alarm ringing at [now], earliest fire first (#47): the ring
/// screen lists all of them — the minute's group, older data that landed in
/// it, an alarm synced from another device — under one sound. Only urgent
/// alarms take over the screen (BLUEPRINT §8.2); normal reminders stay in the
/// OS tray. Pure — the DoD's "fake clock" is just [now].
///
/// [staleAfter] bounds it from below; see [alarmStaleWindowFor].
List<AlarmInput> ringingAlarms(
  List<AlarmInput> alarms,
  DateTime now, {
  Duration staleAfter = _kMinStaleWindow,
}) {
  final floor = now.subtract(staleAfter);
  final ringing = [
    for (final a in alarms)
      // Too long ago to be "ringing" is not forgotten — see [missedAlarms].
      if (a.urgent &&
          !alarmFireAt(a).isAfter(now) &&
          !alarmFireAt(a).isBefore(floor))
        a,
  ];
  ringing.sort(_byFireAt);
  return ringing;
}

/// Earliest fire first; ties in a fixed order so the list never reshuffles.
int _byFireAt(AlarmInput a, AlarmInput b) {
  final at = alarmFireAt(a).compareTo(alarmFireAt(b));
  if (at != 0) return at;
  final task = a.taskId.compareTo(b.taskId);
  return task != 0 ? task : a.reminderId.compareTo(b.reminderId);
}

/// The earliest of [ringingAlarms], or null.
AlarmInput? ringingAlarm(
  List<AlarmInput> alarms,
  DateTime now, {
  Duration staleAfter = _kMinStaleWindow,
}) => ringingAlarms(alarms, now, staleAfter: staleAfter).firstOrNull;

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

  /// Every urgent alarm ringing now, earliest first (#47, ADR-0068); the
  /// ring screen shows one, or the list when there are several.
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

/// How long the ring screen may sit silent with rows left before its sound
/// comes back (#47, decisions §3.1, DESIGN §11 A3 insistence): the first
/// action silences the list, a minute without interaction resumes it.
const Duration kAlarmResumeAfter = Duration(seconds: 60);

/// One ring-screen action on a row or on the whole list (#47).
class AlarmRowAction {
  const AlarmRowAction._(this.actionId) : until = null;

  /// Snooze to [until], written unchanged (floored to the second).
  const AlarmRowAction.snooze(DateTime this.until) : actionId = 'snooze';

  static const acknowledge = AlarmRowAction._(kActionAcknowledge);
  static const complete = AlarmRowAction._(kActionComplete);
  static const mute = AlarmRowAction._(kActionMute);

  /// The [NotificationEvent.actionId]: `snooze`, `acknowledge`, `complete`
  /// or `mute`.
  final String actionId;
  final DateTime? until;
}

/// Applies one in-app action event (#47): [handleNotificationEvent] with the
/// event's receipt (OPH-427/439), so a group action is one transaction with
/// one outbox mutation per member. A seam, so tests can record the events.
final alarmActionApplierProvider =
    Provider<Future<bool> Function(NotificationEvent)>((ref) {
      return (event) {
        AlarmLog? log;
        try {
          log = ref.read(alarmLogProvider);
        } on Object {
          // No log on this surface: the action still applies.
        }
        return handleNotificationEvent(
          event,
          tasks: ref.read(taskStoreProvider),
          reminders: ref.read(reminderStoreProvider),
          navigate: (_) {},
          log: log,
          db: ref.read(databaseProvider),
        );
      };
    });

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
///
/// Several alarms ring as ONE list (#47): one sound for the whole list, an
/// alarm arriving while the screen is open joins it without a second start,
/// the first action silences it, and [kAlarmResumeAfter] without interaction
/// while rows remain brings the in-app sound back (never the AlarmKit alert).
class AlarmOverlayController extends Notifier<AlarmOverlayState> {
  Timer? _timer;

  /// The no-interaction rule's clock; reset by every interaction.
  Timer? _resumeTimer;

  /// Whether the last evaluation showed the screen: only opening it starts
  /// the sound, rows joining an open screen never do.
  bool _open = false;

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
    // Disposed for good, or rebuilt because the gate changed: the timers go
    // with it. The feed and the AlarmKit view are LISTENED to, not watched,
    // so their emissions re-evaluate without a rebuild — a rebuild would
    // cancel the no-interaction minute (#47) on every emission.
    ref.onDispose(() {
      _timer?.cancel();
      _resumeTimer?.cancel();
      _resumeTimer = null;
    });
    if (!ref.watch(alarmOverlayAutoShowProvider)) {
      return AlarmOverlayState(silentHere: ref.read(alarmOpensSilentProvider));
    }
    // A pass that scheduled, or an action that stopped, an AlarmKit alarm
    // changes who owns the sound of what is showing.
    ref.listen(alarmKitViewProvider, (_, _) => state = _evaluate(_feed()));
    ref.listen(
      alarmFeedProvider,
      (_, next) => state = _evaluate(next.value ?? const []),
    );
    return _evaluate(_feed());
  }

  AlarmOverlayState _evaluate(List<AlarmInput> alarms, {bool resume = false}) {
    _timer?.cancel();
    final silentHere = ref.read(alarmOpensSilentProvider);
    if (!ref.read(alarmOverlayAutoShowProvider)) {
      _close();
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
    final ringing = ringingAlarms(
      live,
      now,
      staleAfter: ref.read(alarmStaleWindowProvider),
    );
    final shownKeys = {for (final a in ringing) alarmOccurrenceKey(a)};
    // A failed write brings its alarm back even when it was opened from the
    // missed card, outside the ring window: say it, never lose it.
    final rows = [
      ...ringing,
      for (final a in live)
        if (_failures.containsKey(alarmOccurrenceKey(a)) &&
            !shownKeys.contains(alarmOccurrenceKey(a)))
          a,
    ]..sort(_byFireAt);

    // The wheel keeps turning while the screen is open: an alarm coming due
    // then joins the list.
    final next = nextUrgentFireAfter(live, now);
    if (next != null) {
      final wait = next.difference(now);
      _timer = Timer(wait.isNegative ? Duration.zero : wait, _tick);
    }

    if (rows.isEmpty) {
      if (_sounding) _stopSound();
      _close();
      return AlarmOverlayState(silentHere: silentHere);
    }

    final failed = {
      for (final a in rows)
        if (_failures.containsKey(alarmOccurrenceKey(a))) alarmOccurrenceKey(a),
    };
    // iOS 26+: the system alert already rings (part of) the list; a second,
    // in-app sound on top of it is the #46 screenshot.
    final onLockScreen = rows.any((a) => _covering(a).isNotEmpty);
    if (onLockScreen && _sounding) _stopSound();
    final quiet = silentHere || onLockScreen;
    final opening = !_open;
    _open = true;
    var fresh = false;
    for (final a in rows) {
      final key = alarmOccurrenceKey(a);
      if (_announced.add(key) && !failed.contains(key)) fresh = true;
    }
    if (!quiet && !_sounding && (resume || (opening && fresh))) {
      // The screen opens on a new alarm, or a minute passed untouched. A
      // re-shown failed one, and a row joining an open screen, stay quiet:
      // their sound comes back only through the no-interaction rule.
      _sound().start();
      _sounding = true;
    }
    if (quiet || _sounding) {
      _resumeTimer?.cancel();
      _resumeTimer = null;
    } else {
      _resumeTimer ??= Timer(kAlarmResumeAfter, _resume);
    }
    return AlarmOverlayState(
      ringing: rows,
      silentHere: quiet,
      ringsOnLockScreen: onLockScreen,
      failed: failed,
    );
  }

  void _tick() => state = _evaluate(_feed());

  void _resume() {
    _resumeTimer = null;
    state = _evaluate(_feed(), resume: true);
  }

  void _close() {
    _open = false;
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  /// The person touched the ring screen (a row, a sheet, a scroll): the
  /// no-interaction minute starts again.
  void interacted() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (_open && !_sounding) {
      _resumeTimer = Timer(kAlarmResumeAfter, _resume);
    }
  }

  void _stopSound() {
    _feedback?.stop();
    _sounding = false;
  }

  /// Stop the in-app sound now, synchronously — the first thing every ring
  /// screen action does, before any await. An interaction: if rows remain,
  /// the sound comes back after [kAlarmResumeAfter] untouched.
  void silence() {
    _stopSound();
    interacted();
  }

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
    // Never two in-app sounds at once: a playing bed is not started again
    // (a refused one is — that is what "Sesi başlat" is for).
    if (_sounding && !_sound().soundBlocked.value) return;
    _resumeTimer?.cancel();
    _resumeTimer = null;
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
  Future<bool> commit(AlarmInput alarm, AlarmPendingAction action) =>
      _commitAll([alarm], action);

  Future<bool> _commitAll(
    List<AlarmInput> alarms,
    AlarmPendingAction action,
  ) async {
    try {
      await action.write();
    } on Object catch (e) {
      debugPrint('alarm action failed: $e');
      for (final alarm in alarms) {
        final key = alarmOccurrenceKey(alarm);
        _handled.remove(key);
        _failures[key] = action;
      }
      state = _evaluate(_feed());
      return false;
    }
    action.onSaved?.call();
    return true;
  }

  /// One row's action (#47): [taskId]'s ringing occurrences. Silences the
  /// list, stops the AlarmKit alert covering the row, drops the row at once
  /// and applies ONE in-app event; the rest of the list stays. True when
  /// the write landed; a failed one brings the row back with its error.
  Future<bool> actOnRow(
    String taskId,
    AlarmRowAction action, {
    void Function()? onSaved,
  }) => _act(
    [
      for (final a in state.ringing)
        if (a.taskId == taskId) a,
    ],
    action,
    onSaved: onSaved,
  );

  /// "Tümünü ertele": every row to [until], one event, one batch (#47).
  Future<bool> snoozeAll(DateTime until, {void Function()? onSaved}) =>
      _act(state.ringing, AlarmRowAction.snooze(until), onSaved: onSaved);

  /// "Tümünü onayla": every row, one event (#47).
  Future<bool> acknowledgeAll({void Function()? onSaved}) =>
      _act(state.ringing, AlarmRowAction.acknowledge, onSaved: onSaved);

  Future<bool> _act(
    List<AlarmInput> rows,
    AlarmRowAction action, {
    void Function()? onSaved,
  }) {
    if (rows.isEmpty) return Future.value(false);
    // Silence → stop the system alert → dismiss, all before any await (#46).
    silence();
    for (final a in rows) {
      stopAlarmKit(a);
    }
    for (final a in rows) {
      final key = alarmOccurrenceKey(a);
      _handled.add(key);
      _failures.remove(key);
    }
    state = _evaluate(_feed());
    final event = _eventFor(rows, action);
    final apply = ref.read(alarmActionApplierProvider);
    // A retry re-sends the SAME event: a failed transaction rolled its
    // receipt back, and one that did land is a no-op the second time.
    return _commitAll(
      rows,
      AlarmPendingAction(() => apply(event), onSaved: onSaved),
    );
  }

  /// The in-app event for [rows] (NOTIFICATIONS §2b.3): origin `inapp`, a
  /// fresh id, the members de-duplicated in list order.
  NotificationEvent _eventFor(List<AlarmInput> rows, AlarmRowAction action) {
    final members = <String>{for (final a in rows) a.taskId}.toList();
    final minutes = {
      for (final a in rows) alarmFireAt(a).millisecondsSinceEpoch ~/ 60000,
    };
    final until = action.until;
    return NotificationEvent(
      eventId: newUlid(),
      actionId: action.actionId,
      taskIds: members,
      untilMs: until == null
          ? null
          : until.millisecondsSinceEpoch ~/ 1000 * 1000,
      // One minute names the occurrence; rows from several minutes leave it
      // out, and every member's urgent reminder due by the press is the one
      // that rang.
      occurrenceFireAtMs: minutes.length == 1
          ? alarmFireAt(rows.first).millisecondsSinceEpoch
          : null,
      pressedAtMs: _now().toUtc().millisecondsSinceEpoch,
      origin: 'inapp',
      lane: AlarmLogLane.inapp,
    );
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
