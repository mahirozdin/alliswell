/// Getting back to a file the OS handed us once (DESIGN §29.5 W6, OPH-251).
///
/// W6 is not a nicety: without it, a file we were given access to is
/// unreachable forever unless the user goes hunting in a picker again. It is
/// §22 in its plainest form — the app HOLDS a durable handle, and if nothing
/// surfaces it, that handle is not a feature.
///
/// The Notes tab's single "open a file" button becomes a menu rather than
/// growing a second icon: the app bar is already at the phone's limit, which
/// is the same reason OPH-201 moved actions into an overflow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheets.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../data/external_document.dart';
import '../data/external_session.dart';
import 'markdown_import_screen.dart';

class ExternalOpenMenu extends ConsumerWidget {
  const ExternalOpenMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      key: const Key('notes-open-markdown'),
      // OPH-272: reported blank on the owner's device — the tooltip appeared
      // but no glyph did, so the control did not read as a button. It could
      // not be reproduced here (the widget and the icon are both present in a
      // widget test), and the codepoint theory does not hold either: the
      // settings icon next to it is in the same 0xf… variant block and draws
      // fine. Rather than ship a guess, this drops the dependence on that one
      // glyph — `folder_open` is the classic-codepoint sibling and says the
      // same thing.
      icon: const Icon(Icons.folder_open),
      tooltip: 'note.mdOpen'.tr(),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await _openForEditing(context, ref);
          case 'import':
            await openMarkdownFile(context, ref);
          case 'recent':
            await showExternalRecents(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_document),
            title: Text('note.extEditFile'.tr()),
          ),
        ),
        // Importing is a DIFFERENT thing and stays: it makes a note that lives
        // here, with no tie to the file.
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text('note.extImportNote'.tr()),
          ),
        ),
        PopupMenuItem(
          value: 'recent',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text('note.extRecents'.tr()),
          ),
        ),
      ],
    );
  }
}

Future<void> _openForEditing(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final refusal = await ref.read(externalSessionProvider.notifier).pick();
  if (refusal == null) {
    router.push('/notes/file');
    return;
  }
  // Backing out is not a failure and gets no message; everything else gets a
  // reason, because "nothing happened" is the report people cannot act on.
  final message = describeRefusal(refusal);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

String? describeRefusal(ExternalOpenRefusal refusal) => switch (refusal) {
  ExternalOpenRefusal.cancelled => null,
  ExternalOpenRefusal.tooLarge => 'note.extTooLarge'.tr(),
  ExternalOpenRefusal.denied => 'note.extDenied'.tr(),
  ExternalOpenRefusal.unsupported => 'note.extUnsupported'.tr(),
  ExternalOpenRefusal.gone => 'note.extGone'.tr(),
};

/// The list itself, plus the one thing the owner asked for that neither
/// existing mechanism could do: bind a file to a project WITHOUT importing it.
Future<void> showExternalRecents(BuildContext context, WidgetRef ref) =>
    showAwSheet<void>(
      context,
      builder: (sheetContext) => const _ExternalRecentsSheet(),
    );

class _ExternalRecentsSheet extends ConsumerWidget {
  const _ExternalRecentsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(externalRecentsProvider);
    final projects = ref.watch(projectsControllerProvider).value ?? const [];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AwSpace.x5),
            child: Text(
              'note.extRecents'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (recents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x5,
                0,
                AwSpace.x5,
                AwSpace.x5,
              ),
              child: Text(
                'note.extRecentsEmpty'.tr(),
                key: const Key('external-recents-empty'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView(
                key: const Key('external-recents-list'),
                shrinkWrap: true,
                children: [
                  for (final handle in recents)
                    ListTile(
                      key: Key('external-recent-${handle.token}'),
                      leading: const Icon(Icons.description_outlined),
                      title: Text(handle.displayName),
                      subtitle: Text(
                        projects
                                .where((p) => p.id == handle.projectId)
                                .firstOrNull
                                ?.name ??
                            'note.extNoProject'.tr(),
                      ),
                      trailing: IconButton(
                        key: Key('external-recent-project-${handle.token}'),
                        tooltip: 'note.extLinkProject'.tr(),
                        icon: const Icon(Icons.folder_outlined),
                        onPressed: () => _linkProject(context, ref, handle),
                      ),
                      onTap: () => _reopen(context, ref, handle),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reopen(
    BuildContext context,
    WidgetRef ref,
    ExternalDocHandle handle,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final refusal = await ref
        .read(externalSessionProvider.notifier)
        .openHandle(handle);
    navigator.pop();
    if (refusal == null) {
      router.push('/notes/file');
      return;
    }
    // A row that cannot open is worse than no row: drop it and say so.
    if (refusal == ExternalOpenRefusal.gone) {
      await ref.read(externalRecentsProvider.notifier).forget(handle.token);
    }
    final message = describeRefusal(refusal);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _linkProject(
    BuildContext context,
    WidgetRef ref,
    ExternalDocHandle handle,
  ) async {
    final chosen = await showAwSheet<String?>(
      context,
      builder: (pickerContext) => Padding(
        padding: EdgeInsets.only(
          left: AwSpace.x5,
          right: AwSpace.x5,
          top: AwSpace.x5,
          bottom: MediaQuery.viewInsetsOf(pickerContext).bottom + AwSpace.x5,
        ),
        child: Consumer(
          builder: (consumerContext, pickerRef, _) => ProjectPickerField(
            key: const Key('external-project-picker'),
            projects:
                pickerRef.watch(projectsControllerProvider).value ?? const [],
            value: handle.projectId,
            onChanged: (id) => Navigator.of(pickerContext).pop(id),
          ),
        ),
      ),
    );
    await ref
        .read(externalRecentsProvider.notifier)
        .linkProject(handle.token, chosen);
  }
}
