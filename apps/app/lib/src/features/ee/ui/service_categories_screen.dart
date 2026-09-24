import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/services_models.dart';
import '../services_providers.dart';
import 'service_icons.dart';

/// EE-228 — the catalogue's shelves, as the admin arranges them.
///
/// ── TWO LEVELS, AND THE SCREEN DOES NOT OFFER A THIRD ────────────────
///
/// The server refuses a third level from both directions (EE-212): a shelf
/// cannot go under a sub-shelf, and a shelf that HAS sub-shelves cannot go
/// under anything. The editor offers exactly what that rule accepts — only
/// top shelves as parents, never itself, and no parent at all for a shelf
/// with children, which says why — so the refusal is a guard the admin never
/// meets rather than an error they have to decode.
///
/// Deleting a shelf loses nothing: its services and sub-shelves fall back to
/// the catalogue's root (`ON DELETE SET NULL`), and the confirmation says so
/// before anybody has to wonder.
class EeServiceCategoriesScreen extends ConsumerWidget {
  const EeServiceCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = ref.watch(eeServiceCategoriesProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('ee.team.services.shelves.title'.tr())),
      floatingActionButton: FloatingActionButton(
        key: const Key('shelf-new'),
        tooltip: 'ee.team.services.shelves.create'.tr(),
        onPressed: () => editShelf(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: shelves.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeServiceCategoriesProvider),
        ),
        data: (list) {
          if (list == null) {
            return AwEmptyState(
              icon: Icons.lock_outline,
              title: 'ee.team.services.noneTitle'.tr(),
              message: 'ee.team.services.noneBody'.tr(),
            );
          }
          final tree = shelfTree(list);
          return ListView(
            padding: awListPadding(context, top: AwSpace.x4, extraBottom: 72),
            children: [
              Text(
                'ee.team.services.shelves.intro'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AwSpace.x3),
              if (tree.isEmpty)
                AwEmptyState(
                  key: const Key('shelves-empty'),
                  icon: Icons.account_tree_outlined,
                  title: 'ee.team.services.shelves.empty'.tr(),
                  message: 'ee.team.services.shelves.emptyBody'.tr(),
                ),
              for (final (root, subs) in tree) ...[
                _ShelfRow(shelf: root, all: list, hasChildren: subs.isNotEmpty),
                for (final sub in subs)
                  _ShelfRow(shelf: sub, all: list, hasChildren: false),
              ],
            ],
          );
        },
      ),
    );
  }

  /// A new shelf (null), a new sub-shelf ([parentId]), or an edit.
  static Future<void> editShelf(
    BuildContext context,
    WidgetRef ref,
    EeServiceCategory? existing, {
    String? parentId,
  }) async {
    final all = ref.read(eeServiceCategoriesProvider).value ?? const [];
    final result = await showDialog<_ShelfEdit>(
      context: context,
      builder: (_) => _ShelfDialog(
        existing: existing,
        parentId: existing?.parentId ?? parentId,
        all: all,
      ),
    );
    if (result == null) return;
    final notifier = ref.read(eeServiceCategoriesProvider.notifier);
    if (existing == null) {
      await notifier.create(
        name: result.name,
        parentId: result.parentId,
        icon: result.icon,
      );
      return;
    }
    // Only what changed: an untouched parent is not re-sent, so a rename can
    // never trip the depth rule by accident.
    final patch = <String, Object?>{
      if (result.name != existing.name) 'name': result.name,
      if (result.parentId != existing.parentId) 'parentId': result.parentId,
      if (result.icon != existing.icon) 'icon': result.icon,
    };
    if (patch.isNotEmpty) await notifier.edit(existing.id, patch);
  }
}

/// Top shelves in the server's order (position, then name), each with its
/// sub-shelves. A sub-shelf whose parent is missing is shown at the top
/// rather than hidden — a row the admin cannot see is a row they cannot fix.
List<(EeServiceCategory, List<EeServiceCategory>)> shelfTree(
  List<EeServiceCategory> all,
) {
  int order(EeServiceCategory a, EeServiceCategory b) {
    final byPosition = a.position.compareTo(b.position);
    return byPosition != 0 ? byPosition : a.name.compareTo(b.name);
  }

  final ids = {for (final shelf in all) shelf.id};
  final roots = [
    for (final shelf in all)
      if (shelf.isRoot || !ids.contains(shelf.parentId)) shelf,
  ]..sort(order);
  return [
    for (final root in roots)
      (
        root,
        [
          for (final shelf in all)
            if (shelf.parentId == root.id) shelf,
        ]..sort(order),
      ),
  ];
}

class _ShelfRow extends ConsumerWidget {
  const _ShelfRow({
    required this.shelf,
    required this.all,
    required this.hasChildren,
  });

  final EeServiceCategory shelf;
  final List<EeServiceCategory> all;
  final bool hasChildren;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = !shelf.isRoot;
    return Card(
      key: Key('shelf-row-${shelf.id}'),
      margin: EdgeInsetsDirectional.only(
        start: sub ? AwSpace.x6 : 0,
        bottom: AwSpace.x2,
      ),
      child: ListTile(
        leading: Icon(serviceIconData(shelf.icon)),
        title: Text(shelf.name),
        trailing: PopupMenuButton<String>(
          key: Key('shelf-menu-${shelf.id}'),
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                await EeServiceCategoriesScreen.editShelf(context, ref, shelf);
              case 'sub':
                await EeServiceCategoriesScreen.editShelf(
                  context,
                  ref,
                  null,
                  parentId: shelf.id,
                );
              case 'delete':
                await _confirmDelete(context, ref);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              key: Key('shelf-edit-${shelf.id}'),
              value: 'edit',
              child: Text('ee.team.services.shelves.edit'.tr()),
            ),
            // A sub-shelf takes no children: there is no third level.
            if (!sub)
              PopupMenuItem(
                key: Key('shelf-add-sub-${shelf.id}'),
                value: 'sub',
                child: Text('ee.team.services.shelves.addSub'.tr()),
              ),
            PopupMenuItem(
              key: Key('shelf-delete-${shelf.id}'),
              value: 'delete',
              child: Text('ee.team.services.shelves.delete'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ee.team.services.shelves.deleteTitle'.tr()),
        content: Text('ee.team.services.shelves.deleteBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('shelf-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (yes == true) {
      await ref.read(eeServiceCategoriesProvider.notifier).remove(shelf.id);
    }
  }
}

typedef _ShelfEdit = ({String name, String? parentId, String? icon});

class _ShelfDialog extends StatefulWidget {
  const _ShelfDialog({
    required this.existing,
    required this.parentId,
    required this.all,
  });

  final EeServiceCategory? existing;
  final String? parentId;
  final List<EeServiceCategory> all;

  @override
  State<_ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<_ShelfDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String? _parent = widget.parentId;
  late String? _icon = widget.existing?.icon;

  /// A shelf with sub-shelves cannot itself go under another (EE-212).
  bool get _locked =>
      widget.existing != null &&
      widget.all.any((shelf) => shelf.parentId == widget.existing!.id);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only top shelves can be parents, and never the shelf itself.
    final parents = [
      for (final shelf in widget.all)
        if (shelf.isRoot && shelf.id != widget.existing?.id) shelf,
    ];
    return AlertDialog(
      title: Text(
        (widget.existing == null
                ? (widget.parentId == null
                      ? 'ee.team.services.shelves.create'
                      : 'ee.team.services.shelves.addSub')
                : 'ee.team.services.shelves.edit')
            .tr(),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('shelf-name'),
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: 'ee.team.services.shelves.name'.tr(),
              ),
            ),
            DropdownButtonFormField<String?>(
              key: const Key('shelf-parent'),
              initialValue: _parent,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'ee.team.services.shelves.parent'.tr(),
                helperText: _locked
                    ? 'ee.team.services.shelves.parentLocked'.tr()
                    : null,
                helperMaxLines: 3,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('ee.team.services.shelves.parentNone'.tr()),
                ),
                for (final shelf in parents)
                  DropdownMenuItem<String?>(
                    key: Key('shelf-parent-${shelf.id}'),
                    value: shelf.id,
                    child: Text(shelf.name),
                  ),
              ],
              onChanged: _locked ? null : (id) => setState(() => _parent = id),
            ),
            const SizedBox(height: AwSpace.x3),
            Text(
              'ee.team.services.icon'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AwSpace.x1),
            EeIconPicker(
              value: _icon,
              keyPrefix: 'shelf-icon',
              onChanged: (token) => setState(() => _icon = token),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('shelf-save'),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(
              context,
            ).pop((name: name, parentId: _parent, icon: _icon));
          },
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
