import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/modal_observer.dart';
import '../../../router.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/document_surface.dart';
import '../../../widgets/fab_clearance.dart';
import '../../auth/providers.dart';
import '../../onboarding/tour.dart';
import '../../../notifications/alarm_overlay.dart';
import '../pinned.dart';
import '../providers.dart';
import 'bubble_physics.dart';
import 'quick_access_bubble.dart';
import 'quick_access_panel.dart';

// The auth and splash screens are exactly the screens with no session, so the
// bubble's "not here" rule is the session itself (DESIGN §23 Q4). Watching the
// ROUTER instead would mean listening to the router delegate from inside
// `MaterialApp.builder` — i.e. rebuilding during the router's own build, which
// Flutter refuses ('!_dirty').

/// Puts the floating button above EVERYTHING (OPH-200).
///
/// It wraps `MaterialApp.builder`'s child, which is the router's Navigator —
/// the only seam above every route. The shell's own `Stack` is inside a route,
/// so a bubble there would vanish on task detail and settings, which is
/// exactly where a navigation shortcut earns its keep.
///
/// The gates run cheapest-first on purpose: the rows stream is only subscribed
/// once every cheap condition has passed, so existing widget tests (empty
/// replica, wide surface) gain no new work at all.
class QuickAccessBubbleHost extends ConsumerWidget {
  const QuickAccessBubbleHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    // Wide layouts own the rail section; the bubble is the phone's answer.
    if (width >= kAwWideBreakpoint) return child;
    // Signed out (or still restoring) = the login/register/splash screens.
    if (ref.watch(authControllerProvider).value == null) return child;
    if (!ref.watch(quickBubbleEnabledProvider)) return child;
    // The tour and the alarm ring screen paint INSIDE the shell, i.e. below
    // this layer — without these gates the bubble would float over both.
    if (ref.watch(tourControllerProvider).running) return child;
    if (ref.watch(alarmOverlayControllerProvider).ringing != null) return child;

    // OPH-271: and it does not float over a note being read or written. This
    // layer sits above the Router, so it follows navigation through the
    // delegate rather than `GoRouterState` (which needs a route ancestor).
    return AwDocumentRouteBuilder(
      builder: (context, isDocument) =>
          isDocument ? child : _BubbleLayer(child: child),
    );
  }
}

/// The layer that actually watches the rail's contents.
class _BubbleLayer extends ConsumerStatefulWidget {
  const _BubbleLayer({required this.child});

  final Widget child;

  @override
  ConsumerState<_BubbleLayer> createState() => _BubbleLayerState();
}

class _BubbleLayerState extends ConsumerState<_BubbleLayer> {
  /// Whether something under the button is being scrolled (OPH-359, UI-AUDIT
  /// #57). This layer is above every route, so one listener hears them all.
  final _scrolling = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _scrolling.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null)) {
      _scrolling.value = true;
    } else if (notification is ScrollEndNotification) {
      _scrolling.value = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final rows = ref.watch(quickAccessRowsProvider).value ?? const [];
    // EE-294 (DESIGN §23 Q10): an entry the app pins is something to open —
    // the Approvals door of somebody with no shortcuts of their own still
    // needs a way in on a phone, and this button is it.
    final pins = ref.watch(quickAccessPinsProvider);
    // Nothing to shortcut to yet: the first item is added from an entity menu
    // (DESIGN §23 Q5), and an empty button would be a dead control.
    if (rows.isEmpty && pins.isEmpty) return child;
    final badge = ref.watch(quickAccessPinsBadgeProvider);

    final media = MediaQuery.of(context);
    final observer = ref.watch(awModalObserverProvider);
    final position = parseBubblePosition(
      ref.watch(quickBubblePositionProvider),
    );
    final hinted = ref.watch(quickBubbleHintedProvider);
    final resting = bubbleOrigin(
      position,
      media.size,
      media.padding,
      media.viewInsets.bottom,
    );

    return Stack(
      // The child is the whole app: loose constraints would starve it.
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // UI-AUDIT #57 (retest): every route under the button learns how
          // high it reaches, so its lists and forms end above it.
          child: AwBubbleClearance(
            extent: bubbleClearance(resting, media.size),
            child: child,
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: observer.depth,
          builder: (context, depth, _) {
            // A dialog or a sheet is up — including this feature's own panel.
            // A floating control over a modal is two competing surfaces.
            if (depth > 0) return const SizedBox.shrink();
            final origin = bubbleOrigin(
              position,
              media.size,
              media.padding,
              media.viewInsets.bottom,
            );
            return Stack(
              children: [
                QuickAccessBubble(
                  viewport: media.size,
                  safeArea: media.padding,
                  keyboardInset: media.viewInsets.bottom,
                  badge: badge,
                  contentScrolling: _scrolling,
                  badgeSemantics: pins
                      .where((pin) => pin.badge > 0)
                      .map((pin) => pin.badgeSemantics ?? '${pin.badge}')
                      .join(', '),
                  onTap: () {
                    final rootContext = awRootNavigatorKey.currentContext;
                    if (rootContext == null) return;
                    // The host has no Navigator ancestor of its own; opening
                    // on the root is also what makes the observer above hide
                    // the button while the panel is open.
                    showQuickAccessPanel(rootContext);
                  },
                ),
                if (!hinted)
                  QuickBubbleIntro(anchor: origin, edge: position.edge),
              ],
            );
          },
        ),
      ],
    );
  }
}
