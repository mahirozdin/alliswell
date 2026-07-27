import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// How long the indicator stays up at minimum (DESIGN §15 R2). A local-first
/// refresh answers in milliseconds; a spinner that appears and vanishes in one
/// frame reads as "nothing happened".
const kAwRefreshMinDuration = Duration(milliseconds: 450);

/// Pull to refresh, one implementation for every section (DESIGN §15).
///
/// Wrap the screen's **scrollable**, never the whole body: the indicator is then
/// born under whatever stays pinned above it (filter chips, segmented buttons)
/// and over the first row — exactly where the user is looking (R1).
///
/// Two things the wrapped scrollable must do itself:
/// - carry `physics: AlwaysScrollableScrollPhysics()`, or a short/empty list
///   cannot be pulled at all;
/// - be the nearest scrollable to this widget — a nested scroll view swallows
///   the drag, so non-scrolling states (empty/error) pass
///   `physics: AlwaysScrollableScrollPhysics()` to `AwEmptyState`/`AwErrorState`
///   and become the scrollable themselves.
class AwRefresh extends StatelessWidget {
  const AwRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.indicatorKey,
    this.displacement,
  });

  /// The work. Returning **false** means "tell the user it did not work" (R4) —
  /// see `refreshSection`.
  final Future<bool> Function() onRefresh;

  final Widget child;

  /// Key on the [RefreshIndicator] itself, for tests that drive the gesture.
  final Key? indicatorKey;

  /// Resting distance from the top of [child]. Material's 40 is right whenever
  /// [child] already starts below the pinned rows; pass more only when it does
  /// not.
  final double? displacement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      key: indicatorKey,
      // Tokens, no glass: this rides over content, and glass is chrome-only
      // (DESIGN G1/R1).
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHigh,
      displacement: displacement ?? 40,
      onRefresh: () => runAwRefresh(context, onRefresh),
      child: child,
    );
  }
}

/// Runs a refresh the one way the app runs refreshes: hold the indicator for
/// [kAwRefreshMinDuration] (R2), and say so when it failed (R4). Shared by the
/// gesture ([AwRefresh]) and the pointer-only button ([AwRefreshAction]).
Future<void> runAwRefresh(
  BuildContext context,
  Future<bool> Function() onRefresh,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var ok = false;
  try {
    final results = await Future.wait([
      onRefresh(),
      Future<bool>.delayed(kAwRefreshMinDuration, () => true),
    ]);
    ok = results.first;
  } catch (_) {
    ok = false;
  }
  if (ok) return;
  // The visible data stays exactly as it was; we only say why.
  messenger?.showSnackBar(SnackBar(content: Text('common.refreshFailed'.tr())));
}

/// The pointer-only half of §15 (R5): a mouse wheel cannot overscroll, so wide
/// layouts get the same capability as a button in the section app bar. Spins
/// while the round is in flight and refuses to stack rounds.
class AwRefreshAction extends StatefulWidget {
  const AwRefreshAction({super.key, required this.onRefresh});

  final Future<bool> Function() onRefresh;

  @override
  State<AwRefreshAction> createState() => _AwRefreshActionState();
}

class _AwRefreshActionState extends State<AwRefreshAction> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runAwRefresh(context, widget.onRefresh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('section-refresh'),
      tooltip: 'common.refresh'.tr(),
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }
}
