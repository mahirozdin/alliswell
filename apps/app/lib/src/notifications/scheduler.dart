import 'dart:async';

import 'planner.dart';
import 'gateway.dart';

/// Keeps the OS notification schedule equal to the plan (OPH-061): every
/// replica change re-plans (window ≤[maxPending], urgent chains) and the diff
/// is applied as cancel-the-extras + schedule-the-missing — ids are content
/// hashes, so any change reschedules and convergence is idempotent. Alarms
/// disappear from the plan when acknowledged/completed/cancelled (their rows
/// leave the active set), which cancels their remaining chain.
class NotificationScheduler {
  NotificationScheduler({
    required this.gateway,
    required this.alarms,
    required this.privacyMode,
    this.maxPending = 40,
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc());

  final NotificationsGateway gateway;
  final Stream<List<AlarmInput>> alarms;
  final bool privacyMode;
  final int maxPending;
  final DateTime Function() _now;

  StreamSubscription<List<AlarmInput>>? _subscription;
  List<AlarmInput> _latest = const [];
  bool _applying = false;
  bool _reapplyWanted = false;
  bool _stopped = false;

  /// Permission refusals and platform-channel absence (widget tests, web)
  /// must never break the app — notifications degrade, tasks keep working.
  Future<void> start() async {
    try {
      await gateway.initialize();
      await gateway.requestPermissions();
    } catch (_) {
      return; // no notification surface here — stay dormant
    }
    _subscription = alarms.listen((list) {
      _latest = list;
      unawaited(_apply());
    });
  }

  void dispose() {
    _stopped = true;
    unawaited(_subscription?.cancel());
  }

  Future<void> _apply() async {
    if (_stopped) return;
    if (_applying) {
      _reapplyWanted = true;
      return;
    }
    _applying = true;
    try {
      final desired = planNotifications(
        alarms: _latest,
        now: _now(),
        privacyMode: privacyMode,
        maxPending: maxPending,
      );
      final desiredById = {for (final n in desired) n.id: n};
      final pending = await gateway.pendingIds();

      for (final id in pending.difference(desiredById.keys.toSet())) {
        await gateway.cancel(id);
      }
      for (final id in desiredById.keys.toSet().difference(pending)) {
        await gateway.schedule(desiredById[id]!);
      }
    } catch (_) {
      // Transient plugin failures self-heal on the next replica change.
    } finally {
      _applying = false;
    }
    if (_reapplyWanted && !_stopped) {
      _reapplyWanted = false;
      await _apply();
    }
  }
}
