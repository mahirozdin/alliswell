import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../widgets/color_picker.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../projects/ui/project_edit_sheet.dart' show kProjectPalette;
import '../tags.dart';

/// "Manage tags" (round 8, OPH-165 — DESIGN T3): rename, recolor (palette
/// only — hex never shown), delete with the blast radius named in the
/// confirm. Reached from the tag input's manage affordance.
Future<void> showTagManageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _TagManageSheet(),
  );
}

class _TagManageSheet extends ConsumerWidget {
  const _TagManageSheet();

  Future<void> _edit(BuildContext context, WidgetRef ref, Tag tag) async {
    await showDialog<void>(
      context: context,
      // Round 13 #2: dialogs go to the ROOT navigator for the same
      // reason sheets do (OPH-212) — inside a shell branch the
      // Scaffold's own bar and FAB paint over them.
      useRootNavigator: true,
      builder: (_) => _TagEditDialog(tag: tag),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Tag tag) async {
    final store = ref.read(tagStoreProvider);
    final count = await store.taskCount(tag.id);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      // Round 13 #2: dialogs go to the ROOT navigator for the same
      // reason sheets do (OPH-212) — inside a shell branch the
      // Scaffold's own bar and FAB paint over them.
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('tag.deleteTitle'.tr(args: {'name': tag.name})),
        content: Text(
          count == 0
              ? 'tag.deleteBodyUnused'.tr()
              : 'tag.deleteBody'.tr(args: {'count': '$count'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('tag-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.delete(tag.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, 0, AwSpace.x4, AwSpace.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'tag.manageTitle'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (tags.isEmpty)
            AwEmptyState(
              icon: Icons.tag,
              title: 'tag.emptyTitle'.tr(),
              message: 'tag.emptyBody'.tr(),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final tag in tags)
                    ListTile(
                      key: Key('tag-row-${tag.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: tag.color,
                        radius: 7,
                      ),
                      title: Text('#${tag.name}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('tag-edit-${tag.id}'),
                            tooltip: 'tag.edit'.tr(),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _edit(context, ref, tag),
                          ),
                          IconButton(
                            key: Key('tag-delete-${tag.id}'),
                            tooltip: 'common.delete'.tr(),
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _delete(context, ref, tag),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Rename + palette recolor. The palette is the project palette — one color
/// language across the product, hex never typed (feedback round 1).
class _TagEditDialog extends ConsumerStatefulWidget {
  const _TagEditDialog({required this.tag});

  final Tag tag;

  @override
  ConsumerState<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends ConsumerState<_TagEditDialog> {
  late final TextEditingController _name;
  late String _colorHex;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.tag.name);
    _colorHex = widget.tag.colorRgb.toUpperCase();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(tagStoreProvider);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    if (name.isNotEmpty && name != widget.tag.name) {
      await store.rename(widget.tag.id, name);
    }
    if (_colorHex != widget.tag.colorRgb.toUpperCase()) {
      await store.setColor(widget.tag.id, _colorHex);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('tag.editTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('tag-edit-name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: 'tag.nameLabel'.tr()),
          ),
          const SizedBox(height: 16),
          // OPH-259: this one had grown its OWN swatch — 28 px circles with a
          // white check that vanished on light colours, and no memory of what
          // was picked last. Same component as everywhere else now (§33 R1).
          AwColorPicker(
            keyPrefix: 'tag-color',
            palette: kProjectPalette,
            selected: _colorHex,
            onPicked: (hex) => setState(() => _colorHex = hex),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('tag-edit-save'),
          onPressed: _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
