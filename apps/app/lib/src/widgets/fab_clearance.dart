import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How much of the bottom edge the shell's floating buttons cover (OPH-359,
/// UI-AUDIT #58).
///
/// The shell draws its action cluster — the AI microphone beside create, on
/// the right (OPH-397) — over the content of whatever screen sits in a section. A list that
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

  /// The FAB lane's height: a 56 px button plus Material's 16 px margin —
  /// the microphone (48) is centred on the same line, so the cluster is no
  /// taller. A list therefore ends bar + this + 24 (`awListPadding`).
  static const double lane = 72;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AwFabClearance>()?.extent ?? 0;

  @override
  bool updateShouldNotify(AwFabClearance oldWidget) =>
      oldWidget.extent != extent;
}

/// How far up from the screen's bottom edge the phone's Quick Access bubble
/// reaches (UI-AUDIT #57, retest).
///
/// The bubble floats over the shell (never a pushed page, OPH-397), at the
/// right edge just above the action cluster, and — while it carries a count — it does not recede at rest (DESIGN
/// §23 Q4b). Whatever ends at that height stayed under it for good: the last
/// row's ⋮ menu on a short list, the field at the end of a form. A floating
/// control is only fair if everything under it can be scrolled out from
/// under it, which is the FAB lane's rule (Material) applied to the bubble.
///
/// The bubble layer says it once, above the Navigator (0 while a page is
/// pushed over the shell); [awListPadding] and [awScrollEndPadding] read it. 0 when no bubble
/// shows (wide layouts, signed out, switched off, nothing to open) or when it
/// was parked in the upper half, where padding the end of a list would not
/// move anything out from under it.
class AwBubbleClearance extends InheritedWidget {
  const AwBubbleClearance({
    super.key,
    required this.extent,
    required super.child,
  });

  /// Distance from the screen's bottom edge to just above the bubble.
  final double extent;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AwBubbleClearance>()?.extent ??
      0;

  @override
  bool updateShouldNotify(AwBubbleClearance oldWidget) =>
      oldWidget.extent != extent;
}

/// The bottom padding a scrolling screen ends with: at least [base], and
/// enough that its last line can scroll up past the Quick Access bubble.
///
/// [fab]: the screen's OWN Scaffold carries a floating action button (R3-1,
/// OPH-363). Its last row must scroll up past that button too — [base] plus
/// the [AwFabClearance.lane]. The bubble used to hide the omission: while it
/// rested above the FAB lane its clearance was the larger number. Docked in
/// the bar's row (OPH-362, until OPH-397) it cleared nothing, and a units
/// list ended under "+ New unit" with its last ⋮ unreachable. Both ask,
/// always.
double awScrollEndPadding(
  BuildContext context,
  double base, {
  bool fab = false,
}) => math.max(
  base + (fab ? AwFabClearance.lane : 0),
  AwBubbleClearance.of(context),
);

/// `EdgeInsets.all(all)` for a page's scrolling body, whose end clears the
/// Quick Access bubble and — with [fab] — the page's own floating button
/// ([awScrollEndPadding]).
EdgeInsets awPagePadding(
  BuildContext context,
  double all, {
  bool fab = false,
}) => EdgeInsets.fromLTRB(
  all,
  all,
  all,
  awScrollEndPadding(context, all, fab: fab),
);

/// The name the shell's page carries, so the bubble layer can tell the shell
/// (where the button floats) from a page pushed over it (where it is gone,
/// OPH-391 / OPH-397).
const String kAwShellPageName = 'aw-shell';
