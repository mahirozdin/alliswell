import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds a ring surface when the wall-clock minute changes (W-03).
///
/// Every snooze label on the ring screen ("5 dk · 09:05’te çalar") is
/// `snoozeUntilFor(preset, now)` printed to the minute, and the tap writes the
/// same function of the clock at the press. A label built once went stale the
/// moment the minute rolled over: it said 09:05 while the tap wrote 09:06. So
/// the surface rebuilds on a timer armed for the next minute's first instant,
/// and again when the app comes back to the foreground (a suspended app's
/// timers do not fire), and the label always states what a tap would write.
///
/// [minuteClock] is the same clock the labels and the press read.
mixin AlarmMinuteTick<T extends StatefulWidget> on State<T> {
  DateTime Function() get minuteClock;

  Timer? _minuteTimer;
  _MinuteResumeObserver? _resume;

  @override
  void initState() {
    super.initState();
    _resume = _MinuteResumeObserver(_onMinute);
    WidgetsBinding.instance.addObserver(_resume!);
    _armMinute();
  }

  void _armMinute() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer(alarmUntilNextMinute(minuteClock()), _onMinute);
  }

  void _onMinute() {
    if (!mounted) return;
    setState(() {});
    _armMinute();
  }

  /// Cancels the minute timer and the resume observer; safe to call twice.
  /// A host's `dispose()` calls it first, before anything that could throw,
  /// so a failing dispose never leaves the timer pending.
  void stopMinuteTick() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
    final resume = _resume;
    _resume = null;
    if (resume != null) WidgetsBinding.instance.removeObserver(resume);
  }

  @override
  void dispose() {
    stopMinuteTick();
    super.dispose();
  }
}

/// The wait from [now] to the first instant of the next wall-clock minute —
/// never zero, so a timer that fires a hair early re-arms instead of spinning.
Duration alarmUntilNextMinute(DateTime now) {
  final into = now.millisecondsSinceEpoch % Duration.millisecondsPerMinute;
  return Duration(milliseconds: Duration.millisecondsPerMinute - into);
}

class _MinuteResumeObserver with WidgetsBindingObserver {
  _MinuteResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
