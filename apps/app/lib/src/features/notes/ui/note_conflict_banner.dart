import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../data/note.dart';
import '../data/note_versions_api.dart';
import '../providers.dart';
import 'note_versions_screen.dart';
import 'version_labels.dart';

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
    this.onTookServerCopy,
  });

  final String noteId;
  final String conflictVersionId;

  /// The device took the server's copy ("use the other one"). The editor
  /// drops its unsaved typing and shows that copy — a pending autosave would
  /// otherwise send the refused text back with the server's own revision as
  /// its base, and win (OPH-490).
  final ValueChanged<NoteDetail>? onTookServerCopy;

  @override
  ConsumerState<NoteConflictBanner> createState() => _NoteConflictBannerState();
}

class _NoteConflictBannerState extends ConsumerState<NoteConflictBanner> {
  bool _busy = false;

  @override
  void didUpdateWidget(covariant NoteConflictBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new refusal is a new version the cached history does not have yet.
    if (oldWidget.conflictVersionId != widget.conflictVersionId) {
      ref.invalidate(noteVersionsProvider(widget.noteId));
    }
  }

  /// OPH-494: the two sides, named — my refused text and the text the server
  /// kept, each with its device and exact time. Read from history (an online
  /// surface): offline the lines are simply not drawn.
  ({NoteVersionSummary? mine, NoteVersionSummary? theirs}) _sides() {
    final list = ref.watch(noteVersionsProvider(widget.noteId)).value;
    if (list == null) return (mine: null, theirs: null);
    NoteVersionSummary? mine;
    NoteVersionSummary? theirs;
    for (final v in list) {
      if (v.id == widget.conflictVersionId) mine = v;
      // Newest first: the first row that is not a refusal is the text the
      // note holds now.
      if (theirs == null && v.origin != 'conflict') theirs = v;
    }
    return (mine: mine, theirs: theirs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sides = _sides();
    final myClientId = ref.watch(syncClientIdProvider).value;
    final dateFormat = ref.watch(dateFormatProvider);
    final lineStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onTertiaryContainer,
    );
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
            Text('conflict.bannerBody'.tr(), style: lineStyle),
            if (sides.mine != null) ...[
              const SizedBox(height: AwSpace.x1),
              Text(
                'conflict.mineLine'.tr(
                  args: {
                    'who': versionWho(
                      sides.mine!,
                      myClientId: myClientId,
                      dateFormat: dateFormat,
                    ),
                  },
                ),
                key: const Key('conflict-mine-line'),
                style: lineStyle,
              ),
            ],
            if (sides.theirs != null)
              Text(
                'conflict.theirsLine'.tr(
                  args: {
                    'who': versionWho(
                      sides.theirs!,
                      myClientId: myClientId,
                      dateFormat: dateFormat,
                    ),
                  },
                ),
                key: const Key('conflict-theirs-line'),
                style: lineStyle,
              ),
            const SizedBox(height: AwSpace.x2),
            Wrap(
              spacing: AwSpace.x2,
              children: [
                TextButton(
                  key: const Key('conflict-show-diff'),
                  style: _actionStyle(theme),
                  onPressed: _busy ? null : () => _showDiff(sides.mine),
                  child: Text('conflict.showDiff'.tr()),
                ),
                TextButton(
                  key: const Key('conflict-use-mine'),
                  style: _actionStyle(theme),
                  onPressed: _busy ? null : () => _resolve('replace'),
                  child: Text('conflict.useMine'.tr()),
                ),
                TextButton(
                  key: const Key('conflict-use-theirs'),
                  style: _actionStyle(theme),
                  onPressed: _busy ? null : _useTheirs,
                  child: Text('conflict.useTheirs'.tr()),
                ),
                TextButton(
                  key: const Key('conflict-keep-both'),
                  style: _actionStyle(theme),
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

  /// The banner's actions sit on `tertiaryContainer`, so they take that role's
  /// own ink — NOT the global `tokens.link`, which is tuned for `surface`.
  ///
  /// Measured, because this shipped wrong once (OPH-269): link on the dark
  /// `tertiaryContainer` is **2.79:1** — under 4.5 and under even the 3:1 icon
  /// floor — while `onTertiaryContainer` is 6.68 dark / 7.71 light. It was
  /// missed because `tertiaryContainer` was not in `contrast.py` at all and the
  /// hand-check measured the banner's TEXT, not the pair its BUTTONS paint.
  /// Both pairs are in the guard now.
  ///
  /// Only `foregroundColor` is set: a widget-level style merges over the
  /// ambient theme, so the global 44 px minimum tap target and stadium shape
  /// survive. Wrapping these in a `TextButtonTheme` would have replaced that
  /// theme wholesale and dropped both.
  ButtonStyle _actionStyle(ThemeData theme) => TextButton.styleFrom(
    foregroundColor: theme.colorScheme.onTertiaryContainer,
  );

  void _showDiff(NoteVersionSummary? mine) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteVersionPreview(
          noteId: widget.noteId,
          version:
              mine ??
              NoteVersionSummary(
                id: widget.conflictVersionId,
                origin: 'conflict',
                createdAt: DateTime.now(),
                sizeBytes: 0,
              ),
        ),
      ),
    );
  }

  /// OPH-490: the server's body already won on the SERVER — but the replica
  /// still holds the refused one, and no pull will ever correct it (a refusal
  /// writes nothing). So the device takes the server's copy now; an open
  /// editor adopts it. Ours is still in the history if this was wrong.
  Future<void> _useTheirs() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final server = await ref.read(notesApiProvider).get(widget.noteId);
      final store = ref.read(noteStoreProvider);
      // A save queued since keeps its text; the pointer still goes.
      if (await store.takeServerCopy(server)) {
        if (mounted) widget.onTookServerCopy?.call(server);
      } else {
        await store.clearConflict(widget.noteId);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
