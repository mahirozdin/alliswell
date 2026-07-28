import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The start of the current local day, re-emitted when that day changes.
///
/// OPH-185 (DESIGN §20 C1): a task completed today stays on the planning lists
/// until the next local midnight. That boundary has to be **live** — a phone
/// left on the Home screen overnight, or woken after a long sleep, must not
/// keep yesterday's finished work on today's list.
///
/// Two things make it live, and both are needed:
///
///  * a timer armed for the next midnight (plus a second of slack, so a timer
///    that fires a hair early cannot compute *yesterday* and immediately
///    re-arm for a boundary that has already passed);
///  * an app-lifecycle listener, because a suspended app's timers do not fire —
///    the device can sleep through midnight entirely and the first honest
///    moment to notice is when the user comes back.
///
/// A clock or timezone change lands on the same two paths: the next tick
/// recomputes from `DateTime.now()` rather than from the previous value.
DateTime awStartOfDay(DateTime now) => DateTime(now.year, now.month, now.day);

/// Injectable clock so tests can drive the boundary without waiting for
/// real midnight (the OPH-143 "fake clock" idiom).
final nowProvider = Provider<DateTime Function()>((_) => DateTime.now);

final dayBoundaryProvider = StreamProvider<DateTime>((ref) {
  final now = ref.watch(nowProvider);
  final controller = StreamController<DateTime>();
  Timer? timer;
  var current = awStartOfDay(now());

  void emit() {
    final start = awStartOfDay(now());
    if (start != current) {
      current = start;
      if (!controller.isClosed) controller.add(start);
    }
  }

  void schedule() {
    timer?.cancel();
    final at = now();
    final nextMidnight = DateTime(at.year, at.month, at.day + 1);
    timer = Timer(nextMidnight.difference(at) + const Duration(seconds: 1), () {
      emit();
      schedule();
    });
  }

  final observer = _ResumeObserver(emit);
  WidgetsBinding.instance.addObserver(observer);
  schedule();
  controller.add(current);

  ref.onDispose(() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(observer);
    controller.close();
  });
  return controller.stream;
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
