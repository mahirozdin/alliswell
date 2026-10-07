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
      for (final bottomed in const [
        BubblePosition(edge: BubbleEdge.right, heightFraction: 0.9),
        // Docked: the host hides it under a keyboard, but its geometry
        // still never puts it there.
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
      expect(kBubbleFactoryPosition.docked, isTrue);
      final origin = bubbleOrigin(
        kBubbleFactoryPosition,
        viewport,
        safeArea,
        0,
      );
      // Below the FAB lane, in the bar's row (DESIGN §23 Q4c): never in the
      // FAB's corner — the lane above it is the FAB's.
      expect(
        origin.dy,
        greaterThanOrEqualTo(
          viewport.height -
              safeArea.bottom -
              kBubbleBarFloat -
              kBubbleBarHeight,
        ),
      );
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

    test('UI-AUDIT #57: a position the person drags stays above the bar and '
        'the FAB lane — only the dock lives in the bar\'s row', () {
      const dragged = BubblePosition(
        edge: BubbleEdge.right,
        heightFraction: 0.999,
      );
      expect(dragged.docked, isFalse);
      final origin = bubbleOrigin(dragged, viewport, safeArea, 0);
      expect(
        origin.dy + kBubbleDiameter,
        lessThanOrEqualTo(
          viewport.height - safeArea.bottom - kBubbleBottomReserve,
        ),
      );
    });
  });

  // OPH-362 — UI-AUDIT #57: the rest that still covered controls.
  group('UI-AUDIT #57: the dock', () {
    test('docked, it is centred on the bottom bar\'s row, inside the safe '
        'area', () {
      for (final insets in const [
        safeArea,
        EdgeInsets.zero,
        EdgeInsets.only(bottom: 4),
      ]) {
        final origin = bubbleOrigin(
          kBubbleFactoryPosition,
          viewport,
          insets,
          0,
        );
        final barBottom =
            viewport.height - (insets.bottom > 12 ? insets.bottom : 12);
        expect(
          origin.dy + kBubbleDiameter / 2,
          barBottom - kBubbleBarHeight / 2,
          reason: '$insets',
        );
        expect(origin.dy + kBubbleDiameter, lessThan(barBottom));
      }
    });

    test('the lane is the button plus a gap — as high as the content must '
        'stop, as wide as the bar must give up, on either edge', () {
      for (final edge in BubbleEdge.values) {
        final origin = bubbleOrigin(
          BubblePosition(edge: edge, heightFraction: 1),
          viewport,
          EdgeInsets.zero,
          0,
        );
        final lane = bubbleDockLane(origin, viewport);
        // Content above the lane ends a gap above the button.
        expect(viewport.height - lane.height, origin.dy - kBubbleEdgeMargin);
        // The bar beside it ends a gap before it.
        final barEdge = edge == BubbleEdge.right
            ? viewport.width - lane.width
            : lane.width;
        if (edge == BubbleEdge.right) {
          expect(barEdge, origin.dx - kBubbleEdgeMargin);
        } else {
          expect(barEdge, origin.dx + kBubbleDiameter + kBubbleEdgeMargin);
        }
      }
    });

    test('a release below the free band docks; anywhere above it does not', () {
      expect(
        snapToEdge(const Offset(350, 820), viewport, safeArea, 0).docked,
        isTrue,
      );
      expect(
        snapToEdge(const Offset(350, 400), viewport, safeArea, 0).docked,
        isFalse,
      );
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
