import 'dart:math' as math;

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

/// How far up from the screen's bottom edge the phone's Quick Access bubble
/// reaches (UI-AUDIT #57, retest).
///
/// The bubble floats above every route, at the right edge just above the FAB
/// lane, and — while it carries a count — it does not recede at rest (DESIGN
/// §23 Q4b). Whatever ends at that height stayed under it for good: the last
/// row's ⋮ menu on a short list, the field at the end of a form. A floating
/// control is only fair if everything under it can be scrolled out from
/// under it, which is the FAB lane's rule (Material) applied to the bubble.
///
/// The bubble layer says it once, above the Navigator, so every route sees
/// it; [awListPadding] and [awScrollEndPadding] read it. 0 when no bubble
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
/// the bar's row (OPH-362) it clears nothing above the page, and a units list
/// ended under "+ New unit" with its last ⋮ unreachable. Both ask, always.
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

/// Which side of the screen the docked Quick Access bubble sits on.
enum AwDockEdge { left, right }

/// The phone's Quick Access bubble at rest, in a lane of its own (OPH-362,
/// UI-AUDIT #57 — the rest that still covered controls).
///
/// [AwBubbleClearance] lets the END of a page scroll out from under the
/// bubble; it cannot uncover what a page draws at that height on first sight
/// (a member's ⋮, the second approval's "Approve", the end of "Save"). So the
/// bubble rests where no content is: in the bottom bar's row. The bubble
/// layer publishes the lane here, above the Navigator, and the shell's glass
/// bar ends [width] short of the [edge] it docks on.
///
/// A page OUTSIDE the shell has no bar, and gives up nothing: the docked
/// button steps aside while one is on top (OPH-391, E-09). Until then every
/// such page ended [height] above the screen's bottom, and task detail,
/// settings and a note showed a ~100 pt band of wash under their content.
///
/// Absent (or zero) when nothing is docked: wide layouts, no bubble, a bubble
/// the person parked elsewhere, or a keyboard covering the row.
class AwBubbleDock extends InheritedWidget {
  const AwBubbleDock({
    super.key,
    required this.edge,
    required this.height,
    required this.width,
    required super.child,
  });

  final AwDockEdge edge;

  /// From the screen's bottom edge to a gap above the docked button.
  final double height;

  /// From the screen's [edge] to a gap inside the docked button.
  final double width;

  static AwBubbleDock? maybeOf(BuildContext context) {
    final dock = context.dependOnInheritedWidgetOfExactType<AwBubbleDock>();
    return dock == null || dock.height <= 0 ? null : dock;
  }

  @override
  bool updateShouldNotify(AwBubbleDock oldWidget) =>
      oldWidget.edge != edge ||
      oldWidget.height != height ||
      oldWidget.width != width;
}

/// The name the shell's page carries, so the bubble layer can tell the shell
/// (where the button docks beside the bar, [AwBubbleDock]) from a page pushed
/// over it (where a docked button steps aside, OPH-391).
const String kAwShellPageName = 'aw-shell';
