/// The floating button's physics, as pure functions (OPH-200, DESIGN §23 Q4).
///
/// Everything here is testable without a widget: which edge a release snaps
/// to, where the button sits after a rotation or a keyboard, how far the idle
/// state recedes, and how the position survives a restart.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Which side the button is parked on.
enum BubbleEdge { left, right }

/// Diameter — also the tap target, which is why the idle recede is paint-only
/// (a translated box would leave 28 px and break the 44 px floor, §5).
const double kBubbleDiameter = 56;

/// Breathing room between the button and the screen edge.
const double kBubbleEdgeMargin = 8;

/// Idle delay before the button recedes, and how faint it gets.
///
/// 40 % is not a taste call: it is the platform's own default ("the
/// AssistiveTouch button fades to 40 % opacity a few seconds after you stop
/// using it"). OPH-196 measured the idiom before the number was fixed.
const Duration kBubbleIdleDelay = Duration(seconds: 3);
const double kBubbleIdleOpacity = 0.40;

/// How much of the circle hides past the edge when idle (paint only).
const double kBubbleRecedeFraction = 0.5;

/// What the bottom of a phone screen already holds: the glass navigation bar
/// (80 px and its 12 px float) and, above it, the FAB lane (a 56 px button and
/// its 16 px margin). The band the button may rest in stops above both
/// (OPH-359, UI-AUDIT #57) — parked over the bar it hid a tab, and parked over
/// the FAB it hid the screen's one primary action.
const double kBubbleBottomReserve = 92 + 72;

/// The phone's bottom bar, as the shell draws it: a 64 px glass capsule
/// (`navigationBarTheme.height`) floating 12 px above the safe area
/// (`AwSpace.x3`, the shell's `SafeArea.minimum`). The dock is that row.
const double kBubbleBarHeight = 64;
const double kBubbleBarFloat = 12;

/// Factory position: DOCKED (OPH-362, UI-AUDIT #57's rest) — right edge, in
/// the bottom bar's row, beside the capsule.
///
/// Every earlier rest sat over content. In the middle of the right edge
/// (35 %, until OPH-359) it covered every row's ⋮ menu and form switch; just
/// above the FAB lane (OPH-359) it covered whatever a page drew at that
/// height on first sight — a member's ⋮, the second approval's "Approve", the
/// right end of a "Save" — and only scrolling uncovered them. Padding the end
/// of a list cannot fix the top of a screen. So the bubble does not rest ON
/// content at all: it rests in a lane of its own, which the layout keeps
/// free — the shell shortens its bar to make room in the bar's row, and every
/// page outside the shell ends above it (`AwBubbleDock`). A position the
/// person drags elsewhere is theirs (and padded for, `bubbleClearance`); the
/// bottom of the band is the dock again.
const BubblePosition kBubbleFactoryPosition = BubblePosition(
  edge: BubbleEdge.right,
  heightFraction: 1,
);

/// Where the button rests: an edge plus a fraction of the usable height.
///
/// A fraction, not pixels, because the usable band changes under the user
/// (rotation, a keyboard, a notch) and a stored pixel offset would strand the
/// button off-screen. Pixels are recomputed on every layout.
@immutable
class BubblePosition {
  const BubblePosition({required this.edge, required this.heightFraction});

  final BubbleEdge edge;
  final double heightFraction;

  /// At the bottom of its band = in the dock (OPH-362). The band's floor is
  /// where a release below the free band lands too, so "drag it down" docks.
  bool get docked => heightFraction >= 1;

  @override
  bool operator ==(Object other) =>
      other is BubblePosition &&
      other.edge == edge &&
      (other.heightFraction - heightFraction).abs() < 0.0005;

  @override
  int get hashCode => Object.hash(edge, (heightFraction * 1000).round());

  @override
  String toString() => 'BubblePosition($edge, $heightFraction)';
}

/// The vertical band the button may occupy: inside the safe area, above the
/// keyboard.
({double top, double height}) bubbleBand(
  Size viewport,
  EdgeInsets safeArea,
  double keyboardInset,
) {
  final top = safeArea.top + kBubbleEdgeMargin;
  // The keyboard eats from the bottom; the safe-area bottom is already inside
  // it when both are present, hence the max rather than the sum. The bar and
  // the FAB lane sit above the safe area, and a keyboard covers them both.
  final bottomInset = math.max(
    safeArea.bottom + kBubbleBottomReserve,
    keyboardInset,
  );
  final bottom = viewport.height - bottomInset - kBubbleEdgeMargin;
  final height = math.max(kBubbleDiameter, bottom - top);
  return (top: top, height: height);
}

/// Where a release lands: the nearer vertical edge, at the clamped height the
/// finger let go at.
BubblePosition snapToEdge(
  Offset centre,
  Size viewport,
  EdgeInsets safeArea,
  double keyboardInset,
) {
  final edge = centre.dx < viewport.width / 2
      ? BubbleEdge.left
      : BubbleEdge.right;
  final band = bubbleBand(viewport, safeArea, keyboardInset);
  final travel = math.max(1.0, band.height - kBubbleDiameter);
  final fraction = (centre.dy - kBubbleDiameter / 2 - band.top) / travel;
  return BubblePosition(edge: edge, heightFraction: fraction.clamp(0.0, 1.0));
}

/// The button box's top-left corner for a stored position — re-derived every
/// layout, so a rotation or a keyboard can never strand it.
Offset bubbleOrigin(
  BubblePosition position,
  Size viewport,
  EdgeInsets safeArea,
  double keyboardInset,
) {
  final left = safeArea.left + kBubbleEdgeMargin;
  final right =
      viewport.width - safeArea.right - kBubbleEdgeMargin - kBubbleDiameter;
  final dx = position.edge == BubbleEdge.left ? left : math.max(left, right);
  // Docked and no keyboard: centred on the bottom bar's row. A keyboard
  // covers that row (and the host hides a docked button under it), so the
  // band's floor above the keyboard is where it would stand.
  if (position.docked && keyboardInset <= 0) {
    final barBottom =
        viewport.height - math.max(safeArea.bottom, kBubbleBarFloat);
    final dy = barBottom - (kBubbleBarHeight + kBubbleDiameter) / 2;
    return Offset(dx, math.max(safeArea.top + kBubbleEdgeMargin, dy));
  }
  final band = bubbleBand(viewport, safeArea, keyboardInset);
  final travel = math.max(0.0, band.height - kBubbleDiameter);
  final dy = band.top + travel * position.heightFraction.clamp(0.0, 1.0);
  return Offset(dx, dy);
}

/// How much of a screen's bottom a scrolling view must leave free so that
/// whatever it ends with can be scrolled up from under a button resting at
/// [origin] (UI-AUDIT #57): from the screen's bottom edge to a small gap
/// above the button. A button parked in the upper half asks for nothing —
/// padding the END of a list does not move its top rows.
double bubbleClearance(Offset origin, Size viewport) {
  if (origin.dy < viewport.height / 2) return 0;
  return viewport.height - origin.dy + kBubbleEdgeMargin;
}

/// The lane a DOCKED button keeps for itself (OPH-362): how much of the
/// screen's bottom a page outside the shell gives up ([bubbleClearance] of
/// the docked origin — the button plus a gap above it), and how much of the
/// bar's row the shell's capsule gives up on that edge (the button, its edge
/// margin and the same gap on the inner side).
({double height, double width}) bubbleDockLane(Offset origin, Size viewport) =>
    (
      height: bubbleClearance(origin, viewport),
      width: origin.dx < viewport.width / 2
          ? origin.dx + kBubbleDiameter + kBubbleEdgeMargin
          : viewport.width - origin.dx + kBubbleEdgeMargin,
    );

/// How far the PAINTED circle slides toward its edge when idle. The gesture
/// box never moves — see [kBubbleDiameter].
double recedePaintDx(BubbleEdge edge, double t) {
  final distance = kBubbleDiameter * kBubbleRecedeFraction * t.clamp(0.0, 1.0);
  return edge == BubbleEdge.left ? -distance : distance;
}

/// `right:0.350` — the stored form (localKv holds strings).
String encodeBubblePosition(BubblePosition position) =>
    '${position.edge.name}:${position.heightFraction.clamp(0.0, 1.0).toStringAsFixed(3)}';

final RegExp _positionPattern = RegExp(r'^(left|right):([01](?:\.\d+)?)$');

/// Tolerant by contract, like every other stored preference: anything we did
/// not write — junk, an older format, a value out of range — reads as the
/// factory position rather than throwing at startup.
BubblePosition parseBubblePosition(String? raw) {
  if (raw == null) return kBubbleFactoryPosition;
  final match = _positionPattern.firstMatch(raw.trim());
  if (match == null) return kBubbleFactoryPosition;
  final fraction = double.tryParse(match.group(2)!);
  if (fraction == null || fraction < 0 || fraction > 1) {
    return kBubbleFactoryPosition;
  }
  return BubblePosition(
    edge: match.group(1) == 'left' ? BubbleEdge.left : BubbleEdge.right,
    heightFraction: fraction,
  );
}
