import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../providers.dart';
import 'quick_access_list.dart';
import 'quick_access_row.dart';

/// Collapsed state of the rail's Quick Access section — device-local, like
/// every other view preference.
final quickRailCollapsedProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('alliswell_quick_rail_collapsed', fallback: false),
);

/// The extended rail's "Quick access" section (≥1160, DESIGN §23 Q1).
///
/// It rides `NavigationRail.trailing`, NOT a destination: `selectedIndex` maps
/// 1:1 onto `AppSection.values`, so an extra entry there would corrupt the
/// branch index. A shortcut navigates; it is not a place (BLUEPRINT §12.15).
class QuickAccessRailSection extends ConsumerWidget {
  const QuickAccessRailSection({super.key, this.onAddLink});

  final VoidCallback? onAddLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = ref.watch(quickAccessRowsProvider).value ?? const [];
    final collapsed = ref.watch(quickRailCollapsedProvider);

    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x4, bottom: AwSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          InkWell(
            key: const Key('quick-rail-header'),
            onTap: () => ref.read(quickRailCollapsedProvider.notifier).toggle(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                AwSpace.x3,
                AwSpace.x2,
                AwSpace.x1,
              ),
              child: Row(
                children: [
                  Icon(
                    kQuickAccessIcon,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AwSpace.x2),
                  Expanded(
                    child: Text(
                      'quick.title'.tr(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onAddLink != null)
                    IconButton(
                      key: const Key('quick-rail-add'),
                      icon: const Icon(Icons.add, size: 20),
                      tooltip: 'quick.addLink'.tr(),
                      onPressed: onAddLink,
                    ),
                  Icon(
                    collapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: collapsed
                        ? 'quick.expand'.tr()
                        : 'quick.collapse'.tr(),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            if (rows.isEmpty)
              const QuickAccessEmptyHint()
            else
              // Bounded height: the section shares the rail with the
              // destinations, and an unbounded list inside a scrollable rail
              // cannot lay out (nor auto-scroll while dragging).
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: const QuickAccessList(surface: QuickAccessSurface.rail),
              ),
        ],
      ),
    );
  }
}

/// A dense row's height, and the popover's ceiling — see the note at the
/// SizedBox below for why these are numbers and not constraints.
const double _kPopoverRowHeight = 56;
const double _kPopoverMaxHeight = 360;

/// The narrow rail's entry point (800–1160): one `bolt` button that opens the
/// same list in an anchored popover.
///
/// `MenuAnchor` does the anchoring itself — no `LayerLink`, no hand-rolled
/// `PopupRoute` — and renders into the overlay, so the rail's `ClipRRect`
/// cannot cut the panel off.
class QuickAccessRailButton extends ConsumerWidget {
  const QuickAccessRailButton({super.key, this.onAddLink});

  final VoidCallback? onAddLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(quickAccessRowsProvider).value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: MenuAnchor(
        consumeOutsideTap: true,
        useRootOverlay: true,
        menuChildren: [
          SizedBox(
            width: 288,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x4,
                    AwSpace.x3,
                    AwSpace.x2,
                    0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'quick.title'.tr(),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (onAddLink != null)
                        IconButton(
                          key: const Key('quick-popover-add'),
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: 'quick.addLink'.tr(),
                          onPressed: onAddLink,
                        ),
                    ],
                  ),
                ),
                if (rows.isEmpty)
                  const QuickAccessEmptyHint()
                else
                  SizedBox(
                    // A FIXED height, not a constraint: `MenuAnchor` measures
                    // its menu's intrinsic height, and a shrink-wrapping
                    // viewport cannot answer that (it would have to build
                    // every child, which is the opposite of a viewport).
                    height: (rows.length * _kPopoverRowHeight).clamp(
                      _kPopoverRowHeight,
                      _kPopoverMaxHeight,
                    ),
                    child: const QuickAccessList(
                      surface: QuickAccessSurface.popover,
                      reorderable: false,
                    ),
                  ),
              ],
            ),
          ),
        ],
        builder: (context, controller, child) => IconButton(
          key: const Key('quick-rail-button'),
          icon: const Icon(kQuickAccessIcon),
          tooltip: 'quick.title'.tr(),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}
