import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class AwModalRouteObserver extends NavigatorObserver {
  final ValueNotifier<int> depth = ValueNotifier<int>(0);

  void _bump(int delta) {
    depth.value = (depth.value + delta).clamp(0, 999);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(-1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PopupRoute) _bump(-1);
    if (newRoute is PopupRoute) _bump(1);
  }

  void dispose() => depth.dispose();
}

/// ONE instance, registered on the root `GoRouter` only: go_router merges the
/// root observers into every branch navigator, so this sees both the dialogs
/// that go to the root and the bottom sheets that go to a branch.
final awModalObserverProvider = Provider<AwModalRouteObserver>((ref) {
  final observer = AwModalRouteObserver();
  ref.onDispose(observer.dispose);
  return observer;
});
