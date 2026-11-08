import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/quick_link.dart';
import '../providers.dart';
import 'quick_access_menu.dart';
import 'quick_access_navigation.dart';
import 'quick_access_row.dart';
import 'quick_link_sheets.dart';

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
          await showQuickEmojiSheet(context, ref, row);
        case QuickRowAction.color:
          await showQuickColorSheet(context, ref, row);
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

    // OPH-405: Flutter's default desktop handle is a Stack overlay on the
    // row's trailing edge, so it was painted over the ⋯ menu. The rail draws
    // its own handle instead, in a column of its own after the menu; touch
    // platforms keep Flutter's long-press-the-row drag and get no handle.
    final dragsHere = reorderable && surface == QuickAccessSurface.rail;
    final handleColumn = dragsHere && _pointerPlatform(defaultTargetPlatform);

    Widget tile(QuickAccessRow row, int index) => QuickAccessRowTile(
      key: ValueKey('quick-tile-${row.id}'),
      row: row,
      dense: surface != QuickAccessSurface.panel,
      dragHandle: handleColumn
          ? QuickDragHandle(key: Key('quick-drag-${row.id}'), index: index)
          : null,
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
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final ids = [for (final r in rows) r.id];
        final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
        final moved = ids.removeAt(oldIndex);
        ids.insert(target, moved);
        ref
            .read(quickAccessStoreProvider)
            .reorder(rows.first.link.workspaceId, ids);
      },
      children: [
        for (final (index, row) in rows.indexed)
          if (dragsHere && !handleColumn)
            ReorderableDelayedDragStartListener(
              key: ValueKey('quick-tile-${row.id}'),
              index: index,
              child: tile(row, index),
            )
          else
            tile(row, index),
      ],
    );
  }
}

/// Where a pointer can hover, so a handle can wait for it — Flutter's own
/// split between a drag handle and a long-press on the row.
bool _pointerPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  _ => false,
};

/// The rail row's drag handle (OPH-405): a 32×32 target of its own. It is a
/// pointer accelerator only — screen readers and keyboards reorder through
/// the row menu's move up/down (DESIGN §23 Q9) — so it carries no semantics.
class QuickDragHandle extends StatelessWidget {
  const QuickDragHandle({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ReorderableDragStartListener(
        index: index,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox.square(
            dimension: kQuickRowControl,
            child: Icon(
              Icons.drag_indicator,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
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
