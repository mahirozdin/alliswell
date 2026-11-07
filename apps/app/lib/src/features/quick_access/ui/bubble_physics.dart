/// The floating button's physics, as pure functions (OPH-200, DESIGN §23 Q4).
///
/// Everything here is testable without a widget: which edge a release snaps
/// to, where the button sits after a rotation or a keyboard, how far the idle
/// state recedes, and how the position survives a restart.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../theme/tokens.dart';

/// Which side the button is parked on.
enum BubbleEdge { left, right }

/// Diameter — also the tap target; the idle state only fades, so the whole
/// 56 px stays on screen and tappable (§5, U-03).
const double kBubbleDiameter = 56;

/// Breathing room above and below the button inside its band. Sideways it
/// keeps the floating gutter instead ([awFloatGutter], ADR-0062 §4): the
/// same 16 (20 on the widest phones) as the capsule, the orb and the "+",
/// so at rest on the right it stands in the "+"'s column.
const double kBubbleEdgeMargin = AwSpace.x2;

/// Idle delay before the button fades, and how faint it gets.
///
/// 40 % is not a taste call: it is the platform's own default ("the
/// AssistiveTouch button fades to 40 % opacity a few seconds after you stop
/// using it"). OPH-196 measured the idiom before the number was fixed. It
/// only FADES: since OPH-397 (U-03) nothing of it slides past the safe area —
/// half a circle beyond the screen's edge read as broken.
const Duration kBubbleIdleDelay = Duration(seconds: 3);
const double kBubbleIdleOpacity = 0.40;

/// The phone's bottom bar, as the shell draws it: a 64 px glass capsule
/// (`kAwTabCapsuleHeight`) floating at least 12 px above the screen's edge
/// (`AwSpace.x3`, the shell's `SafeArea.minimum`).
const double kBubbleBarHeight = 64;
const double kBubbleBarFloat = 12;

/// The shell's action cluster above the bar: Material's 16 px float and the
/// 56 px "+" (`AwFabClearance.lane`).
const double kBubbleFabLane = 16 + 56;

/// How much of the screen's bottom, above the safe area's floor, the band
/// the button may rest in leaves to the bar and the action cluster (OPH-359,
/// UI-AUDIT #57): parked over the bar it hid a tab, over the "+" the screen's
/// one primary action.
double bubbleBottomReserve(EdgeInsets safeArea) =>
    math.max(safeArea.bottom, kBubbleBarFloat) +
    kBubbleBarHeight +
    kBubbleFabLane;

/// Factory position: the bottom of the band on the right — just above the
/// "+", in its column (OPH-397).
///
/// History. OPH-362 docked the button in the bar's own row beside the
/// capsule (UI-AUDIT #57: every rest above it covered something); that lane
/// left the capsule's slots under 48 dp (ADR-0062), so the bubble is off by
/// default on phones now and, switched on, rests above the cluster again —
/// where `awListPadding` lets every list end above it (`AwBubbleClearance`).
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
  final bottomInset = math.max(bubbleBottomReserve(safeArea), keyboardInset);
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
  // Inside the safe area, on the floating gutter (U-03, ADR-0062 §4).
  final gutter = awFloatGutter(viewport.width);
  final left = safeArea.left + gutter;
  final right = viewport.width - safeArea.right - gutter - kBubbleDiameter;
  final dx = position.edge == BubbleEdge.left ? left : math.max(left, right);
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
