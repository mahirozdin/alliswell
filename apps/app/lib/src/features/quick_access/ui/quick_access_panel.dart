import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';
import 'quick_access_add.dart';
import 'quick_access_list.dart';
import 'quick_access_row.dart';

/// The phone's Quick Access panel (OPH-200, BLUEPRINT §12.15).
///
/// Opened on the ROOT navigator: the bubble lives above the whole router and
/// has no `Navigator` ancestor of its own, and opening on the root is also
/// what lets the modal observer hide the bubble while the panel is up.
Future<void> showQuickAccessPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => const QuickAccessPanel(),
  );
}

class QuickAccessPanel extends ConsumerWidget {
  const QuickAccessPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = ref.watch(quickAccessRowsProvider).value ?? const [];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x2,
              AwSpace.x2,
            ),
            child: Row(
              children: [
                Icon(kQuickAccessIcon, color: theme.colorScheme.primary),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'quick.title'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('quick-panel-add'),
                  icon: const Icon(Icons.add),
                  tooltip: 'quick.addLink'.tr(),
                  onPressed: () => showQuickLinkDialog(context, ref),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            // The panel owns the whole sheet, so here the full empty state is
            // right — unlike the rail's one-liner (DESIGN §23 Q6).
            Padding(
              padding: const EdgeInsets.only(bottom: AwSpace.x8),
              child: AwEmptyState(
                icon: kQuickAccessIcon,
                title: 'quick.emptyPanelTitle'.tr(),
                message: 'quick.emptyPanelBody'.tr(),
                action: FilledButton.icon(
                  key: const Key('quick-empty-add'),
                  onPressed: () => showQuickLinkDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text('quick.addLink'.tr()),
                ),
              ),
            )
          else
            Flexible(
              child: QuickAccessList(
                surface: QuickAccessSurface.panel,
                // Tapping a row closes the panel first, so navigation never
                // races a sheet that is still dismissing.
                onNavigate: () => Navigator.of(context).maybePop(),
              ),
            ),
          const SizedBox(height: AwSpace.x4),
        ],
      ),
    );
  }
}
