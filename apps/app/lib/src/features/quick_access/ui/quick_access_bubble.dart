import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kv/local_kv.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
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
  });

  final Size viewport;
  final EdgeInsets safeArea;
  final double keyboardInset;
  final VoidCallback onTap;

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
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
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
    final receded = _idle && !dragging;

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() {
          _dragCentre =
              origin + const Offset(kBubbleDiameter / 2, kBubbleDiameter / 2);
          _restartIdleTimer();
        }),
        onPanUpdate: (details) =>
            setState(() => _dragCentre = centre + details.delta),
        onPanEnd: (_) {
          final snapped = snapToEdge(
            centre,
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
          button: true,
          label: 'quick.title'.tr(),
          child: SizedBox(
            // The BOX never moves or shrinks: 56 px stays 56 px, so the target
            // survives the idle recede (DESIGN §23 Q4a).
            width: kBubbleDiameter,
            height: kBubbleDiameter,
            child: AnimatedSlide(
              duration: AwMotion.base,
              curve: AwMotion.enter,
              offset: Offset(
                receded
                    ? recedePaintDx(_position.edge, 1) / kBubbleDiameter
                    : 0,
                0,
              ),
              child: AnimatedOpacity(
                duration: AwMotion.base,
                // The one sanctioned exception to §20 C3's ban on `Opacity`
                // for calm: a resting control carries no text anyone is asked
                // to read, and the first touch restores it in full. Its colour
                // pair is contrast-checked at FULL opacity.
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
