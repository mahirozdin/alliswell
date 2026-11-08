import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The app's popup menu button (OPH-398, DESIGN §26 M1).
///
/// It looks and behaves like Material's [PopupMenuButton] and takes the same
/// [PopupMenuItem] entries; the one difference is the menu's barrier.
///
/// Material's menu route gives its barrier ("Dismiss menu" to a screen
/// reader) the whole screen as its accessibility rect. The centre of that
/// rect — where VoiceOver draws the focus and where an accessibility tap
/// lands — is usually ON the menu, so "pressing" the barrier picked whatever
/// item lay under the middle of the screen (the Home view menu switched the
/// order to "Title"). Here the barrier's node covers only the largest free
/// strip beside the menu, so it sits where a tap really closes the menu and
/// never on an item. The barrier still covers the whole screen for touch.
class AwPopupMenuButton<T> extends StatefulWidget {
  const AwPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onCanceled,
    this.onOpened,
    this.tooltip,
    this.icon,
    this.iconSize,
    this.padding = const EdgeInsets.all(8),
    this.child,
    this.enabled = true,
  }) : assert(icon == null || child == null);

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final VoidCallback? onOpened;
  final String? tooltip;
  final Widget? icon;
  final double? iconSize;
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final bool enabled;

  @override
  State<AwPopupMenuButton<T>> createState() => AwPopupMenuButtonState<T>();
}

class AwPopupMenuButtonState<T> extends State<AwPopupMenuButton<T>> {
  bool _expanded = false;

  /// Opens the menu under the button, as a tap does.
  void showButtonMenu() {
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final button = context.findRenderObject()! as RenderBox;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final buttonRect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    widget.onOpened?.call();
    setState(() => _expanded = true);
    showAwMenu<T>(
      context: context,
      position: RelativeRect.fromRect(buttonRect, Offset.zero & overlay.size),
      items: items,
    ).then((value) {
      if (!mounted) return;
      setState(() => _expanded = false);
      if (value == null) {
        widget.onCanceled?.call();
      } else {
        widget.onSelected?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tooltip =
        widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip;
    final child = widget.child;
    if (child != null) {
      return Semantics(
        expanded: _expanded,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: widget.enabled ? showButtonMenu : null,
            child: child,
          ),
        ),
      );
    }
    final popupTheme = PopupMenuTheme.of(context);
    final iconTheme = IconTheme.of(context);
    return IconButton(
      icon: Semantics(
        expanded: _expanded,
        child: widget.icon ?? Icon(Icons.adaptive.more),
      ),
      padding: widget.padding,
      iconSize: widget.iconSize ?? popupTheme.iconSize ?? iconTheme.size,
      color: popupTheme.iconColor ?? iconTheme.color,
      tooltip: tooltip,
      onPressed: widget.enabled ? showButtonMenu : null,
    );
  }
}

/// Shows [items] in a menu at [position] (the button's rect in the
/// navigator's overlay); `null` when it was closed without a choice.
Future<T?> showAwMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) {
  assert(items.isNotEmpty);
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final String? semanticLabel = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => null,
    _ => localizations.popupMenuLabel,
  };
  return navigator.push(
    _AwMenuRoute<T>(
      position: position,
      items: items,
      semanticLabel: semanticLabel,
      barrierLabel: localizations.menuDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
    ),
  );
}

/// Where the barrier's accessibility rect goes: the largest of the four
/// strips of [screen] around [menu], as the insets that cut [screen] down to
/// it. Its centre is always on the barrier, never on the menu (OPH-398).
@visibleForTesting
EdgeInsets awBarrierSemanticsClip(Size screen, Rect menu) {
  final above = screen.width * menu.top;
  final below = screen.width * (screen.height - menu.bottom);
  final left = menu.left * screen.height;
  final right = (screen.width - menu.right) * screen.height;
  final best = [above, below, left, right].reduce((a, b) => a >= b ? a : b);
  if (best == above) return EdgeInsets.only(bottom: screen.height - menu.top);
  if (best == below) return EdgeInsets.only(top: menu.bottom);
  if (best == left) return EdgeInsets.only(right: screen.width - menu.left);
  return EdgeInsets.only(left: menu.right);
}

const _kMenuDuration = Duration(milliseconds: 300);
const _kMenuCloseIntervalEnd = 2.0 / 3.0;
const _kMenuWidthStep = 56.0;
const _kMenuMinWidth = 2.0 * _kMenuWidthStep;
const _kMenuMaxWidth = 5.0 * _kMenuWidthStep;
const _kMenuScreenPadding = 8.0;

class _AwMenuRoute<T> extends PopupRoute<T> {
  _AwMenuRoute({
    required this.position,
    required this.items,
    required this.semanticLabel,
    required this.barrierLabel,
    required this.capturedThemes,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final String? semanticLabel;
  final CapturedThemes capturedThemes;

  /// The barrier's semantics clip; the layout below sets it from where the
  /// menu lands.
  final ValueNotifier<EdgeInsets> _barrierClip = ValueNotifier(EdgeInsets.zero);

  CurvedAnimation? _curve;

  @override
  Animation<double> createAnimation() => _curve ??= CurvedAnimation(
    parent: super.createAnimation(),
    curve: Curves.linear,
    reverseCurve: const Interval(0.0, _kMenuCloseIntervalEnd),
  );

  @override
  Duration get transitionDuration => _kMenuDuration;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  @override
  Widget buildModalBarrier() => ModalBarrier(
    dismissible: barrierDismissible,
    semanticsLabel: barrierLabel,
    barrierSemanticsDismissible: semanticsDismissible,
    clipDetailsNotifier: _barrierClip,
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final padding = MediaQuery.paddingOf(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: CustomSingleChildLayout(
        delegate: _AwMenuLayout(
          position: position,
          padding: padding,
          textDirection: Directionality.of(context),
          onPlaced: (screen, menu) =>
              _barrierClip.value = awBarrierSemanticsClip(screen, menu),
        ),
        child: capturedThemes.wrap(_AwMenu<T>(route: this)),
      ),
    );
  }

  @override
  void dispose() {
    _curve?.dispose();
    _barrierClip.dispose();
    super.dispose();
  }
}

/// Material's popup menu placement: aligned with the button's top, growing
/// away from the nearer side edge, kept 8 px inside the safe area.
class _AwMenuLayout extends SingleChildLayoutDelegate {
  _AwMenuLayout({
    required this.position,
    required this.padding,
    required this.textDirection,
    required this.onPlaced,
  });

  final RelativeRect position;
  final EdgeInsets padding;
  final TextDirection textDirection;
  final void Function(Size screen, Rect menu) onPlaced;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        constraints.biggest,
      ).deflate(const EdgeInsets.all(_kMenuScreenPadding) + padding);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final growLeft = position.left == position.right
        ? textDirection == TextDirection.rtl
        : position.left > position.right;
    var x = growLeft
        ? size.width - position.right - childSize.width
        : position.left;
    var y = position.top;
    final minX = _kMenuScreenPadding + padding.left;
    final maxX =
        size.width - childSize.width - _kMenuScreenPadding - padding.right;
    final minY = _kMenuScreenPadding + padding.top;
    final maxY =
        size.height - childSize.height - _kMenuScreenPadding - padding.bottom;
    if (x < minX) {
      x = minX;
    } else if (x > maxX) {
      x = maxX;
    }
    if (y < minY) {
      y = minY;
    } else if (y > maxY) {
      y = maxY;
    }
    final offset = Offset(x, y);
    onPlaced(size, offset & childSize);
    return offset;
  }

  @override
  bool shouldRelayout(_AwMenuLayout old) =>
      position != old.position ||
      padding != old.padding ||
      textDirection != old.textDirection;
}

class _AwMenu<T> extends StatefulWidget {
  const _AwMenu({required this.route});

  final _AwMenuRoute<T> route;

  @override
  State<_AwMenu<T>> createState() => _AwMenuState<T>();
}

class _AwMenuState<T> extends State<_AwMenu<T>> {
  late final List<CurvedAnimation> _opacities;

  double get _unit => 1.0 / (widget.route.items.length + 1.5);

  @override
  void initState() {
    super.initState();
    final unit = _unit;
    _opacities = [
      for (var i = 0; i < widget.route.items.length; i++)
        CurvedAnimation(
          parent: widget.route.animation!,
          curve: Interval(
            (i + 1) * unit,
            clampDouble((i + 1) * unit + 1.5 * unit, 0, 1),
          ),
        ),
    ];
  }

  @override
  void dispose() {
    for (final o in _opacities) {
      o.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupTheme = PopupMenuTheme.of(context);
    final route = widget.route;
    final animation = route.animation!;
    final unit = _unit;
    final opacity = CurveTween(curve: const Interval(0.0, 1.0 / 3.0));
    final width = CurveTween(curve: Interval(0.0, unit));
    final height = CurveTween(curve: Interval(0.0, unit * route.items.length));

    final Widget menu = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _kMenuMinWidth,
        maxWidth: _kMenuMaxWidth,
      ),
      child: IntrinsicWidth(
        stepWidth: _kMenuWidthStep,
        child: Semantics(
          role: SemanticsRole.menu,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: route.semanticLabel,
          child: SingleChildScrollView(
            padding:
                popupTheme.menuPadding ??
                const EdgeInsets.symmetric(vertical: 8),
            child: ListBody(
              children: [
                for (var i = 0; i < route.items.length; i++)
                  FadeTransition(opacity: _opacities[i], child: route.items[i]),
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => FadeTransition(
        opacity: opacity.animate(animation),
        child: Material(
          type: MaterialType.card,
          shape:
              popupTheme.shape ??
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
          color: popupTheme.color ?? theme.colorScheme.surfaceContainer,
          elevation: popupTheme.elevation ?? 3,
          shadowColor: popupTheme.shadowColor ?? theme.colorScheme.shadow,
          surfaceTintColor: popupTheme.surfaceTintColor ?? Colors.transparent,
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            widthFactor: width.evaluate(animation),
            heightFactor: height.evaluate(animation),
            child: child,
          ),
        ),
      ),
      child: menu,
    );
  }
}
