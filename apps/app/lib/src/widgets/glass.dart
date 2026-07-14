import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Static ambient wash painted ONCE behind the whole app (see app.dart).
/// Two soft, motionless color blobs give the glass chrome something to
/// refract — deliberately not animated (performance + reduced motion).
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
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.auroraTop, t.auroraBottom],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  children: [
                    _blob(t.blobA, w * -0.15, h * -0.12, w * 0.7),
                    _blob(t.blobB, w * 0.55, h * 0.55, w * 0.8),
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

/// Which edge of a glass panel touches content (gets the hairline stroke).
enum GlassEdge { top, right, all }

/// Frosted chrome surface: backdrop blur + high-opacity tint + hairline
/// stroke + top catchlight. Chrome only (nav bar, nav rail, toolbars) —
/// body text always lives on solid surfaces (docs/DESIGN.md rule G1).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.edge = GlassEdge.all,
    this.borderRadius,
  });

  final Widget child;
  final GlassEdge edge;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final t = context.awTokens;
    final stroke = BorderSide(color: t.glassStroke);
    final border = switch (edge) {
      GlassEdge.top => Border(top: stroke),
      GlassEdge.right => Border(right: stroke),
      GlassEdge.all => Border.fromBorderSide(stroke),
    };
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kAwGlassSigma, sigmaY: kAwGlassSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: border,
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(t.glassHighlight, t.glassTint),
                t.glassTint,
              ],
              stops: const [0, 0.35],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
