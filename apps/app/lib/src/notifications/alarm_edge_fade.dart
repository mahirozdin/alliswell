import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How tall the fade at a ring surface's scrolling edge is (W-15).
const double kAlarmEdgeFadeHeight = AwSpace.x6;

/// Fades the bottom edge of [child], a scroll view, while more of it lies
/// below (W-15, spec §1.4 "alt kenar sisi"): a card cut by a hard line read as
/// the end of the list, a card fading out reads as "there is more". At the
/// end of the scroll, or when everything fits, nothing is faded.
///
/// The mask only scales the child's own alpha (`dstIn`): no colour is
/// painted, so the contrast pairs underneath stay the ones `contrast.py`
/// measures — and the faded strip is the part that is about to scroll in.
class AlarmEdgeFade extends StatefulWidget {
  const AlarmEdgeFade({super.key, required this.child});

  final Widget child;

  @override
  State<AlarmEdgeFade> createState() => AlarmEdgeFadeState();
}

/// Public for tests: [fading] says whether the bottom edge is faded now.
class AlarmEdgeFadeState extends State<AlarmEdgeFade> {
  bool _more = false;

  /// More of the scroll view lies below its bottom edge, so that edge fades.
  bool get fading => _more;

  bool _onMetrics(ScrollMetrics metrics, int depth) {
    if (depth != 0) return false;
    final more = metrics.extentAfter > 0.5;
    if (more != _more && mounted) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Always the same mask, so the scroll view under it keeps its State and
    // its offset when the fade comes and goes; nothing to fade = all solid.
    final mask = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final solid = !_more || bounds.height <= 0
            ? 1.0
            : (1 - kAlarmEdgeFadeHeight / bounds.height).clamp(0.0, 1.0);
        // An alpha mask, not a colour on screen: only the alpha counts.
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, solid, 1],
        ).createShader(bounds);
      },
      child: widget.child,
    );
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics, n.depth),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => _onMetrics(n.metrics, n.depth),
        child: mask,
      ),
    );
  }
}
