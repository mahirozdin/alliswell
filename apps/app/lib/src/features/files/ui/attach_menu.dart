import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheets.dart';
import '../providers.dart';

/// The attach affordance (DESIGN §30 A1/A4) — OPH-244.
///
/// One implementation, four surfaces. Round 17 #2: a single "Add file" button
/// promised the Files app, so someone looking for a photo had no reason to tap
/// it — and if they did, their photos were not there. Now the button opens a
/// short menu that names each way in.
///
/// On platforms with only one way in (web, desktop) NO sheet appears: the
/// button resolves straight to that source. A one-item menu is a dead tap
/// (DESIGN §22).
enum AttachButtonStyle { outlined, text }

class AttachButton extends ConsumerWidget {
  const AttachButton({
    super.key,
    required this.onPicked,
    this.style = AttachButtonStyle.outlined,
    this.enabled = true,
    this.labelKey = 'file.add',
    this.icon = Icons.attach_file,
    this.buttonKey,
  });

  /// Receives whatever the chosen path produced. Never called with an empty
  /// list — backing out of a picker is not an event anyone needs.
  final Future<void> Function(List<PickedUpload> picks) onPicked;

  final AttachButtonStyle style;
  final bool enabled;
  final String labelKey;
  final IconData icon;

  /// Kept overridable because the surfaces that already had a button keep their
  /// own keys, and their tests still assert on them.
  final Key? buttonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(attachSourcesProvider);
    final label = Text(labelKey.tr());
    final leading = Icon(icon, size: 18);
    final onPressed = enabled ? () => _run(context, ref, sources) : null;

    // The SAME button types as before the menu existed: the theme's tap-target
    // sizing and existing widget-type assertions both depend on it.
    return switch (style) {
      AttachButtonStyle.outlined => OutlinedButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        icon: leading,
        label: label,
      ),
      AttachButtonStyle.text => TextButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        icon: leading,
        label: label,
      ),
    };
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    List<AttachSource> sources,
  ) async {
    final source = sources.length == 1
        ? sources.single
        : await showAttachSourceSheet(context, sources: sources);
    if (source == null || !context.mounted) return;
    final picks = await pickFrom(context, ref, source);
    if (picks.isEmpty) return;
    await onPicked(picks);
  }
}

/// The menu itself. Returns null when the user backs out.
Future<AttachSource?> showAttachSourceSheet(
  BuildContext context, {
  required List<AttachSource> sources,
}) {
  // Through showAwSheet, which already solves OPH-212: inside a shell branch a
  // plain sheet renders UNDER the shell's own glass bar and FAB.
  return showAwSheet<AttachSource>(
    context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x5,
              0,
              AwSpace.x5,
              AwSpace.x2,
            ),
            child: Text(
              'file.attachTitle'.tr(),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final source in sources)
            ListTile(
              key: Key(attachSourceSheetKey(source)),
              leading: Icon(_sourceIcon(source)),
              title: Text(attachSourceLabelKey(source).tr()),
              onTap: () => Navigator.of(sheetContext).pop(source),
            ),
          const SizedBox(height: AwSpace.x2),
        ],
      ),
    ),
  );
}

/// Runs ONE named path. Never throws, and says why when it fails (DESIGN
/// §30 A8) — a picker that blows up used to take the whole async chain with it,
/// because nothing anywhere caught a `PlatformException`.
Future<List<PickedUpload>> pickFrom(
  BuildContext context,
  WidgetRef ref,
  AttachSource source,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await ref.read(filePickerProvider)(source);
  } on PlatformException {
    messenger?.showSnackBar(SnackBar(content: Text('file.pickFailed'.tr())));
    return const [];
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text('file.pickFailed'.tr())));
    return const [];
  }
}

IconData _sourceIcon(AttachSource source) => switch (source) {
  AttachSource.photoLibrary ||
  AttachSource.imageLibrary => Icons.photo_library_outlined,
  AttachSource.camera => Icons.photo_camera_outlined,
  AttachSource.videoLibrary => Icons.video_library_outlined,
  AttachSource.audioFiles => Icons.library_music_outlined,
  AttachSource.anyFile => Icons.folder_open_outlined,
};
