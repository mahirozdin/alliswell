import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One action of the ring screen's grid (#46, DESIGN §11 direction A): every
/// snooze preset, "Pick a time…", "Silence indefinitely", "Start the sound"
/// and "Try again" are this one component, so the grid cannot drift back into
/// three button styles of three widths.
///
/// A solid `surface` capsule with a 1 px `outline` edge — an outlined pill
/// with an empty middle read as "disabled" on the urgency wash. Line 1 says
/// the action ([label], `labelLarge` w600 `onSurface`), line 2 what it will do
/// ([subline], `labelSmall` tabular `onSurfaceVariant`, "rings at 09:05").
///
/// It never looks disabled: [onPressed] is required, and a press that takes
/// longer than 300 ms shows [busy] as a 20 pt spinner in place of the label
/// while every other tile stays as it was (#46: a grey button on an alarm
/// reads as "this alarm is stuck").
class AwAlarmActionTile extends StatefulWidget {
  const AwAlarmActionTile({
    super.key,
    required this.label,
    required this.onPressed,
    this.subline,
    this.icon,
    this.busy = false,
    this.wrap = false,
    this.minHeight = kAwAlarmTileHeight,
  });

  final String label;
  final String? subline;
  final IconData? icon;

  /// Runs on tap — the screen silences inside it, so it comes before the
  /// selection haptic.
  final VoidCallback onPressed;

  /// The pressed action is still running after 300 ms.
  final bool busy;

  /// One tile per row (text scale > 1.3): the lines wrap and the tile grows.
  /// In the two-column grid each line stays on one line and scales down
  /// instead, so every tile keeps one height.
  final bool wrap;

  final double minHeight;

  @override
  State<AwAlarmActionTile> createState() => _AwAlarmActionTileState();
}

/// The grid tile's height (G4: ring tiles 56).
const double kAwAlarmTileHeight = 56;

class _AwAlarmActionTileState extends State<AwAlarmActionTile> {
  bool _pressed = false;
  bool _focused = false;

  void _tap() {
    // Silence first (the screen's handler), then the haptic.
    widget.onPressed();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    const press = Duration(milliseconds: 150);
    final fill = _pressed
        ? Color.alphaBlend(
            scheme.onSurface.withValues(alpha: 0.12),
            scheme.surface,
          )
        : scheme.surface;

    Widget line(String value, TextStyle? style) {
      final t = Text(
        value,
        style: style,
        textAlign: TextAlign.center,
        maxLines: widget.wrap ? null : 1,
        softWrap: widget.wrap,
      );
      return widget.wrap ? t : FittedBox(fit: BoxFit.scaleDown, child: t);
    }

    final labelStyle = text.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    Widget first = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AwSpace.x2),
        ],
        Flexible(child: line(widget.label, labelStyle)),
      ],
    );
    if (widget.busy) {
      first = Stack(
        alignment: Alignment.center,
        children: [
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: first,
          ),
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AwSpace.x3,
          vertical: AwSpace.x1,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              first,
              if (widget.subline != null)
                line(
                  widget.subline!,
                  awTabular(
                    text.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return AnimatedScale(
      scale: _pressed && !reduce ? 0.97 : 1,
      duration: press,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: fill),
        duration: reduce ? Duration.zero : press,
        builder: (context, color, child) => Material(
          color: color,
          clipBehavior: Clip.antiAlias,
          // A visible 2 px ring on keyboard focus; 1 px outline otherwise.
          shape: StadiumBorder(
            side: _focused
                ? BorderSide(color: scheme.primary, width: 2)
                : BorderSide(color: scheme.outline),
          ),
          child: child,
        ),
        child: Semantics(
          button: true,
          child: MergeSemantics(
            child: InkWell(
              onTap: _tap,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              onFocusChange: (v) => setState(() => _focused = v),
              customBorder: const StadiumBorder(),
              splashFactory: NoSplash.splashFactory,
              // The pressed overlay is the fill above, on a 150 ms clock.
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.transparent
                    : null,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
