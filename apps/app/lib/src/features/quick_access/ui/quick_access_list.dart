import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/quick_link.dart';
import '../providers.dart';
import 'quick_access_menu.dart';
import 'quick_access_navigation.dart';
import 'quick_access_row.dart';

/// Which chrome the shared list is wearing (DESIGN §23 Q1: one store, one
/// order, three surfaces — they may differ in chrome, never in content).
enum QuickAccessSurface { rail, popover, panel }

/// The rail's body: the same rows, the same order, everywhere.
class QuickAccessList extends ConsumerWidget {
  const QuickAccessList({
    super.key,
    required this.surface,
    this.reorderable = true,
    this.onNavigate,
  });

  final QuickAccessSurface surface;

  /// Pointer drag-to-reorder. The menu's move up/down always works regardless
  /// (DESIGN §23 Q9) — dragging is an accelerator, never the only path.
  final bool reorderable;

  /// Called just before navigating, so a sheet can close itself first.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(quickAccessRowsProvider).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    Future<void> handle(QuickAccessRow row, QuickRowAction action) async {
      final store = ref.read(quickAccessStoreProvider);
      final ids = [for (final r in rows) r.id];
      final index = ids.indexOf(row.id);
      switch (action) {
        case QuickRowAction.rename:
          await showQuickRenameDialog(context, ref, row);
        case QuickRowAction.emoji:
        case QuickRowAction.color:
          // The pickers arrive with OPH-202; until then the menu still shows
          // the entries so the surface is complete in one place.
          break;
        case QuickRowAction.useTargetName:
          await store.rename(row.id, fallbackTitleFor(row));
        case QuickRowAction.moveUp:
          if (index > 0) {
            await store.reorder(row.link.workspaceId, [
              ...ids.sublist(0, index - 1),
              ids[index],
              ids[index - 1],
              ...ids.sublist(index + 1),
            ]);
          }
        case QuickRowAction.moveDown:
          if (index >= 0 && index < ids.length - 1) {
            await store.reorder(row.link.workspaceId, [
              ...ids.sublist(0, index),
              ids[index + 1],
              ids[index],
              ...ids.sublist(index + 2),
            ]);
          }
        case QuickRowAction.remove:
          await store.remove(row.id);
      }
    }

    Widget tile(QuickAccessRow row, int index) => QuickAccessRowTile(
      key: ValueKey('quick-tile-${row.id}'),
      row: row,
      dense: surface != QuickAccessSurface.panel,
      trailing: QuickRowMenu(
        row: row,
        canMoveUp: index > 0,
        canMoveDown: index < rows.length - 1,
        onAction: (action) => handle(row, action),
      ),
      onTap: () {
        onNavigate?.call();
        openQuickDestination(context, ref, row);
      },
    );

    if (!reorderable) {
      return ListView(
        shrinkWrap: true,
        // Never the primary controller: this list is always nested inside
        // another scrollable (the rail, the popover panel, the sheet), and two
        // positions on one controller trips the scrollbar assertion.
        primary: false,
        padding: EdgeInsets.zero,
        children: [for (final (index, row) in rows.indexed) tile(row, index)],
      );
    }

    return ReorderableListView(
      shrinkWrap: true,
      primary: false,
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: surface == QuickAccessSurface.rail,
      onReorderItem: (oldIndex, newIndex) {
        final ids = [for (final r in rows) r.id];
        final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
        final moved = ids.removeAt(oldIndex);
        ids.insert(target, moved);
        ref
            .read(quickAccessStoreProvider)
            .reorder(rows.first.link.workspaceId, ids);
      },
      children: [for (final (index, row) in rows.indexed) tile(row, index)],
    );
  }
}

/// The rail section's one-line empty state (DESIGN §23 Q6): a hint, not an
/// `AwEmptyState` card — the rail has no room for a monument.
class QuickAccessEmptyHint extends StatelessWidget {
  const QuickAccessEmptyHint({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x1,
        AwSpace.x4,
        AwSpace.x3,
      ),
      child: Text(
        'quick.empty'.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
