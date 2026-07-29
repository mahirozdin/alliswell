import 'package:alliswell/src/features/quick_access/ui/bubble_physics.dart';
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
      expect(origin.dx, kBubbleEdgeMargin);
      expect(origin.dy, safeArea.top + kBubbleEdgeMargin);

      const right = BubblePosition(edge: BubbleEdge.right, heightFraction: 1);
      final far = bubbleOrigin(right, viewport, safeArea, 0);
      expect(far.dx, viewport.width - kBubbleEdgeMargin - kBubbleDiameter);
      expect(
        far.dy + kBubbleDiameter,
        lessThanOrEqualTo(viewport.height - safeArea.bottom),
      );
    });

    test('a keyboard pushes the button UP, never under it', () {
      const bottomed = BubblePosition(
        edge: BubbleEdge.right,
        heightFraction: 1,
      );
      final resting = bubbleOrigin(bottomed, viewport, safeArea, 0);
      final withKeyboard = bubbleOrigin(bottomed, viewport, safeArea, 320);
      expect(withKeyboard.dy, lessThan(resting.dy));
      expect(
        withKeyboard.dy + kBubbleDiameter,
        lessThanOrEqualTo(viewport.height - 320),
      );
    });

    test('a rotation re-derives pixels from the fraction', () {
      const middle = BubblePosition(
        edge: BubbleEdge.right,
        heightFraction: 0.5,
      );
      const landscape = Size(844, 390);
      final origin = bubbleOrigin(middle, landscape, EdgeInsets.zero, 0);
      expect(origin.dx, landscape.width - kBubbleEdgeMargin - kBubbleDiameter);
      expect(origin.dy + kBubbleDiameter, lessThan(landscape.height));
    });
  });

  group('recedePaintDx', () {
    test('slides toward its own edge, and only paint moves', () {
      expect(recedePaintDx(BubbleEdge.right, 1), kBubbleDiameter / 2);
      expect(recedePaintDx(BubbleEdge.left, 1), -kBubbleDiameter / 2);
      expect(recedePaintDx(BubbleEdge.right, 0), 0);
      // Out-of-range t cannot push it further than half a diameter.
      expect(recedePaintDx(BubbleEdge.right, 4), kBubbleDiameter / 2);
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

    test('the factory position keeps clear of the quick-add FAB corner', () {
      expect(kBubbleFactoryPosition.edge, BubbleEdge.right);
      expect(kBubbleFactoryPosition.heightFraction, closeTo(0.35, 0.001));
      final origin = bubbleOrigin(
        kBubbleFactoryPosition,
        viewport,
        safeArea,
        0,
      );
      // Well above the bottom-right FAB (DESIGN §23 Q4c).
      expect(origin.dy + kBubbleDiameter, lessThan(viewport.height * 0.6));
    });
  });
}
