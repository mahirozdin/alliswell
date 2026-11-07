import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Where the shell's action cluster stands (OPH-397, ADR-0062 §3/§4): its
/// end edge on the floating gutter ([awFloatGutter]), its bottom
/// Material's 16 above the content's bottom — on a phone, 16 above the
/// capsule's top.
///
/// The cluster is ONE widget (microphone, gap, "+") so the "+" lands on the
/// gutter whether the microphone is there or not; until OPH-397 the two
/// FABs were a full-width `Row` under `centerFloat`, and switching AI on
/// moved the "+" 8 pt (R-06).
class AwFabLocation extends StandardFabLocation with FabFloatOffsetY {
  const AwFabLocation(this.gutter);

  final double gutter;

  @override
  double getOffsetX(ScaffoldPrelayoutGeometry geometry, double adjustment) {
    return switch (geometry.textDirection) {
      TextDirection.rtl => geometry.minInsets.left + gutter - adjustment,
      TextDirection.ltr =>
        geometry.scaffoldSize.width -
            geometry.minInsets.right -
            gutter -
            geometry.floatingActionButtonSize.width +
            adjustment,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AwFabLocation && other.gutter == gutter;

  @override
  int get hashCode => gutter.hashCode;

  @override
  String toString() => 'AwFabLocation($gutter)';
}

/// Listens to the vertical scrolling under the cluster and says whether it
/// should step down (ADR-0062 §3): a scroll toward the end of a list of more
/// than [_threshold] lowers it [kAwFabScrollDrop]; scrolling back, or
/// [_settle] of stillness, raises it again.
///
/// Wrap the Scaffold whose `floatingActionButton` is an [AwFabDrop]: the
/// body's scroll notifications bubble up through the Scaffold to here, and
/// the button reads the answer from the same scope.
class AwFabScrollScope extends StatefulWidget {
  const AwFabScrollScope({super.key, required this.child});

  final Widget child;

  static const double _threshold = 24;
  static const Duration _settle = Duration(milliseconds: 600);

  @override
  State<AwFabScrollScope> createState() => _AwFabScrollScopeState();
}

class _AwFabScrollScopeState extends State<AwFabScrollScope> {
  final _dropped = ValueNotifier<bool>(false);
  double _travel = 0;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    _dropped.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      _settle?.cancel();
      _travel = 0;
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta < 0) {
        _travel = 0;
        _dropped.value = false;
      } else if (delta > 0) {
        _travel += delta;
        if (_travel > AwFabScrollScope._threshold) _dropped.value = true;
      }
    } else if (notification is ScrollEndNotification) {
      _settle?.cancel();
      _settle = Timer(AwFabScrollScope._settle, () {
        if (mounted) _dropped.value = false;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _FabDropped(notifier: _dropped, child: widget.child),
    );
  }
}

class _FabDropped extends InheritedNotifier<ValueNotifier<bool>> {
  const _FabDropped({required super.notifier, required super.child});
}

/// The cluster, lowered while its [AwFabScrollScope] says so — 150 ms,
/// at once with reduced motion. A translation, not a fade: the buttons stay
/// whole and tappable (DESIGN §20 C3).
class AwFabDrop extends StatelessWidget {
  const AwFabDrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_FabDropped>()
        ?.notifier;
    final dropped = scope?.value ?? false;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: dropped ? kAwFabScrollDrop : 0),
      duration: reduced ? Duration.zero : AwMotion.fast,
      curve: AwMotion.enter,
      builder: (context, dy, child) =>
          Transform.translate(offset: Offset(0, dy), child: child),
      child: child,
    );
  }
}
