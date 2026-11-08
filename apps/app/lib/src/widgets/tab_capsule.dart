import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import 'sheets.dart';
import '../theme/typography.dart';

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
  /// Access, ADR-0062 §5), and what a screen reader says it does. Slots
  /// only: the large-text menu (N4) has no long press.
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

/// Label text scaling stops here; past it the capsule is one labelled
/// menu button instead of slots (DESIGN §43 N4, ADR-0066).
const double kAwTabLabelMaxScale = 1.3;

/// Whether the reader's text is larger than the slots' labels may be: then
/// the capsule is the labelled menu (DESIGN §43 N4, ADR-0066), and the
/// caller hands it every section — the menu has no "More" step.
bool awTabMenuMode(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler.scale(kAwTabLabelSize) / kAwTabLabelSize > kAwTabLabelMaxScale;
}

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
///  * label scaling is clamped at 1.3; above that ([awTabMenuMode]) the
///    capsule is one button naming the open section, and it opens a sheet
///    with every section in full at the reader's size, in rows that grow
///    with the text (OPH-396 J-02, ADR-0066) — the clamped labels were
///    unreadable at AX sizes and a long-press bubble was not a way in;
///  * each slot is one semantics node: button, selected, "Home\nTab 1 of 5".
class AwTabCapsule extends StatefulWidget {
  const AwTabCapsule({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.menuKey,
  });

  /// The sections: at most five slots, or — in [awTabMenuMode] — every one.
  final List<AwTabItem> items;

  /// -1 draws no selection.
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Anchors the onboarding tour on the large-text menu button.
  final Key? menuKey;

  @override
  State<AwTabCapsule> createState() => _AwTabCapsuleState();
}

class _AwTabCapsuleState extends State<AwTabCapsule> {
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    final picked = await showAwSheet<int>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => _TabMenuSheet(
        items: widget.items,
        selectedIndex: widget.selectedIndex,
      ),
    );
    _menuOpen = false;
    if (picked != null && mounted) widget.onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    final localizations = MaterialLocalizations.of(context);
    final menu = awTabMenuMode(context);

    return GlassSurface(
      key: const Key('tab-capsule'),
      floating: true,
      borderRadius: const BorderRadius.all(Radius.circular(AwRadius.pill)),
      child: SizedBox(
        height: kAwTabCapsuleHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kAwTabCapsulePadding),
          child: menu
              ? _TabMenuButton(
                  key: widget.menuKey,
                  item:
                      widget.selectedIndex >= 0 && widget.selectedIndex < count
                      ? widget.items[widget.selectedIndex]
                      : null,
                  onTap: _openMenu,
                )
              : Row(
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
                          onLongPress: widget.items[i].onLongPress,
                        ),
                      ),
                  ],
                ),
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
                          // ADR-0063: the font's own tracking for 11 pt.
                          letterSpacing: context.awText.tracking(
                            kAwTabLabelSize,
                          ),
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

/// The capsule above 1.3× text (DESIGN §43 N4, ADR-0066): one button the
/// capsule wide — the open section's glyph and whole name, and an unfold
/// glyph that says a menu opens. The name is at the reader's size, shrunk
/// only if the 64 pt capsule cannot hold it, never cut.
class _TabMenuButton extends StatelessWidget {
  const _TabMenuButton({super.key, required this.item, required this.onTap});

  /// The open section; null when none of the items is open.
  final AwTabItem? item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = item?.label ?? 'nav.menuTitle'.tr();
    return Semantics(
      container: true,
      button: true,
      label: 'nav.menuLabel'.tr(args: {'name': name}),
      onTapHint: 'nav.menuHint'.tr(),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: const Key('tab-menu-button'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(
          Radius.circular(kAwTabSelectionHeight / 2),
        ),
        child: SizedBox(
          height: kAwTabCapsuleHeight,
          child: Center(
            child: Container(
              height: kAwTabSelectionHeight + AwSpace.x2,
              padding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: const BorderRadius.all(
                  Radius.circular((kAwTabSelectionHeight + AwSpace.x2) / 2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item?.selectedIcon ?? Icons.menu,
                    size: 24,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: AwSpace.x3),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        name,
                        key: const Key('tab-menu-label'),
                        maxLines: 1,
                        softWrap: false,
                        style: textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AwSpace.x2),
                  Icon(
                    Icons.unfold_more,
                    size: 24,
                    color: scheme.onPrimaryContainer,
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

/// The large-text menu's sheet: every section, its glyph and its whole name
/// at the reader's size, wrapping rather than cut; rows grow with the text
/// from 56 pt; the open one is selected and carries a check. A solid sheet,
/// never glass — it carries text (G1).
class _TabMenuSheet extends StatelessWidget {
  const _TabMenuSheet({required this.items, required this.selectedIndex});

  final List<AwTabItem> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localizations = MaterialLocalizations.of(context);
    return SafeArea(
      child: Column(
        key: const Key('tab-menu-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x5,
              0,
              AwSpace.x5,
              AwSpace.x2,
            ),
            child: Semantics(
              header: true,
              child: Text('nav.menuTitle'.tr(), style: textTheme.titleMedium),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // OPH-407 (T-07): one node per row. The outer Semantics
                  // and the ListTile's own button used to be two nodes — a
                  // button with no name ("Tab 2 of 5") around the named one.
                  for (var i = 0; i < items.length; i++)
                    MergeSemantics(
                      key: Key('tab-menu-row-$i'),
                      child: Semantics(
                        button: true,
                        selected: i == selectedIndex,
                        hint: localizations.tabLabel(
                          tabIndex: i + 1,
                          tabCount: items.length,
                        ),
                        child: ListTile(
                          minTileHeight: 56,
                          selected: i == selectedIndex,
                          leading: Icon(
                            i == selectedIndex
                                ? items[i].selectedIcon
                                : items[i].icon,
                            size: 24,
                          ),
                          title: Text(
                            items[i].label,
                            key: const Key('tab-menu-row-title'),
                            style: textTheme.titleMedium!.copyWith(
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w600
                                  : null,
                              color: scheme.onSurface,
                            ),
                          ),
                          trailing: i == selectedIndex
                              ? Icon(
                                  Icons.check,
                                  key: const Key('tab-menu-current'),
                                  size: 24,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AwSpace.x2),
        ],
      ),
    );
  }
}
