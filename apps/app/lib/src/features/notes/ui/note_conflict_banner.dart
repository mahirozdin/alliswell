import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../data/note_versions_api.dart';
import '../providers.dart';
import 'note_versions_screen.dart';

/// The conflict surface (OPH-269, DESIGN §35 V3).
///
/// A band on the note itself — not a stray sibling note in some other folder,
/// which is Joplin's documented anti-pattern for one person on two devices.
/// The decision stays where the user's attention already is.
///
/// **No action here can lose anything**, and that is what makes four buttons
/// safe to offer: the refused body is already a version on the server (V1), so
/// "use theirs" discards nothing, and "use mine" is an ordinary restore that
/// itself becomes history (V5).
class NoteConflictBanner extends ConsumerStatefulWidget {
  const NoteConflictBanner({
    super.key,
    required this.noteId,
    required this.conflictVersionId,
  });

  final String noteId;
  final String conflictVersionId;

  @override
  ConsumerState<NoteConflictBanner> createState() => _NoteConflictBannerState();
}

class _NoteConflictBannerState extends ConsumerState<NoteConflictBanner> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('note-conflict-banner'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          AwSpace.x3,
          AwSpace.x4,
          AwSpace.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.call_split,
                  size: 20,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'conflict.bannerTitle'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              'conflict.bannerBody'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            Wrap(
              spacing: AwSpace.x2,
              children: [
                TextButton(
                  key: const Key('conflict-show-diff'),
                  onPressed: _busy ? null : _showDiff,
                  child: Text('conflict.showDiff'.tr()),
                ),
                TextButton(
                  key: const Key('conflict-use-mine'),
                  onPressed: _busy ? null : () => _resolve('replace'),
                  child: Text('conflict.useMine'.tr()),
                ),
                TextButton(
                  key: const Key('conflict-use-theirs'),
                  onPressed: _busy ? null : _useTheirs,
                  child: Text('conflict.useTheirs'.tr()),
                ),
                TextButton(
                  key: const Key('conflict-keep-both'),
                  onPressed: _busy ? null : () => _resolve('copy'),
                  child: Text('conflict.keepBoth'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDiff() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteVersionPreview(
          noteId: widget.noteId,
          version: NoteVersionSummary(
            id: widget.conflictVersionId,
            origin: 'conflict',
            createdAt: DateTime.now(),
            sizeBytes: 0,
          ),
        ),
      ),
    );
  }

  /// The server's body already won, so there is nothing to write — only the
  /// local pointer to clear. Ours is still in the history if this was wrong.
  Future<void> _useTheirs() async {
    await ref.read(noteStoreProvider).clearConflict(widget.noteId);
  }

  /// `replace` puts my refused body back as a new head; `copy` splits it into
  /// its own note — the Dropbox-style copy as a CHOSEN outcome (V3).
  Future<void> _resolve(String mode) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(noteVersionsApiProvider)
          .restore(widget.noteId, widget.conflictVersionId, mode: mode);
      await ref.read(noteStoreProvider).clearConflict(widget.noteId);
      ref.invalidate(noteVersionsProvider(widget.noteId));
      ref.read(syncEngineProvider)?.syncNow();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mode == 'copy'
                ? 'conflict.keptBoth'.tr()
                : 'conflict.usedMine'.tr(),
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
