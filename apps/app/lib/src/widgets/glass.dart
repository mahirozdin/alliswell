import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Static ambient wash painted ONCE behind the whole app (see app.dart).
/// Three soft, motionless color blobs (azure / violet / mint) give the glass
/// chrome something to refract — deliberately colorful, deliberately not
/// animated (performance + reduced motion). Body text never sits on the wash
/// directly: the scaffold veil and solid surfaces guarantee contrast.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.awTokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.auroraTop, t.auroraBottom],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  children: [
                    _blob(t.blobA, w * -0.20, h * -0.15, w * 0.85),
                    _blob(t.blobB, w * 0.48, h * 0.24, w * 0.78),
                    _blob(t.blobC, w * -0.12, h * 0.60, w * 0.72),
                  ],
                );
              },
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _blob(Color color, double left, double top, double size) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which edge of a glass panel touches content (gets the lensing stroke).
/// [all] is the Liquid Glass default for floating chrome.
enum GlassEdge { top, right, all }

/// Liquid Glass chrome surface (docs/DESIGN.md rule G1: chrome only — body
/// text always lives on solid surfaces).
///
/// The material is built the way iOS 26 builds it, within Flutter's means:
///  * the backdrop is blurred AND saturation-boosted, so the aurora's color
///    bleeds through vividly instead of turning to gray fog;
///  * a high-opacity tint keeps text on the glass at ≥ 4.5:1 no matter what
///    scrolls beneath (Apple's "regular" variant, chosen for legibility);
///  * a gradient lensing edge — bright on the top rim, fading down — fakes
///    the light-bending rim of real glass;
///  * [floating] chrome casts a soft ambient shadow, visually lifting the
///    functional layer above the content layer.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.edge = GlassEdge.all,
    this.borderRadius,
    this.floating = false,
  });

  final Widget child;
  final GlassEdge edge;
  final BorderRadiusGeometry? borderRadius;

  /// Floating chrome (bottom bar capsule, rail panel): adds the ambient
  /// drop shadow that separates the glass layer from content.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final t = context.awTokens;
    final radius =
        borderRadius?.resolve(Directionality.of(context)) ?? BorderRadius.zero;

    final surface = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: kAwGlassSigma, sigmaY: kAwGlassSigma),
          inner: ColorFilter.matrix(_saturationMatrix(kAwGlassSaturation)),
        ),
        child: CustomPaint(
          foregroundPainter: _LensEdgePainter(
            radius: radius,
            edge: edge,
            bright: t.glassStroke,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(t.glassHighlight, t.glassTint),
                  t.glassTint,
                ],
                stops: const [0, 0.4],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (!floating) return surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: t.glassShadow,
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: t.glassShadow.withValues(alpha: t.glassShadow.a * 0.5),
            blurRadius: 6,
            offset: const Offset(0, 2),
            spreadRadius: -2,
          ),
        ],
      ),
      child: surface,
    );
  }
}

/// 5×4 color matrix that scales saturation by [s] (1 = identity).
List<double> _saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
  return <double>[
    ir + s, ig, ib, 0, 0, //
    ir, ig + s, ib, 0, 0, //
    ir, ig, ib + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Strokes the glass rim with a vertical light gradient: strongest on the
/// top edge (specular catchlight), fading to a faint trace at the bottom —
/// the "lensing" that makes the panel read as glass, not as a gray card.
class _LensEdgePainter extends CustomPainter {
  const _LensEdgePainter({
    required this.radius,
    required this.edge,
    required this.bright,
  });

  final BorderRadius radius;
  final GlassEdge edge;
  final Color bright;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    switch (edge) {
      case GlassEdge.top:
        paint.color = bright;
        canvas.drawLine(rect.topLeft, rect.topRight, paint);
      case GlassEdge.right:
        paint.color = bright.withValues(alpha: bright.a * 0.6);
        canvas.drawLine(rect.topRight, rect.bottomRight, paint);
      case GlassEdge.all:
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bright,
            bright.withValues(alpha: bright.a * 0.25),
            bright.withValues(alpha: bright.a * 0.55),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect);
        canvas.drawRRect(radius.toRRect(rect).deflate(0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_LensEdgePainter old) =>
      old.radius != radius || old.edge != edge || old.bright != bright;
}
