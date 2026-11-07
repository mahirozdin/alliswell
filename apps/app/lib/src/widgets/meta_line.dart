import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A row's meta line (OPH-400, DESIGN §46 R3): items side by side, [spacing]
/// apart, each centred on the line.
///
/// One line means one line. An item that does not fit whole is DROPPED, and so
/// is everything after it — the order is the priority, so what is cut is
/// always the least important end. Only the first item may be squeezed (it is
/// the date, and a date that ellipsizes beats a row with no date) — and an
/// item wrapped in [AwMetaShrink], which takes the width that is left when at
/// least its `minWidth` is (a state that must never silently vanish, like a
/// silenced alarm). A dropped item is neither painted, hit nor read out.
///
/// With [wrap] (the large-text row) the items flow onto as many lines as they
/// need instead, [runSpacing] apart.
class AwMetaLine extends MultiChildRenderObjectWidget {
  const AwMetaLine({
    super.key,
    required super.children,
    this.spacing = 8,
    this.runSpacing = 4,
    this.wrap = false,
  });

  final double spacing;
  final double runSpacing;
  final bool wrap;

  @override
  RenderAwMetaLine createRenderObject(BuildContext context) => RenderAwMetaLine(
    spacing: spacing,
    runSpacing: runSpacing,
    wrap: wrap,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderAwMetaLine renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..wrap = wrap
      ..textDirection = Directionality.of(context);
  }
}

class _MetaParentData extends ContainerBoxParentData<RenderBox> {
  bool shown = false;

  /// Set by [AwMetaShrink]: the narrowest width the item may be squeezed to
  /// instead of being dropped. Null — the item is shown whole or not at all.
  double? shrinkTo;
}

/// Marks an [AwMetaLine] item that shortens (its child ellipsizes) rather
/// than drops when the line runs out — as long as [minWidth] is left. Use it
/// for a fact whose absence would say the opposite (E35 G-B review r1: a
/// muted alarm that vanished read as an armed one).
class AwMetaShrink extends ParentDataWidget<_MetaParentData> {
  const AwMetaShrink({super.key, required this.minWidth, required super.child});

  final double minWidth;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _MetaParentData;
    if (data.shrinkTo == minWidth) return;
    data.shrinkTo = minWidth;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => AwMetaLine;
}

/// The render object behind [AwMetaLine].
class RenderAwMetaLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MetaParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MetaParentData> {
  RenderAwMetaLine({
    required double spacing,
    required double runSpacing,
    required bool wrap,
    required TextDirection textDirection,
  }) : this._(spacing, runSpacing, wrap, textDirection);

  RenderAwMetaLine._(
    this._spacing,
    this._runSpacing,
    this._wrap,
    this._textDirection,
  );

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  bool _wrap;
  set wrap(bool value) {
    if (value == _wrap) return;
    _wrap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// How many children the last layout showed (for tests and debugging).
  int get shownCount {
    var count = 0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _MetaParentData;
      if (data.shown) count++;
      child = data.nextSibling;
    }
    return count;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MetaParentData) {
      child.parentData = _MetaParentData();
    }
  }

  /// Measures the children with [measure] (a real layout or a dry one) and
  /// returns the size; [place] receives every child's position and whether it
  /// is shown.
  Size _arrange(
    BoxConstraints constraints, {
    required Size Function(RenderBox child, BoxConstraints c) measure,
    void Function(RenderBox child, Offset offset, bool shown)? place,
  }) {
    final maxWidth = constraints.maxWidth;
    const loose = BoxConstraints();
    final lines = <List<(RenderBox, Size)>>[[]];
    final hidden = <RenderBox>[];
    var x = 0.0;
    var stopped = false;
    var index = 0;
    for (var child = firstChild; child != null; index++) {
      final next = (child.parentData! as _MetaParentData).nextSibling;
      if (stopped) {
        hidden.add(child);
        child = next;
        continue;
      }
      var size = measure(child, loose);
      final gap = lines.last.isEmpty ? 0.0 : _spacing;
      if (x + gap + size.width > maxWidth) {
        final shrinkTo = (child.parentData! as _MetaParentData).shrinkTo;
        final left = maxWidth - x - gap;
        if (_wrap) {
          if (lines.last.isNotEmpty) {
            lines.add([]);
            x = 0;
          }
          if (size.width > maxWidth) {
            size = measure(child, BoxConstraints(maxWidth: maxWidth));
          }
        } else if (index == 0) {
          size = measure(child, BoxConstraints(maxWidth: maxWidth));
        } else if (shrinkTo != null && left >= shrinkTo) {
          // It takes the rest of the line, so nothing after it fits.
          size = measure(child, BoxConstraints(maxWidth: left));
          stopped = true;
        } else {
          stopped = true;
          hidden.add(child);
          child = next;
          continue;
        }
      }
      x += (lines.last.isEmpty ? 0.0 : _spacing) + size.width;
      lines.last.add((child, size));
      child = next;
    }

    final placed = <(RenderBox, Offset, Size)>[];
    var y = 0.0;
    var width = 0.0;
    for (final (i, line) in lines.indexed) {
      if (line.isEmpty) continue;
      if (i > 0) y += _runSpacing;
      final height = line.fold(0.0, (h, e) => math.max(h, e.$2.height));
      var lx = 0.0;
      for (final (box, size) in line) {
        if (lx > 0) lx += _spacing;
        placed.add((box, Offset(lx, y + (height - size.height) / 2), size));
        lx += size.width;
      }
      width = math.max(width, lx);
      y += height;
    }
    final out = constraints.constrain(Size(width, y));
    if (place != null) {
      for (final (box, offset, size) in placed) {
        place(
          box,
          _textDirection == TextDirection.rtl
              ? Offset(out.width - offset.dx - size.width, offset.dy)
              : offset,
          true,
        );
      }
      for (final box in hidden) {
        place(box, Offset.zero, false);
      }
    }
    return out;
  }

  @override
  void performLayout() {
    size = _arrange(
      constraints,
      measure: (child, c) {
        child.layout(c, parentUsesSize: true);
        return child.size;
      },
      place: (child, offset, shown) {
        final data = child.parentData! as _MetaParentData;
        data
          ..offset = offset
          ..shown = shown;
        // A dropped child is still laid out once, so nothing in the tree is
        // left dirty; it is simply never painted, hit or read.
        if (!shown) child.layout(const BoxConstraints());
      },
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, measure: (child, cc) => child.getDryLayout(cc));

  @override
  double computeMinIntrinsicWidth(double height) {
    final first = firstChild;
    return first == null ? 0 : first.getMinIntrinsicWidth(height);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    var child = firstChild;
    while (child != null) {
      if (width > 0) width += _spacing;
      width += child.getMaxIntrinsicWidth(height);
      child = (child.parentData! as _MetaParentData).nextSibling;
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _arrange(
    BoxConstraints(maxWidth: width),
    measure: (child, cc) {
      final w = math.min(
        child.getMaxIntrinsicWidth(double.infinity),
        cc.maxWidth,
      );
      return Size(w, child.getMaxIntrinsicHeight(w));
    },
  ).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _MetaParentData;
      if (data.shown) {
        final distance = child.getDistanceToActualBaseline(baseline);
        if (distance != null) return distance + data.offset.dy;
      }
      child = data.nextSibling;
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _MetaParentData;
      if (data.shown) context.paintChild(child, data.offset + offset);
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as _MetaParentData;
      if (data.shown) {
        final hit = result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (result, transformed) =>
              child!.hitTest(result, position: transformed),
        );
        if (hit) return true;
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _MetaParentData;
      if (data.shown) visitor(child);
      child = data.nextSibling;
    }
  }
}
