import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'tour.dart';

/// The first-run tour overlay (OPH-111): a dimming scrim with a spotlight
/// cut-out over the current step's anchor, plus a solid bubble card explaining
/// it. Glass stays chrome-only (DESIGN G1) — the bubble is a SOLID surface.
/// The overlay is rendered on top of the shell; the caller supplies the
/// anchor's on-screen [anchorRect] (null = a centered welcome/farewell card).
class TourOverlay extends StatelessWidget {
  const TourOverlay({
    super.key,
    required this.state,
    required this.anchorRect,
    required this.onNext,
    required this.onSkip,
  });

  final TourState state;
  final Rect? anchorRect;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      // System back / ESC skips the tour instead of leaving the screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onSkip();
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'App tour, step ${state.step + 1} of ${kTourSteps.length}',
        child: AnimatedSwitcher(
          duration: AwMotion.fast,
          child: KeyedSubtree(
            key: ValueKey(state.step),
            child: Stack(
              children: [
                // Dimming scrim with the spotlight hole. Absorbs taps so the app
                // underneath can't be poked mid-tour (advance via the buttons).
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {},
                    child: CustomPaint(painter: _SpotlightPainter(anchorRect)),
                  ),
                ),
                if (anchorRect != null)
                  Positioned.fromRect(
                    rect: anchorRect!.inflate(10),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(14),
                          ),
                          border: Border.all(color: scheme.primary, width: 2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: media.padding.top + 4,
                  right: 4,
                  child: TextButton(
                    key: const Key('tour-skip'),
                    onPressed: onSkip,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Skip'),
                  ),
                ),
                _bubble(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = state.current;
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AwSpace.x2),
              Text(step.body, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AwSpace.x4),
              Row(
                children: [
                  for (var i = 0; i < kTourSteps.length; i++)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == state.step
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('tour-next'),
                    onPressed: onNext,
                    child: Text(state.isLast ? 'Done' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final rect = anchorRect;
    final screen = MediaQuery.sizeOf(context);
    // Welcome / farewell (no anchor) → center.
    if (rect == null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(AwSpace.x6), child: card),
      );
    }
    // A rail icon sits on the left → put the card to its RIGHT, roughly level
    // with it. A bottom-bar icon sits low → put the card ABOVE it.
    final onLeft = rect.center.dx < screen.width * 0.35;
    if (onLeft) {
      final top = (rect.top - 12).clamp(
        MediaQuery.paddingOf(context).top + 8,
        screen.height - 280,
      );
      return Positioned(
        left: rect.right + AwSpace.x4,
        right: AwSpace.x4,
        top: top,
        child: Align(alignment: Alignment.centerLeft, child: card),
      );
    }
    return Positioned(
      left: AwSpace.x4,
      right: AwSpace.x4,
      bottom: screen.height - rect.top + AwSpace.x4,
      child: Align(alignment: Alignment.center, child: card),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xCC0B1220);
    final full = Offset.zero & size;
    if (hole == null) {
      canvas.drawRect(full, paint);
      return;
    }
    final rrect = RRect.fromRectAndRadius(
      hole!.inflate(10),
      const Radius.circular(14),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRRect(rrect),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}
