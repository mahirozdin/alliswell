import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/fab_clearance.dart';

/// Counts the modal routes currently on top (OPH-200).
///
/// The floating quick-access button lives above the whole Navigator, so it
/// would otherwise float over dialogs and sheets — two competing surfaces, the
/// thing DESIGN §23 Q4 forbids. [PopupRoute] is exactly the right supertype:
/// `DialogRoute`, `ModalBottomSheetRoute` and popup menus all extend it, while
/// snack bars (ScaffoldMessenger) and `MenuAnchor` panels (OverlayPortal) are
/// correctly not routes at all.
///
/// A [ValueNotifier] rather than a Riverpod state, deliberately: `didPush` can
/// fire during a build (a route pushed from `initState`), and mutating a
/// provider there throws.
///
/// [outsideShell] (OPH-391): whether the top PAGE on the root navigator is a
/// page outside the shell — task detail, settings, a note opened by address.
/// The docked bubble rests in the shell bar's row; such a page has no bar, so
/// the bubble steps aside there instead of the page giving up a lane for it
/// (E-09: that lane was a ~100 pt dead band under every pushed screen).
class AwModalRouteObserver extends NavigatorObserver {
  final ValueNotifier<int> depth = ValueNotifier<int>(0);
  final ValueNotifier<bool> outsideShell = ValueNotifier<bool>(false);

  /// The root navigator's page routes, bottom to top.
  final List<Route<dynamic>> _rootPages = [];

  void _bump(int delta) {
    depth.value = (depth.value + delta).clamp(0, 999);
  }

  /// A page on the ROOT navigator: go_router merges this observer into every
  /// branch navigator too, and a branch's pages live inside the shell.
  static bool _isRootPage(Route<dynamic> route) {
    if (route is! PageRoute) return false;
    final navigator = route.navigator;
    if (navigator == null || !navigator.mounted) return false;
    return Navigator.maybeOf(navigator.context, rootNavigator: true) ==
        navigator;
  }

  bool _settleScheduled = false;
  bool _disposed = false;

  /// go_router changes the root's pages while the router BUILDS, and its
  /// navigator reports them from inside that build — where notifying a
  /// listener throws. Then the answer waits for the end of the frame.
  void _settle() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      _apply();
      return;
    }
    if (_settleScheduled) return;
    _settleScheduled = true;
    binding.addPostFrameCallback((_) {
      _settleScheduled = false;
      if (!_disposed) _apply();
    });
    binding.ensureVisualUpdate();
  }

  void _apply() {
    final top = _rootPages.isEmpty ? null : _rootPages.last;
    outsideShell.value = top != null && top.settings.name != kAwShellPageName;
  }

  void _addPage(Route<dynamic> route) {
    if (!_isRootPage(route)) return;
    _rootPages
      ..remove(route)
      ..add(route);
    _settle();
  }

  void _removePage(Route<dynamic> route) {
    if (_rootPages.remove(route)) _settle();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(1);
    _addPage(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(-1);
    _removePage(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(-1);
    _removePage(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PopupRoute) _bump(-1);
    if (newRoute is PopupRoute) _bump(1);
    final at = oldRoute == null ? -1 : _rootPages.indexOf(oldRoute);
    if (at >= 0 && newRoute != null && _isRootPage(newRoute)) {
      _rootPages[at] = newRoute;
      _settle();
    } else {
      if (oldRoute != null) _removePage(oldRoute);
      if (newRoute != null) _addPage(newRoute);
    }
  }

  void dispose() {
    _disposed = true;
    depth.dispose();
    outsideShell.dispose();
  }
}

/// ONE instance, registered on the root `GoRouter` only: go_router merges the
/// root observers into every branch navigator, so this sees both the dialogs
/// that go to the root and the bottom sheets that go to a branch.
final awModalObserverProvider = Provider<AwModalRouteObserver>((ref) {
  final observer = AwModalRouteObserver();
  ref.onDispose(observer.dispose);
  return observer;
});
