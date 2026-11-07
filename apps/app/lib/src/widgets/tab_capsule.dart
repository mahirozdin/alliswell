import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass.dart';

/// One slot of the phone's [AwTabCapsule].
class AwTabItem {
  const AwTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.iconKey,
    this.selectedIconKey,
    this.onLongPress,
    this.longPressHint,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Anchors for the onboarding tour's spotlight (only one is mounted).
  final Key? iconKey;
  final Key? selectedIconKey;

  /// A second way in through this slot (Home's long press opens Quick
  /// Access, ADR-0062 §5), and what a screen reader says it does. Not
  /// offered while the large content viewer owns the long press (N4).
  final VoidCallback? onLongPress;
  final String? longPressHint;
}

/// The capsule's height (ADR-0062 §1, DESIGN §43 N1).
const double kAwTabCapsuleHeight = 64;

/// The selection's height: it stays inside its slot, 12 above and below.
const double kAwTabSelectionHeight = 40;

/// Inner side padding. With the capsule's 32 radius and the selection's 20,
/// 12 makes the outer selections concentric with the capsule's curve, so
/// neither the pill nor a label can reach the clipped corner (R-02).
const double kAwTabCapsulePadding = AwSpace.x3;

/// The smallest slot the layout may produce (DESIGN G4 on Android).
const double kAwMinTabSlot = 48;

/// Icon and label sizes (DESIGN §43 N2).
const double kAwTabIconSize = 22;
const double kAwTabLabelSize = 11;
const double kAwTabLabelLineHeight = 13;

/// Label text scaling stops here; past it a long press names the tab in a
/// large bubble instead (DESIGN §43 N4).
const double kAwTabLabelMaxScale = 1.3;

/// The phone's bottom navigation (OPH-396, ADR-0062): a 64 pt glass capsule
/// with equal slots, every one labelled.
///
/// Replaces Material 3's `NavigationBar`, whose 64 pt indicator squashed in
/// a 36–54 pt slot, which lifted the selected icon ≈10 pt above the others
/// and let the selected label run out of the capsule (R-01, R-02):
///
///  * every slot is the same width and every glyph sits on one centre line —
///    selecting a tab changes a colour and a glyph, and moves nothing;
///  * the label is one line, scaled down to fit its slot rather than clipped,
///    and never leaves the capsule;
///  * label scaling is clamped at 1.3; above that a long press shows the
///    name in a large bubble, and lifting the finger selects the slot under
///    it (iOS's large content viewer);
///  * each slot is one semantics node: button, selected, "Home\nTab 1 of 5".
class AwTabCapsule extends StatefulWidget {
  const AwTabCapsule({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AwTabItem> items;

  /// -1 draws no selection.
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<AwTabCapsule> createState() => _AwTabCapsuleState();
}

class _AwTabCapsuleState extends State<AwTabCapsule> {
  OverlayEntry? _bubble;
  int? _pressed;

  @override
  void dispose() {
    _hideBubble();
    super.dispose();
  }

  int _slotAt(Offset local, double width) {
    final inner = width - 2 * kAwTabCapsulePadding;
    final slot = inner / widget.items.length;
    final index = ((local.dx - kAwTabCapsulePadding) / slot).floor();
    return index.clamp(0, widget.items.length - 1);
  }

  void _showBubble(int index) {
    if (_pressed == index && _bubble != null) return;
    _pressed = index;
    _bubble?.remove();
    _bubble = null;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final top = box?.localToGlobal(Offset.zero).dy;
    final item = widget.items[index];
    _bubble = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        final bottom = top == null
            ? media.size.height / 2
            : media.size.height - top + AwSpace.x4;
        return Positioned(
          left: AwSpace.x4,
          right: AwSpace.x4,
          bottom: bottom,
          child: IgnorePointer(
            child: Center(child: _LargeLabel(item: item)),
          ),
        );
      },
    );
    overlay.insert(_bubble!);
  }

  void _hideBubble() {
    _bubble?.remove();
    _bubble = null;
    _pressed = null;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // The large content viewer is for people whose text is bigger than the
    // clamp lets the label be (DESIGN §43 N4).
    final bigText =
        scaler.scale(kAwTabLabelSize) / kAwTabLabelSize > kAwTabLabelMaxScale;
    final count = widget.items.length;
    final localizations = MaterialLocalizations.of(context);

    return GlassSurface(
      key: const Key('tab-capsule'),
      floating: true,
      borderRadius: const BorderRadius.all(Radius.circular(AwRadius.pill)),
      child: SizedBox(
        height: kAwTabCapsuleHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final row = Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kAwTabCapsulePadding,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _TabSlot(
                        key: Key('tab-slot-$i'),
                        item: widget.items[i],
                        selected: i == widget.selectedIndex,
                        semanticLabel:
                            '${widget.items[i].label}\n'
                            '${localizations.tabLabel(tabIndex: i + 1, tabCount: count)}',
                        onTap: () => widget.onSelected(i),
                        onLongPress: bigText
                            ? null
                            : widget.items[i].onLongPress,
                      ),
                    ),
                ],
              ),
            );
            if (!bigText) return row;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (d) =>
                  _showBubble(_slotAt(d.localPosition, constraints.maxWidth)),
              onLongPressMoveUpdate: (d) =>
                  _showBubble(_slotAt(d.localPosition, constraints.maxWidth)),
              onLongPressEnd: (d) {
                final index = _slotAt(d.localPosition, constraints.maxWidth);
                _hideBubble();
                widget.onSelected(index);
              },
              onLongPressCancel: _hideBubble,
              child: row,
            );
          },
        ),
      ),
    );
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    super.key,
    required this.item,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
    this.onLongPress,
  });

  final AwTabItem item;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AwMotion.fast;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: kAwTabLabelMaxScale);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : item.longPressHint,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: const BorderRadius.all(
          Radius.circular(kAwTabSelectionHeight / 2),
        ),
        child: SizedBox(
          height: kAwTabCapsuleHeight,
          child: Center(
            child: AnimatedContainer(
              key: selected ? const Key('tab-selection') : null,
              duration: duration,
              curve: AwMotion.enter,
              // The whole slot wide, so every selection is the same shape
              // whatever the label; 12 above and below it in the capsule.
              width: double.infinity,
              height: kAwTabSelectionHeight,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: const BorderRadius.all(
                  Radius.circular(kAwTabSelectionHeight / 2),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The glyph keeps its place: selection swaps outline for
                  // fill and changes colour, nothing else (R-01).
                  KeyedSubtree(
                    key: selected ? item.selectedIconKey : item.iconKey,
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: kAwTabIconSize,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 1),
                  // One line, shrunk to the slot instead of cut or spilled:
                  // "Ana Sayfa" in a 48 pt slot at 360 dp (R-02, U-01).
                  // The label's box is the same height in every slot, so a
                  // label shrunk to fit cannot pull its glyph off the line.
                  SizedBox(
                    height:
                        scaler.scale(kAwTabLabelSize) *
                        kAwTabLabelLineHeight /
                        kAwTabLabelSize,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        key: const Key('tab-label'),
                        maxLines: 1,
                        softWrap: false,
                        textScaler: scaler,
                        style: textTheme.labelSmall!.copyWith(
                          fontSize: kAwTabLabelSize,
                          height: kAwTabLabelLineHeight / kAwTabLabelSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The large content bubble (DESIGN §43 N4): a solid surface, never glass —
/// it carries text (G1).
class _LargeLabel extends StatelessWidget {
  const _LargeLabel({required this.item});

  final AwTabItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('tab-capsule-large-label'),
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      borderRadius: const BorderRadius.all(Radius.circular(AwRadius.xl)),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.selectedIcon, size: 48, color: scheme.onSurface),
            const SizedBox(height: AwSpace.x2),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge!.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
