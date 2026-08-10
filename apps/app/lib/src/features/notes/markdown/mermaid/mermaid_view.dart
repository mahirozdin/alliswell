/// Drawing a mermaid diagram (OPH-254, DESIGN §29 D7/D8/D11).
///
/// A `CustomPainter` over the pure-Dart layouts — no web view and no JS engine
/// anywhere near the reading path, which is D10's hard line and the reason
/// ADR-0028 refused the easy implementation.
///
/// Every colour comes from `AwTokens`/`ColorScheme`; there is not a hex in this
/// file. And when a diagram cannot be drawn, the reason says WHICH kind of
/// cannot: a type we decline is a different sentence from a diagram we failed
/// to read (D11).
library;

import 'package:flutter/material.dart';

import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../md_theme.dart';
import '../md_unsupported.dart';
import 'flow_layout.dart';
import 'mermaid_parse.dart';
import 'sequence_layout.dart';

/// Renders the body of a ```` ```mermaid ```` fence.
class MermaidView extends StatelessWidget {
  const MermaidView({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final diagram = parseMermaid(source);

    return switch (diagram) {
      // Two different failures, two different sentences — the rule D11 exists
      // for. "Not drawn yet" sends the reader to wait; "could not be read"
      // sends them to their own line.
      MermaidUnsupported(:final type) => MdUnsupportedBlock(
        icon: Icons.account_tree_outlined,
        reason: 'markdown.mermaidUnsupported'.tr(args: {'type': type}),
        source: source,
      ),
      MermaidParseError() => MdUnsupportedBlock(
        icon: Icons.account_tree_outlined,
        reason: 'markdown.mermaidUnreadable'.tr(),
        source: source,
      ),
      MermaidFlow() => _Canvas(diagram: diagram),
      MermaidSequence() => _Canvas(diagram: diagram),
    };
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({required this.diagram});

  final MermaidDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    final labelStyle = styles.body.copyWith(fontSize: 13, height: 1.2);

    Size measure(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.size;
    }

    final painter = switch (diagram) {
      MermaidFlow() => _FlowPainter(
        layout: layoutFlowchart(diagram as MermaidFlow, measure: measure),
        styles: styles,
        labelStyle: labelStyle,
      ),
      MermaidSequence() => _SequencePainter(
        layout: layoutSequence(diagram as MermaidSequence, measure: measure),
        styles: styles,
        labelStyle: labelStyle,
      ),
      _ => null,
    };
    if (painter == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AwSpace.x2),
      decoration: BoxDecoration(
        color: styles.scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        border: Border.all(color: styles.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // D8: a diagram wider than the column scrolls HERE. The page never
      // scrolls sideways.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AwSpace.x2),
        child: CustomPaint(size: painter.canvasSize, painter: painter),
      ),
    );
  }
}

abstract class _DiagramPainter extends CustomPainter {
  const _DiagramPainter({required this.styles, required this.labelStyle});

  final MdStyles styles;
  final TextStyle labelStyle;

  Size get canvasSize;

  Color get ink => styles.scheme.onSurface;
  Color get line => styles.scheme.onSurfaceVariant;
  Color get fill => styles.scheme.surfaceContainerHighest;

  void paintText(
    Canvas canvas,
    String text,
    Offset anchor, {
    TextAlign align = TextAlign.center,
    Color? color,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: color ?? ink),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(
      canvas,
      align == TextAlign.center
          ? anchor - Offset(painter.width / 2, painter.height / 2)
          : anchor,
    );
  }

  /// A filled arrowhead at [tip], pointing away from [from].
  void paintArrow(Canvas canvas, Offset from, Offset tip, Paint paint) {
    final direction = (tip - from);
    final length = direction.distance;
    if (length == 0) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    const size = 7.0;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - unit.dx * size + normal.dx * size * 0.5,
        tip.dy - unit.dy * size + normal.dy * size * 0.5,
      )
      ..lineTo(
        tip.dx - unit.dx * size - normal.dx * size * 0.5,
        tip.dy - unit.dy * size - normal.dy * size * 0.5,
      )
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  /// Dashes a path by walking it — `PathMetric` is the only honest way to dash
  /// a curve, and a dotted edge that is really solid would misreport the
  /// diagram's meaning.
  void paintDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 5;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter old) =>
      old.styles.scheme != styles.scheme || old.canvasSize != canvasSize;
}

class _FlowPainter extends _DiagramPainter {
  const _FlowPainter({
    required this.layout,
    required super.styles,
    required super.labelStyle,
  });

  final FlowLayout layout;

  @override
  Size get canvasSize => layout.size;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (final edge in layout.edges) {
      final path = Path()..moveTo(edge.points.first.dx, edge.points.first.dy);
      for (final point in edge.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final paint = Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge.style == MermaidEdgeStyle.thick ? 2.6 : 1.4
        ..strokeCap = StrokeCap.round;

      if (edge.style == MermaidEdgeStyle.dotted) {
        paintDashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      if (edge.arrow && edge.points.length >= 2) {
        paintArrow(
          canvas,
          edge.points[edge.points.length - 2],
          edge.points.last,
          Paint()..color = line,
        );
      }

      if (edge.label != null && edge.labelAnchor != null) {
        // The caption sits on its own chip so it stays legible where it
        // crosses its own edge.
        final metrics = TextPainter(
          text: TextSpan(text: edge.label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final box = Rect.fromCenter(
          center: edge.labelAnchor!,
          width: metrics.width + 10,
          height: metrics.height + 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = styles.scheme.surfaceContainerLow,
        );
        paintText(canvas, edge.label!, edge.labelAnchor!, color: line);
      }
    }

    for (final node in layout.nodes) {
      _paintShape(canvas, node, stroke);
      paintText(
        canvas,
        node.label,
        node.rect.center,
        maxWidth: node.rect.width - 8,
      );
    }
  }

  void _paintShape(Canvas canvas, FlowNodeBox node, Paint stroke) {
    final body = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    final r = node.rect;

    switch (node.shape) {
      case MermaidShape.diamond:
        final path = Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..close();
        canvas
          ..drawPath(path, body)
          ..drawPath(path, stroke);
      case MermaidShape.circle:
        canvas
          ..drawOval(r, body)
          ..drawOval(r, stroke);
      case MermaidShape.stadium:
        final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
        canvas
          ..drawRRect(rr, body)
          ..drawRRect(rr, stroke);
      case MermaidShape.round:
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
        canvas
          ..drawRRect(rr, body)
          ..drawRRect(rr, stroke);
      case MermaidShape.rect:
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
        canvas
          ..drawRRect(rr, body)
          ..drawRRect(rr, stroke);
    }
  }
}

class _SequencePainter extends _DiagramPainter {
  const _SequencePainter({
    required this.layout,
    required super.styles,
    required super.labelStyle,
  });

  final SequenceLayout layout;

  @override
  Size get canvasSize => layout.size;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final p in layout.participants) {
      final lifeline = Path()
        ..moveTo(p.lifelineX, p.header.bottom)
        ..lineTo(p.lifelineX, p.lifelineBottom);
      paintDashed(
        canvas,
        lifeline,
        Paint()
          ..color = styles.hairline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      final rr = RRect.fromRectAndRadius(p.header, const Radius.circular(6));
      canvas
        ..drawRRect(rr, Paint()..color = fill)
        ..drawRRect(rr, stroke);
      paintText(canvas, p.label, p.header.center, maxWidth: p.header.width - 8);
    }

    for (final m in layout.messages) {
      final path = Path()..moveTo(m.points.first.dx, m.points.first.dy);
      for (final point in m.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final paint = Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;

      if (m.dotted) {
        paintDashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      if (m.arrow) {
        paintArrow(
          canvas,
          m.points[m.points.length - 2],
          m.points.last,
          Paint()..color = line,
        );
      }

      paintText(
        canvas,
        m.text,
        m.textAnchor,
        align: m.isSelf ? TextAlign.left : TextAlign.center,
        color: ink,
        maxWidth: m.isSelf ? 220 : null,
      );
    }
  }
}
