import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../shared_items_providers.dart';

/// "Shared with me" (EE-061) — the receiving end of EE-059's bridge.
///
/// Every row here is a REFERENCE to something that lives in another unit. Two
/// things the layout has to make honest, because both are true and neither is
/// obvious:
///
///   • THE ITEM IS NOT YOURS. It is rendered as a reference, with the label the
///     mirror cached — not dressed up as a task in your own list, where it
///     would look like something you could reorder, complete or delete.
///   • WHAT YOU MAY DO IS A CEILING. `view` and `edit` are shown, because a
///     person about to type needs to know which one they have before they
///     type — and because `edit` still needs their ordinary permission, so the
///     badge promises access, never capability.
class EeSharedWithMeScreen extends ConsumerWidget {
  const EeSharedWithMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(sharedWithMeProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.shared.title'.tr())),
      body: shared.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (items) => items.isEmpty
            ? AwEmptyState(
                icon: Icons.move_to_inbox_outlined,
                title: 'ee.shared.emptyTitle'.tr(),
                message: 'ee.shared.emptyBody'.tr(),
              )
            : ListView(
                padding: const EdgeInsets.all(AwSpace.x4),
                children: [
                  Text(
                    'ee.shared.intro'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AwSpace.x3),
                  for (final item in items) _SharedRow(item: item),
                ],
              ),
      ),
    );
  }
}

class _SharedRow extends StatelessWidget {
  const _SharedRow({required this.item});

  final SharedItem item;

  static const _icons = {
    'task': Icons.check_circle_outline,
    'note': Icons.description_outlined,
    'project': Icons.folder_outlined,
    'file': Icons.attach_file,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('shared-${item.id}'),
      child: ListTile(
        leading: Icon(_icons[item.entityType] ?? Icons.link),
        // `?? ` is not enough: a source with an empty title yields '', which
        // renders a row with no label rather than a row that says it has none.
        title: Text(
          (item.title ?? '').trim().isEmpty
              ? 'ee.shared.untitled'.tr()
              : item.title!,
        ),
        subtitle: Text(
          [
            'ee.shared.kind.${item.entityType}'.tr(),
            item.rights == 'edit'
                ? 'ee.shared.canEdit'.tr()
                : 'ee.shared.readOnly'.tr(),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        // No chevron: opening a reference into another unit's workspace is
        // EE-063's surface. A row that looks tappable and is not would be a
        // worse promise than a row that plainly is not (DESIGN §22).
      ),
    );
  }
}
