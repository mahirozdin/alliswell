import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a deleted row stays takeable-back before the delete is really
/// performed (OPH-184, DESIGN §19 D4). Matches the undo snackbar's lifetime.
///
/// Three seconds, not five (feedback round 13): the bar has to outlive the
/// swipe animation and a glance, and nothing more. Five seconds of a control
/// the user has already decided against reads as the app arguing with them —
/// and it sits over the list they went back to using.
const Duration kAwUndoWindow = Duration(seconds: 3);

/// Overridable so widget tests need not wait out a real five seconds — and so
/// a test that WANTS to observe the commit can shorten it deliberately.
final undoWindowProvider = Provider<Duration>((_) => kAwUndoWindow);

/// Rows the user deleted but can still take back.
///
/// DESIGN §19 D4: **undo means the mutation has not happened yet.** The row is
/// hidden from every list the moment the user taps Delete, but nothing is
/// written — not to the replica, not to the outbox — until the window closes.
/// Two consequences we want:
///
///  * Undo cannot lose anything. There is no re-creation step, so tags,
///    checklist items, attachments and the record's own id are never at risk.
///  * If the app is killed inside the window, **nothing was deleted.** That is
///    the safe direction for a destructive action, and it is why the timer
///    lives here rather than inside a row widget: a row scrolled out of view is
///    disposed, which would either resurrect the row or strand its timer.
class PendingDeletes extends Notifier<Set<String>> {
  final Map<String, Timer> _timers = {};
  final Map<String, Future<void> Function()> _commits = {};

  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _commits.clear();
    });
    return const {};
  }

  /// Hide [id] now; run [commit] when the undo window closes.
  ///
  /// Scheduling the same id twice commits nothing twice — the previous timer is
  /// replaced, so a double-tap cannot enqueue two deletes.
  void schedule(
    String id,
    Future<void> Function() commit, {
    required Duration window,
  }) {
    _timers.remove(id)?.cancel();
    _commits[id] = commit;
    _timers[id] = Timer(window, () => _commit(id));
    state = {...state, id};
  }

  /// Take it back: the row returns and [commit] never runs.
  void undo(String id) {
    _timers.remove(id)?.cancel();
    _commits.remove(id);
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
  }

  /// Commit early — used when the user leaves the surface that offered the undo.
  /// Safe to call for an id that is not pending.
  void commitNow(String id) {
    if (!_timers.containsKey(id)) return;
    _timers.remove(id)!.cancel();
    _commit(id);
  }

  bool isPending(String id) => state.contains(id);

  void _commit(String id) {
    _timers.remove(id);
    final commit = _commits.remove(id);
    // The id stays hidden: the commit removes the row for real, and dropping it
    // from `state` first would flash the row back for one frame.
    if (commit == null) return;
    unawaited(
      commit().catchError((Object _) {
        // A failed delete must not leave a permanently invisible row.
        undo(id);
      }),
    );
  }
}

final pendingDeletesProvider = NotifierProvider<PendingDeletes, Set<String>>(
  PendingDeletes.new,
);

/// Drops rows that are pending deletion from a list.
///
/// Row widgets hide themselves (`AwSwipeToDelete`), but a grouped list also
/// computes headers and counts from the raw list — so the surfaces that group
/// filter first, or a group would render a header above nothing.
List<T> awWithoutPending<T>(
  List<T> items,
  Set<String> pending,
  String Function(T) idOf,
) => pending.isEmpty
    ? items
    : [
        for (final item in items)
          if (!pending.contains(idOf(item))) item,
      ];
