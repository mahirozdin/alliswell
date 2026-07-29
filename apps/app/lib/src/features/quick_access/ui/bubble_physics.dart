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

/// Factory position: right edge, 35 % down — deliberately far from the
/// quick-add FAB's corner (DESIGN §23 Q4c: the bubble is not a FAB).
const BubblePosition kBubbleFactoryPosition = BubblePosition(
  edge: BubbleEdge.right,
  heightFraction: 0.35,
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
  // it when both are present, hence the max rather than the sum.
  final bottomInset = math.max(safeArea.bottom, keyboardInset);
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
  final band = bubbleBand(viewport, safeArea, keyboardInset);
  final travel = math.max(0.0, band.height - kBubbleDiameter);
  final dy = band.top + travel * position.heightFraction.clamp(0.0, 1.0);
  final left = safeArea.left + kBubbleEdgeMargin;
  final right =
      viewport.width - safeArea.right - kBubbleEdgeMargin - kBubbleDiameter;
  final dx = position.edge == BubbleEdge.left ? left : math.max(left, right);
  return Offset(dx, dy);
}

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
