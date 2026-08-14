import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a deleted row stays takeable-back before the delete is really
/// performed (OPH-184, DESIGN §19 D4). Matches the undo snackbar's lifetime.
///
/// Three seconds, not five (feedback round 13): the bar has to outlive the
/// swipe animation and a glance, and nothing more. Five seconds of a control
/// the user has already decided against reads as the app arguing with them —
/// and it sits over the list they went back to using.
///
/// Worth knowing (OPH-257): shortening this in round 13 did **nothing** to the
/// complaint it was answering. The bar was ignoring its duration entirely —
/// see `widgets/snackbars.dart`. This constant only ever governed the commit.
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
  ///
  /// Returns whether there was still something to take back. False means the
  /// window had already closed and the delete is written — the caller must say
  /// so rather than let the tap look like it worked (OPH-257: the old signature
  /// returned nothing, so a stale Undo button was a silent no-op).
  bool undo(String id) {
    final cancelled = _commits.remove(id) != null;
    _timers.remove(id)?.cancel();
    if (state.contains(id)) state = {...state}..remove(id);
    return cancelled;
  }

  /// Commit early, because the undo has left the screen.
  ///
  /// The bar that offers the window is the only thing the user can see of it,
  /// so when the bar goes — timed out, swiped away, cleared by the next delete
  /// — the delete it described stops being provisional. The backstop timer
  /// stays for the case where there is no bar at all (OPH-257 wired this; it
  /// had been written in round 10 and never called).
  ///
  /// Safe for an id that is not pending, and for an id already committed: a
  /// delete pushed twice is a real bug, and the `closed` future and the timer
  /// genuinely race.
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
