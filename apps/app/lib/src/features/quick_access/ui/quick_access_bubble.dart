import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kv/local_kv.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/count_badge.dart';
import 'bubble_physics.dart';
import 'quick_access_row.dart';

/// Is the floating button switched on? Factory: yes (DESIGN §23 Q5) — and the
/// feature is never gesture-only, so switching it off moves the entry point to
/// the Home app bar rather than removing it.
final quickBubbleEnabledProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('alliswell_quick_bubble_enabled', fallback: true),
);

/// Where the user parked it — device-local, tolerant of junk.
final quickBubblePositionProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(
    'alliswell_quick_bubble_pos',
    fallback: encodeBubblePosition(kBubbleFactoryPosition),
  ),
);

/// Has the one-time introduction been shown?
final quickBubbleHintedProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('alliswell_quick_bubble_hinted', fallback: false),
);

/// The draggable button itself (DESIGN §23 Q4/Q4a/Q4b).
///
/// It positions itself inside [viewport] from the stored edge + height
/// fraction; the parent only says where the safe area and keyboard are.
class QuickAccessBubble extends ConsumerStatefulWidget {
  const QuickAccessBubble({
    super.key,
    required this.viewport,
    required this.safeArea,
    required this.keyboardInset,
    required this.onTap,
    this.badge = 0,
    this.badgeSemantics = '',
    this.contentScrolling,
  });

  final Size viewport;
  final EdgeInsets safeArea;
  final double keyboardInset;
  final VoidCallback onTap;

  /// EE-294: what the pinned entries are counting (the approvals waiting on
  /// this person). Zero draws nothing.
  final int badge;
  final String badgeSemantics;

  /// True while the content under the button scrolls (OPH-359, UI-AUDIT #57).
  final ValueListenable<bool>? contentScrolling;

  @override
  ConsumerState<QuickAccessBubble> createState() => _QuickAccessBubbleState();
}

class _QuickAccessBubbleState extends ConsumerState<QuickAccessBubble> {
  Offset? _dragCentre;
  bool _idle = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _restartIdleTimer();
    widget.contentScrolling?.addListener(_onScrolling);
  }

  @override
  void didUpdateWidget(QuickAccessBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentScrolling != widget.contentScrolling) {
      oldWidget.contentScrolling?.removeListener(_onScrolling);
      widget.contentScrolling?.addListener(_onScrolling);
    }
  }

  @override
  void dispose() {
    widget.contentScrolling?.removeListener(_onScrolling);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onScrolling() {
    if (mounted) setState(() {});
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(kBubbleIdleDelay, () {
      if (mounted) setState(() => _idle = true);
    });
    if (_idle) _idle = false;
  }

  BubblePosition get _position =>
      parseBubblePosition(ref.watch(quickBubblePositionProvider));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = bubbleOrigin(
      _position,
      widget.viewport,
      widget.safeArea,
      widget.keyboardInset,
    );
    final centre =
        _dragCentre ??
        origin + const Offset(kBubbleDiameter / 2, kBubbleDiameter / 2);
    final topLeft = _dragCentre == null
        ? origin
        : centre - const Offset(kBubbleDiameter / 2, kBubbleDiameter / 2);
    final dragging = _dragCentre != null;
    // EE-294 (DESIGN §23 Q4b): a count is text somebody is asked to read,
    // and the 40 % dim is sanctioned only for a control that carries none —
    // so while a count shows, the button neither recedes nor dims AT REST.
    // OPH-359 (UI-AUDIT #57): but while the person is scrolling the content
    // under it, it gets out of the way whatever it carries. The count itself
    // is painted outside the slide and the fade, so it is never dimmed.
    final scrolling = widget.contentScrolling?.value ?? false;
    final receded = !dragging && (scrolling || (_idle && widget.badge == 0));

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // R3-2 (OPH-363): the drag is a pointer gesture, not something to
        // announce. Left in, the pan recognisers dressed the button as a
        // SCROLL container (scrollUp/Down/Left/Right), and the web engine
        // drew that node as a scrollable region the size of the screen — a
        // focus ring around everything, "Quick access" under any touch. The
        // button's one accessible action is the tap, declared below.
        excludeFromSemantics: true,
        // `.down`, not the default: `.start` swallows the movement before the
        // drag is recognised, and the button trailed the finger by that slop
        // for the whole drag (#17).
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => setState(() {
          _dragCentre =
              origin + const Offset(kBubbleDiameter / 2, kBubbleDiameter / 2);
          _restartIdleTimer();
        }),
        // Onto the FIELD, never onto `centre`: that local is fixed when this
        // build ran, and a touch panel delivers several moves per frame. Each
        // one started again from the same stale point, so all but the last
        // were dropped and the button fell behind the finger (#17).
        onPanUpdate: (details) => setState(
          () => _dragCentre = (_dragCentre ?? centre) + details.delta,
        ),
        onPanEnd: (_) {
          final snapped = snapToEdge(
            _dragCentre ?? centre,
            widget.viewport,
            widget.safeArea,
            widget.keyboardInset,
          );
          ref
              .read(quickBubblePositionProvider.notifier)
              .set(encodeBubblePosition(snapped));
          setState(() => _dragCentre = null);
          _restartIdleTimer();
        },
        onTap: () {
          _restartIdleTimer();
          setState(() {});
          widget.onTap();
        },
        child: Semantics(
          container: true,
          button: true,
          enabled: true,
          onTap: () {
            _restartIdleTimer();
            widget.onTap();
          },
          label: widget.badge > 0
              ? '${'quick.title'.tr()}, ${widget.badgeSemantics}'
              : 'quick.title'.tr(),
          excludeSemantics: widget.badge > 0,
          child: SizedBox(
            // The BOX never moves or shrinks: 56 px stays 56 px, so the target
            // survives the idle recede (DESIGN §23 Q4a).
            width: kBubbleDiameter,
            height: kBubbleDiameter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedSlide(
                    duration: AwMotion.base,
                    curve: AwMotion.enter,
                    offset: Offset(
                      receded
                          ? recedePaintDx(_position.edge, 1) / kBubbleDiameter
                          : 0,
                      0,
                    ),
                    // opacity-ok: the one sanctioned exception to §20 C3's ban on
                    // `Opacity` for calm, named in DESIGN §22 Q4b — a resting control
                    // carries no text anyone is asked to read, the first touch
                    // restores it in full, and its colour pair is contrast-checked at
                    // FULL opacity. The 40 % is the platform's own default for a
                    // receded control, not a taste call (OPH-196).
                    child: AnimatedOpacity(
                      duration: AwMotion.base,
                      opacity: receded ? kBubbleIdleOpacity : 1,
                      child: Material(
                        elevation: dragging ? 8 : 4,
                        color: theme.colorScheme.primaryContainer,
                        shape: const CircleBorder(),
                        child: Center(
                          child: Icon(
                            kQuickAccessIcon,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Painted OUTSIDE the slide and the fade, so it is never
                // dimmed and never slides under the screen's edge.
                if (widget.badge > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: AwCountBadge(
                      badgeKey: const Key('quick-bubble-badge'),
                      count: widget.badge,
                      semanticsLabel: widget.badgeSemantics,
                      ring: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-time introduction next to the button.
///
/// Not a `Tooltip`: the bubble lives above the Navigator, where there is no
/// `Overlay` ancestor, and `Tooltip` needs one. So the hint is an ordinary
/// bubble-shaped label in the same `Stack`, dismissed by a tap or by time.
class QuickBubbleIntro extends ConsumerStatefulWidget {
  const QuickBubbleIntro({super.key, required this.anchor, required this.edge});

  final Offset anchor;
  final BubbleEdge edge;

  @override
  ConsumerState<QuickBubbleIntro> createState() => _QuickBubbleIntroState();
}

class _QuickBubbleIntroState extends ConsumerState<QuickBubbleIntro> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 6), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    if (mounted) ref.read(quickBubbleHintedProvider.notifier).set(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: widget.anchor.dy + kBubbleDiameter + AwSpace.x2,
      left: widget.edge == BubbleEdge.left ? AwSpace.x3 : null,
      right: widget.edge == BubbleEdge.right ? AwSpace.x3 : null,
      child: GestureDetector(
        onTap: _dismiss,
        child: Material(
          color: theme.colorScheme.inverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x3,
              vertical: AwSpace.x2,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                'quick.bubbleIntro'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clears every device-local quick-access preference — used by tests, and the
/// single place that knows the key names.
Future<void> resetQuickAccessPrefs() async {
  for (final key in const [
    'alliswell_quick_bubble_enabled',
    'alliswell_quick_bubble_pos',
    'alliswell_quick_bubble_hinted',
    'alliswell_quick_rail_collapsed',
    'alliswell_quick_emoji_recents',
  ]) {
    await localKv.remove(key);
  }
}
