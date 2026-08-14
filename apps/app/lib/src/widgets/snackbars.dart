import 'package:flutter/material.dart';

/// The app's only door to a snackbar that carries an action (OPH-257).
///
/// **Why this exists.** Flutter 3.44's `SnackBar` constructor ends with
/// `persist = persist ?? action != null` — so a bar with a button opts *out* of
/// its own timeout by default. `ScaffoldMessengerState.build` arms one timer,
/// that timer fires, sees `persist`, returns without hiding anything, and is
/// never re-armed (the `_snackBarTimer == null` guard). The result is a bar
/// that stays until the user swipes it away, which is exactly what the owner
/// reported twice — on web and on mobile — and what feedback round 13 tried to
/// fix by shortening a duration the bar was never reading.
///
/// Every action bar in this app therefore has to say `persist: false` out loud.
/// Rather than trust four call sites to remember a defaulted-on flag, they all
/// come through here: the flag lives in one place, with the reason attached.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAwActionSnackBar(
  ScaffoldMessengerState messenger, {
  Key? key,
  required Widget content,
  required String actionLabel,
  required VoidCallback onAction,
  Duration duration = const Duration(seconds: 4),
}) => messenger.showSnackBar(
  SnackBar(
    key: key,
    content: content,
    // The whole point of this file. Guarded by test/widgets/snackbars_test.dart
    // — removing this line turns that test red.
    persist: false,
    duration: duration,
    action: SnackBarAction(label: actionLabel, onPressed: onAction),
  ),
);
