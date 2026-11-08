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
/// should retract (ADR-0062 §3, OPH-397 polish 4 T-01): a scroll toward the
/// end of a list of more than [_threshold] retracts it; scrolling back, or
/// [_settle] of stillness, brings it back.
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

/// The cluster, retracted while its [AwFabScrollScope] says the list is
/// scrolling down, and while the on-screen keyboard is up (OPH-397 polish 4,
/// T-01) — in [AwMotion.fast], at once with reduced motion.
///
/// Until polish 4 it only stepped down [kAwFabScrollDrop] and stayed whole:
/// the microphone and "+" went on covering the right end of every row a
/// reader scrolled past and the last visible title, and with the quick add
/// focused they stood on the calendar and a section's arrow (persona
/// recheck 2).
///
/// Retracting is a scale to nothing while it steps down — never an `Opacity`
/// layer (DESIGN §20 C3: nothing is ever drawn half-legible at rest). A
/// retracted cluster takes no touch and leaves the semantics tree, so a tap
/// meant for the row beneath reaches the row.
class AwFabDrop extends StatelessWidget {
  const AwFabDrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_FabDropped>()
        ?.notifier;
    final dropped = scope?.value ?? false;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final retracted = dropped || keyboard;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      key: const Key('shell-fab-retract'),
      ignoring: retracted,
      child: ExcludeSemantics(
        excluding: retracted,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: retracted ? 1 : 0),
          duration: reduced ? Duration.zero : AwMotion.fast,
          curve: AwMotion.enter,
          builder: (context, t, child) => Transform.translate(
            offset: Offset(0, kAwFabScrollDrop * t),
            child: Transform.scale(scale: 1 - t, child: child),
          ),
          child: child,
        ),
      ),
    );
  }
}
