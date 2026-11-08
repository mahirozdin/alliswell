import 'package:alliswell/src/features/quick_access/ui/bubble_physics.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-200 — the floating button's maths, with no widget in sight.
void main() {
  const viewport = Size(390, 844);
  const safeArea = EdgeInsets.only(top: 47, bottom: 34);

  group('snapToEdge', () {
    test('picks the nearer vertical edge', () {
      expect(
        snapToEdge(const Offset(40, 400), viewport, safeArea, 0).edge,
        BubbleEdge.left,
      );
      expect(
        snapToEdge(const Offset(350, 400), viewport, safeArea, 0).edge,
        BubbleEdge.right,
      );
    });

    test('the exact midpoint goes right — one rule, never a coin flip', () {
      expect(
        snapToEdge(const Offset(195, 400), viewport, safeArea, 0).edge,
        BubbleEdge.right,
      );
    });

    test('height is clamped into 0..1, above and below', () {
      expect(
        snapToEdge(
          const Offset(350, -500),
          viewport,
          safeArea,
          0,
        ).heightFraction,
        0,
      );
      expect(
        snapToEdge(
          const Offset(350, 5000),
          viewport,
          safeArea,
          0,
        ).heightFraction,
        1,
      );
    });
  });

  group('bubbleOrigin', () {
    test('sits inside the safe area on both edges', () {
      const left = BubblePosition(edge: BubbleEdge.left, heightFraction: 0);
      final origin = bubbleOrigin(left, viewport, safeArea, 0);
      // Sideways on the floating gutter (ADR-0062 §4), not the 8 px margin.
      expect(origin.dx, kAwFloatGutter);
      expect(origin.dy, safeArea.top + kBubbleEdgeMargin);

      const right = BubblePosition(edge: BubbleEdge.right, heightFraction: 1);
      final far = bubbleOrigin(right, viewport, safeArea, 0);
      expect(far.dx, viewport.width - kAwFloatGutter - kBubbleDiameter);
      expect(
        far.dy + kBubbleDiameter,
        lessThanOrEqualTo(viewport.height - safeArea.bottom),
      );
    });

    test('a keyboard pushes the button UP, never under it', () {
      for (final bottomed in const [
        BubblePosition(edge: BubbleEdge.right, heightFraction: 0.9),
        BubblePosition(edge: BubbleEdge.right, heightFraction: 1),
      ]) {
        final resting = bubbleOrigin(bottomed, viewport, safeArea, 0);
        final withKeyboard = bubbleOrigin(bottomed, viewport, safeArea, 320);
        expect(withKeyboard.dy, lessThan(resting.dy));
        expect(
          withKeyboard.dy + kBubbleDiameter,
          lessThanOrEqualTo(viewport.height - 320),
        );
      }
    });

    test('a rotation re-derives pixels from the fraction', () {
      const middle = BubblePosition(
        edge: BubbleEdge.right,
        heightFraction: 0.5,
      );
      const landscape = Size(844, 390);
      final origin = bubbleOrigin(middle, landscape, EdgeInsets.zero, 0);
      // 844 wide: the widest phones' 20 px gutter.
      expect(origin.dx, landscape.width - kAwFloatGutterWide - kBubbleDiameter);
      expect(origin.dy + kBubbleDiameter, lessThan(landscape.height));
    });
  });

  group('persistence', () {
    test('encode ∘ parse round-trips', () {
      const position = BubblePosition(
        edge: BubbleEdge.left,
        heightFraction: 0.723,
      );
      expect(parseBubblePosition(encodeBubblePosition(position)), position);
    });

    test('anything we did not write reads as the factory position', () {
      for (final junk in [
        null,
        '',
        'up:0.5',
        'right',
        'right:9',
        'right:-0.2',
        'left:abc',
        '{"edge":"left"}',
      ]) {
        expect(
          parseBubblePosition(junk),
          kBubbleFactoryPosition,
          reason: 'junk "$junk" must not strand the button',
        );
      }
    });

    test('OPH-397: the factory position is above the "+", in its column — '
        'never in the bar\'s row', () {
      expect(kBubbleFactoryPosition.edge, BubbleEdge.right);
      final origin = bubbleOrigin(
        kBubbleFactoryPosition,
        viewport,
        safeArea,
        0,
      );
      // The "+": 56 px, its end on the gutter, 16 above the capsule, which
      // floats on the safe area (34 here, at least 12).
      const plusTop = 844 - 34 - kBubbleBarHeight - 16 - 56;
      expect(origin.dy + kBubbleDiameter, plusTop - kBubbleEdgeMargin);
      expect(origin.dx + kBubbleDiameter, viewport.width - kAwFloatGutter);
    });

    // OPH-359 — UI-AUDIT #57.
    test('UI-AUDIT #57: it rests low, out of the middle of the screen where '
        'the row menus and the form controls are', () {
      final origin = bubbleOrigin(
        kBubbleFactoryPosition,
        viewport,
        safeArea,
        0,
      );
      expect(origin.dy, greaterThan(viewport.height * 0.6));
    });

    test('UI-AUDIT #57: wherever it is dragged it stays above the bar and '
        'the action cluster', () {
      for (final insets in const [
        safeArea,
        EdgeInsets.zero,
        EdgeInsets.only(bottom: 4),
      ]) {
        for (final fraction in const [0.5, 0.999, 1.0]) {
          final origin = bubbleOrigin(
            BubblePosition(edge: BubbleEdge.right, heightFraction: fraction),
            viewport,
            insets,
            0,
          );
          expect(
            origin.dy + kBubbleDiameter,
            lessThanOrEqualTo(viewport.height - bubbleBottomReserve(insets)),
            reason: '$insets $fraction',
          );
        }
      }
    });
  });

  group('UI-AUDIT #57 (retest): the room a screen leaves at its end', () {
    test('reaches from the bottom edge to above the resting button', () {
      final origin = bubbleOrigin(
        kBubbleFactoryPosition,
        viewport,
        safeArea,
        0,
      );
      final room = bubbleClearance(origin, viewport);
      expect(viewport.height - room, lessThan(origin.dy));
    });

    test('a button parked in the upper half asks for nothing', () {
      const high = BubblePosition(edge: BubbleEdge.right, heightFraction: 0);
      final origin = bubbleOrigin(high, viewport, safeArea, 0);
      expect(bubbleClearance(origin, viewport), 0);
    });
  });
}
