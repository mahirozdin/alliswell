import 'package:flutter/widgets.dart';

/// How much of the bottom edge the shell's floating buttons cover (OPH-359,
/// UI-AUDIT #58).
///
/// The shell draws its FABs — create on the right, the AI microphone on the
/// left — over the content of whatever screen sits in a section. A list that
/// does not know they are there ends under them: the last card, an empty
/// state's sentence, the performance board's last unit. Screens used to pass
/// `extraBottom: 72` one by one and the ones pushed INTO a section (the SLA
/// dashboard, the performance board) never did.
///
/// The shell says it once, here, and `awListPadding` reads it — so every list
/// inside the shell clears the buttons, and a screen on the root navigator
/// (where no shell FAB floats) pays nothing.
class AwFabClearance extends InheritedWidget {
  const AwFabClearance({super.key, required this.extent, required super.child});

  /// The height to keep clear above the bottom inset; 0 when no FAB shows.
  final double extent;

  /// The FAB lane's height: a 56 px button plus Material's 16 px margin.
  static const double lane = 72;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AwFabClearance>()?.extent ?? 0;

  @override
  bool updateShouldNotify(AwFabClearance oldWidget) =>
      oldWidget.extent != extent;
}
