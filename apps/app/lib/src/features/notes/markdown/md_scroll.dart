/// Scrolling a rendered document to a BLOCK (DESIGN §29 D13/D16, OPH-249).
///
/// OPH-248 deferred this on purpose: the block → source-line map has existed
/// since OPH-247, but a line means nothing to a scroll view until something
/// knows how tall each block is. The outline, the anchors and the split view's
/// sync all want the same answer, so it is one mechanism, here.
///
/// **No new dependency.** `scrollable_positioned_list` solves exactly this and
/// was the obvious reach; it is not taken because the whole job is a height
/// cache and two frames of correction, and AGENTS §1.6 asks a dependency to
/// earn itself. What it costs instead is written down below: the first jump
/// into unbuilt territory is an ESTIMATE, and estimates are corrected rather
/// than trusted.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Owns the scroll position of one rendered document.
class AwMarkdownController extends ChangeNotifier {
  AwMarkdownController() {
    scroll.addListener(_onScroll);
  }

  final ScrollController scroll = ScrollController();

  /// Measured heights of blocks that have been built, by index. A lazy list
  /// only ever knows about what it has drawn, so this fills in as the reader
  /// moves and the estimates get better the more of the document they see.
  final Map<int, double> _heights = {};

  int _blockCount = 0;
  int _firstVisible = 0;

  /// The topmost block currently on screen — what the outline highlights.
  int get firstVisibleBlock => _firstVisible;

  void reportBlockCount(int count) => _blockCount = count;

  void reportHeight(int index, double height) {
    if (height <= 0) return;
    final previous = _heights[index];
    if (previous != null && (previous - height).abs() < 0.5) return;
    _heights[index] = height;
  }

  /// The average of what we have measured — the stand-in for anything we have
  /// not. Zero measurements means zero estimate, which is honest: the jump
  /// then simply starts from the top and corrects.
  double get _averageHeight => _heights.isEmpty
      ? 0
      : _heights.values.reduce((a, b) => a + b) / _heights.length;

  double _offsetOf(int index) {
    var offset = 0.0;
    final average = _averageHeight;
    for (var i = 0; i < index && i < _blockCount; i++) {
      offset += _heights[i] ?? average;
    }
    return offset;
  }

  void _onScroll() {
    if (!scroll.hasClients) return;
    final target = scroll.offset;
    var cumulative = 0.0;
    final average = _averageHeight;
    for (var i = 0; i < _blockCount; i++) {
      final height = _heights[i] ?? average;
      if (cumulative + height > target) {
        if (i != _firstVisible) {
          _firstVisible = i;
          notifyListeners();
        }
        return;
      }
      cumulative += height;
    }
  }

  /// Scrolls [index] to the top of the viewport.
  ///
  /// Estimate, settle, re-estimate. One pass lands close; the second uses the
  /// heights the first pass caused to be BUILT, which is why a jump deep into
  /// an unread document still arrives.
  Future<void> jumpToBlock(int index) async {
    if (!scroll.hasClients) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      final target = _offsetOf(
        index,
      ).clamp(0.0, scroll.position.maxScrollExtent);
      if ((scroll.offset - target).abs() < 1) break;
      scroll.jumpTo(target);
      await SchedulerBinding.instance.endOfFrame;
      if (!scroll.hasClients) return;
    }
  }

  @override
  void dispose() {
    scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }
}

/// Reports its own height to [controller] once it has one.
class MdMeasuredBlock extends StatefulWidget {
  const MdMeasuredBlock({
    super.key,
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final AwMarkdownController controller;
  final Widget child;

  @override
  State<MdMeasuredBlock> createState() => _MdMeasuredBlockState();
}

class _MdMeasuredBlockState extends State<MdMeasuredBlock> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(MdMeasuredBlock old) {
    super.didUpdateWidget(old);
    _report();
  }

  void _report() {
    // After layout, not during it: a size read in `build` is last frame's.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size != null) {
        widget.controller.reportHeight(widget.index, size.height);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
