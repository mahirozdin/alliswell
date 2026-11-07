import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../theme/tokens.dart';
import 'tour.dart';

/// The first-run tour overlay (OPH-111): a dimming scrim with a spotlight
/// cut-out over the current step's anchor, plus a solid bubble card explaining
/// it. Glass stays chrome-only (DESIGN G1) — the bubble is a SOLID surface.
/// The overlay is rendered on top of the shell; the caller supplies
/// [resolveAnchor], the current step's on-screen rect (null = a centred
/// card). It is asked again after each frame that changed something and
/// whenever a [TourAnchor] arrives (OPH-404): the step's target can be laid
/// out after the tour started.
class TourOverlay extends StatefulWidget {
  const TourOverlay({
    super.key,
    required this.state,
    required this.resolveAnchor,
    required this.onNext,
    required this.onSkip,
  });

  final TourState state;
  final Rect? Function() resolveAnchor;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  Rect? anchorRect;

  TourState get state => widget.state;
  VoidCallback get onNext => widget.onNext;
  VoidCallback get onSkip => widget.onSkip;

  @override
  void initState() {
    super.initState();
    anchorRect = widget.resolveAnchor();
    TourAnchor.changes.addListener(_refresh);
  }

  @override
  void didUpdateWidget(TourOverlay old) {
    super.didUpdateWidget(old);
    anchorRect = widget.resolveAnchor();
  }

  @override
  void dispose() {
    TourAnchor.changes.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final rect = widget.resolveAnchor();
    if (rect != anchorRect) setState(() => anchorRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    // Settles in a frame or two: a refresh only rebuilds when the rect moved.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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
        label: 'tour.stepOf'.tr(
          args: {'step': '${state.step + 1}', 'total': '${state.steps.length}'},
        ),
        child: AnimatedSwitcher(
          duration: AwMotion.fast,
          child: KeyedSubtree(
            key: ValueKey(state.step),
            // The overlay's own box, not the window: it covers the shell, and
            // the anchors are measured in the same space.
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  // Dimming scrim with the spotlight hole. Absorbs taps so the app
                  // underneath can't be poked mid-tour (advance via the buttons).
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {},
                      child: CustomPaint(
                        painter: _SpotlightPainter(anchorRect),
                      ),
                    ),
                  ),
                  if (anchorRect != null)
                    Positioned.fromRect(
                      key: const Key('tour-spotlight'),
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
                  _bubble(context, box.biggest),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, Size screen) {
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
                  for (var i = 0; i < state.steps.length; i++)
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
                  // OPH-404 (U-33): Skip lives in the card, left of Next —
                  // in the screen's corner it sat on the settings gear, and
                  // Next stays in one place on every step.
                  if (!state.isLast)
                    TextButton(
                      key: const Key('tour-skip'),
                      onPressed: onSkip,
                      child: Text('tour.skip'.tr()),
                    ),
                  const SizedBox(width: AwSpace.x2),
                  FilledButton(
                    key: const Key('tour-next'),
                    onPressed: onNext,
                    child: Text(
                      state.isLast ? 'tour.done'.tr() : 'tour.next'.tr(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final rect = anchorRect;
    // No anchor (the alarm step, or a target off screen) → centre.
    if (rect == null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(AwSpace.x6), child: card),
      );
    }
    // A rail icon sits on the left → put the card to its RIGHT, roughly level
    // with it. Something in the top half (Home's quick-add field) → BELOW it;
    // a bottom-bar icon or a floating button → ABOVE it.
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
    if (rect.center.dy < screen.height / 2) {
      return Positioned(
        left: AwSpace.x4,
        right: AwSpace.x4,
        top: rect.bottom + AwSpace.x4,
        child: Align(alignment: Alignment.center, child: card),
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
