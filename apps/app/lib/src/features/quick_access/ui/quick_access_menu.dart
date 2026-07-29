import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../data/quick_link.dart';
import '../providers.dart';

/// What a row's overflow menu can do. `moveUp`/`moveDown` are not garnish:
/// dragging is the one interaction a screen-reader user cannot aim, so every
/// surface offers the same reordering through the menu (DESIGN §23 Q9).
enum QuickRowAction {
  rename,
  emoji,
  color,
  useTargetName,
  moveUp,
  moveDown,
  remove,
}

/// The row's "⋯" menu, identical on every surface.
///
/// A visible control rather than a long-press: a mouse never long-presses, and
/// hiding actions behind a gesture is exactly what DESIGN §19 D2 forbids. It
/// therefore also appears on keyboard focus, not only on hover.
class QuickRowMenu extends ConsumerWidget {
  const QuickRowMenu({
    super.key,
    required this.row,
    required this.onAction,
    this.canMoveUp = true,
    this.canMoveDown = true,
  });

  final QuickAccessRow row;
  final void Function(QuickRowAction action) onAction;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<QuickRowAction>(
      key: Key('quick-menu-${row.id}'),
      tooltip: 'quick.actions'.tr(),
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: onAction,
      itemBuilder: (context) => [
        _item(
          QuickRowAction.rename,
          Icons.drive_file_rename_outline,
          'quick.rename',
        ),
        _item(
          QuickRowAction.emoji,
          Icons.emoji_emotions_outlined,
          'quick.emoji',
        ),
        _item(QuickRowAction.color, Icons.palette_outlined, 'quick.color'),
        if (row.targetRenamed)
          _item(
            QuickRowAction.useTargetName,
            Icons.sync_alt,
            'quick.useTargetName',
          ),
        if (canMoveUp)
          _item(QuickRowAction.moveUp, Icons.arrow_upward, 'quick.moveUp'),
        if (canMoveDown)
          _item(
            QuickRowAction.moveDown,
            Icons.arrow_downward,
            'quick.moveDown',
          ),
        _item(QuickRowAction.remove, Icons.bolt, 'quick.remove'),
      ],
    );
  }

  PopupMenuItem<QuickRowAction> _item(
    QuickRowAction value,
    IconData icon,
    String key,
  ) => PopupMenuItem<QuickRowAction>(
    value: value,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(key.tr()),
    ),
  );
}

/// Renames a shortcut. Clearing the field returns the row to its target's
/// current name (BLUEPRINT §4.12 — the title is suggested, not owned, by the
/// target); a `url` row falls back to its host.
Future<void> showQuickRenameDialog(
  BuildContext context,
  WidgetRef ref,
  QuickAccessRow row,
) async {
  final name = await showDialog<String>(
    context: context,
    // Round 13 #2: dialogs go to the ROOT navigator for the same
    // reason sheets do (OPH-212) — inside a shell branch the
    // Scaffold's own bar and FAB paint over them.
    useRootNavigator: true,
    // The dialog owns its controller: disposing it here would run while the
    // route is still animating out and the field is still rebuilding.
    builder: (dialogContext) => _RenameDialog(initial: row.displayTitle),
  );
  if (name == null) return;
  final trimmed = name.trim();
  await ref
      .read(quickAccessStoreProvider)
      .rename(row.id, trimmed.isEmpty ? fallbackTitleFor(row) : trimmed);
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('quick.rename'.tr()),
      content: TextField(
        key: const Key('quick-rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        decoration: InputDecoration(labelText: 'quick.linkTitle'.tr()),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}

/// What an empty title falls back to: the target's live name, or a url's host.
String fallbackTitleFor(QuickAccessRow row) {
  if (row.targetTitle case final title? when title.trim().isNotEmpty) {
    return title.trim();
  }
  if (row.link.kind == QuickKind.url) {
    final host = Uri.tryParse(row.link.url ?? '')?.host ?? '';
    if (host.isNotEmpty) return host;
  }
  return row.link.title;
}
