import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'list_detail.dart';

/// A section screen's own create button, lent to the shell's action
/// cluster (OPH-397 polish 2, DESIGN §44 F3).
///
/// A screen that lives inside a section has its own Scaffold, and that
/// Scaffold placed its floating button by itself, at its own end — exactly
/// where the shell's cluster put the microphone. The microphone covered the
/// extended "new request" button ("New r…"), on the phone and the desktop.
///
/// Put this in the screen's `floatingActionButton` slot. Inside the shell
/// ([AwSectionFabHost] above it) it draws nothing and hands [child] to the
/// shell, which stands it on the gutter with the microphone 8 to its left —
/// the same cluster as Home's "+". The hand-over lasts while the screen is
/// the one on show: its branch is the active one (`TickerMode`) and its
/// route is the top of that branch. Outside a shell (a page on the root
/// navigator, a test) [child] floats in the screen's own Scaffold, as
/// before.
class AwSectionFab extends ConsumerStatefulWidget {
  const AwSectionFab({super.key, required this.child, this.paneKind});

  final Widget child;

  /// The screen's list–detail pane, if it has one (`AwListDetailScope`):
  /// while it is open the cluster stands left of it (DESIGN §51 D2).
  final String? paneKind;

  @override
  ConsumerState<AwSectionFab> createState() => _AwSectionFabState();
}

class _AwSectionFabState extends ConsumerState<AwSectionFab> {
  late final AwSectionFabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(awSectionFabProvider.notifier);
  }

  @override
  void dispose() {
    // The tree is locked while it unmounts: say it after the frame.
    final controller = _controller;
    _later(() => controller.release(this));
    super.dispose();
  }

  void _later(VoidCallback action) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => action())
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (!AwSectionFabHost.within(context)) return widget.child;
    final onShow =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final kind = widget.paneKind;
    final paneOpen = kind != null && AwListDetailScope.isOpen(context, kind);
    final lent = AwLentFab(
      owner: this,
      // Its label stops growing at 1.3× (as the tab labels do, DESIGN §43
      // N4): at 2× text "New request" beside the microphone was wider than
      // a phone (R-02).
      fab: MediaQuery.withClampedTextScaling(
        maxScaleFactor: kAwFabLabelMaxScale,
        child: widget.child,
      ),
      endInset: paneOpen ? kAwDetailPaneWidth : 0,
    );
    _later(() {
      if (!mounted) return;
      onShow ? _controller.lend(lent) : _controller.release(this);
    });
    return const SizedBox.shrink();
  }
}

/// Where a lent button's label stops growing with the text size.
const double kAwFabLabelMaxScale = 1.3;

/// What a section screen lent the shell: the button, and how far from the
/// window's end its screen wants the cluster (an open detail pane).
@immutable
class AwLentFab {
  const AwLentFab({required this.owner, required this.fab, this.endInset = 0});

  final Object owner;
  final Widget fab;
  final double endInset;
}

class AwSectionFabController extends Notifier<AwLentFab?> {
  @override
  AwLentFab? build() => null;

  void lend(AwLentFab lent) {
    if (!ref.mounted) return;
    final now = state;
    if (now != null &&
        identical(now.owner, lent.owner) &&
        now.fab == lent.fab &&
        now.endInset == lent.endInset) {
      return;
    }
    state = lent;
  }

  void release(Object owner) {
    // The scope may be gone by the time a screen's dispose is said.
    if (!ref.mounted) return;
    if (identical(state?.owner, owner)) state = null;
  }
}

/// The button a section screen has lent the shell's cluster, if any.
final awSectionFabProvider =
    NotifierProvider<AwSectionFabController, AwLentFab?>(
      AwSectionFabController.new,
    );

/// Marks the shell's section content: an [AwSectionFab] under it lends its
/// button to the shell's cluster instead of drawing it.
class AwSectionFabHost extends InheritedWidget {
  const AwSectionFabHost({super.key, required super.child});

  static bool within(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AwSectionFabHost>() != null;

  @override
  bool updateShouldNotify(AwSectionFabHost oldWidget) => false;
}
