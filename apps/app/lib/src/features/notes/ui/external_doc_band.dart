/// Somebody else's file, inside our own editor (DESIGN §29.5, OPH-251).
///
/// The document opens in the SAME editor a note does — same modes, same
/// toolbar, same everything — because it is the same job. What changes is that
/// it is permanently marked as external (W1) and that it only changes when the
/// user says so (W2).
///
/// W3 is carried by the type system rather than by this file: the save action
/// is built from the `ExternalWritable` arm of a sealed `ExternalAccess`, so
/// on a read-only file there is no saver to bind a button to and the button
/// cannot exist. A disabled one would be the dead affordance §22 forbids.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheets.dart';
import '../data/external_document.dart';
import '../data/external_session.dart';

/// W1: the real file name, in every mode, for the whole session.
///
/// "The moment editing is possible, 'which file am I changing' stops being a
/// nicety." So the band is not a toast and not an app-bar subtitle — it is a
/// row that stays.
class ExternalDocBand extends ConsumerWidget {
  const ExternalDocBand({super.key, required this.dirty});

  /// Whether the editor holds unsaved edits. Shown here rather than through
  /// the autosave indicator: that one describes AllisWell's own notes, and
  /// conflating the two would be the exact confusion W2 is about.
  final bool dirty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(externalSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    final reason = describeAccess(session.access, session.document.encoding);

    return Container(
      key: const Key('external-doc-band'),
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x4,
        vertical: AwSpace.x2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.document.name,
                  key: const Key('external-doc-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  dirty && reason == null
                      ? 'note.extUnsaved'.tr()
                      : (reason ?? 'note.extExternal'.tr()),
                  key: const Key('external-doc-state'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// Why this document cannot be written, in the user's words — or null when it
/// can be.
///
/// Every arm names its own cause. "Read-only" and "we have lost our grip on
/// this file" call for different actions, and a single generic refusal would
/// hide which one happened.
String? describeAccess(ExternalAccess access, ExternalEncoding encoding) =>
    switch (access) {
      ExternalWritable() => null,
      ExternalReadOnly(:final reason) => switch (reason) {
        ReadOnlyReason.notUtf8 => 'note.extNotUtf8'.tr(),
        ReadOnlyReason.notMarkdownCanonical => 'note.extNotMarkdown'.tr(),
        ReadOnlyReason.providerNoWrite ||
        ReadOnlyReason.volumeReadOnly ||
        ReadOnlyReason.permissionReadOnly => 'note.extReadOnly'.tr(),
      },
      ExternalUnreachable(:final reason) => switch (reason) {
        LostAccessReason.unsupportedPlatform => 'note.extUnsupported'.tr(),
        LostAccessReason.fileGone => 'note.extGone'.tr(),
        LostAccessReason.grantRevoked ||
        LostAccessReason.scopeExpired => 'note.extLostAccess'.tr(),
      },
    };

/// The saver, if and only if writing is allowed (W3 + W4).
///
/// Two gates, both required: the OS has to permit the write, and the bytes
/// have to survive the round trip. A file can be perfectly writable and still
/// refuse to be written.
ExternalSaver? saverFor(ExternalSession session) => switch (session.access) {
  ExternalWritable(:final saver) =>
    canWriteBack(markdownCanonical: true, encoding: session.document.encoding)
        ? saver
        : null,
  ExternalReadOnly() => null,
  ExternalUnreachable() => null,
};

/// W2: the deliberate write. Never called by autosave.
///
/// Re-probes first, because the answer can have changed since the screen was
/// built — a scope expires, a grant is revoked — and offering a save that then
/// fails is the failure mode W3 exists to prevent, one step later.
Future<bool> saveExternal(
  BuildContext context,
  WidgetRef ref,
  String markdown,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(externalSessionProvider.notifier).reprobe();
  final session = ref.read(externalSessionProvider);
  if (session == null) return false;
  final saver = saverFor(session);
  if (saver == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          describeAccess(session.access, session.document.encoding) ??
              'note.extSaveFailed'.tr(),
        ),
      ),
    );
    return false;
  }

  final outcome = await saver.save(
    markdown,
    expected: session.document.stamp,
    encoding: session.document.encoding,
    intent: SaveIntent.ifUnchanged,
  );

  switch (outcome) {
    case SaveSucceeded(:final stamp):
      ref.read(externalSessionProvider.notifier).adoptStamp(stamp, markdown);
      messenger.showSnackBar(SnackBar(content: Text('note.extSaved'.tr())));
      return true;
    case SaveConflict():
      if (!context.mounted) return false;
      return _resolveConflict(context, ref, markdown, saver, session);
    case SaveLostAccess():
      await ref.read(externalSessionProvider.notifier).reprobe();
      messenger.showSnackBar(
        SnackBar(content: Text('note.extLostAccess'.tr())),
      );
      return false;
    case SaveFailed():
      messenger.showSnackBar(
        SnackBar(content: Text('note.extSaveFailed'.tr())),
      );
      return false;
  }
}

/// W5: changed underneath is a CHOICE. Three legs, none of them silent.
Future<bool> _resolveConflict(
  BuildContext context,
  WidgetRef ref,
  String markdown,
  ExternalSaver saver,
  ExternalSession session,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showAwSheet<String>(
    context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AwSpace.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'note.extConflictTitle'.tr(),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: AwSpace.x2),
                Text(
                  'note.extConflictBody'.tr(
                    args: {'name': session.document.name},
                  ),
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          ListTile(
            key: const Key('external-conflict-reload'),
            leading: const Icon(Icons.refresh),
            title: Text('note.extReload'.tr()),
            subtitle: Text('note.extReloadHint'.tr()),
            onTap: () => Navigator.of(sheetContext).pop('reload'),
          ),
          ListTile(
            key: const Key('external-conflict-copy'),
            leading: const Icon(Icons.file_copy_outlined),
            title: Text('note.extSaveCopy'.tr()),
            subtitle: Text('note.extSaveCopyHint'.tr()),
            onTap: () => Navigator.of(sheetContext).pop('copy'),
          ),
          ListTile(
            key: const Key('external-conflict-overwrite'),
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text('note.extOverwrite'.tr()),
            subtitle: Text('note.extOverwriteHint'.tr()),
            onTap: () => Navigator.of(sheetContext).pop('overwrite'),
          ),
          const SizedBox(height: AwSpace.x4),
        ],
      ),
    ),
  );

  switch (choice) {
    case 'reload':
      await ref.read(externalSessionProvider.notifier).reload();
      return false; // the caller re-seeds the editor from the new document
    case 'overwrite':
      // The ONLY place `force` is reachable, which is what makes a silent
      // overwrite impossible to express.
      final forced = await saver.save(
        markdown,
        expected: session.document.stamp,
        encoding: session.document.encoding,
        intent: SaveIntent.force,
      );
      if (forced is SaveSucceeded) {
        ref
            .read(externalSessionProvider.notifier)
            .adoptStamp(forced.stamp, markdown);
        messenger.showSnackBar(SnackBar(content: Text('note.extSaved'.tr())));
        return true;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('note.extSaveFailed'.tr())),
      );
      return false;
    case 'copy':
      await saveExternalCopy(ref, markdown, session);
      return false;
    default:
      return false;
  }
}

/// W5's third leg. An export, not the same handle — the original is left
/// exactly as the other writer left it.
Future<void> saveExternalCopy(
  WidgetRef ref,
  String markdown,
  ExternalSession session,
) async {
  final bytes = encodeExternalText(markdown, session.document.encoding);
  await FilePicker.saveFile(
    fileName: 'copy-${session.document.name}',
    bytes: Uint8List.fromList(bytes),
  );
}
