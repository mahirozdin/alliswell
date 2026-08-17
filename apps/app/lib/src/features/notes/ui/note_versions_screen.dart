import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../../sync/providers.dart';
import '../data/note_versions_api.dart';
import '../providers.dart';
import 'modes/reading_mode.dart';

/// Version history (OPH-269, DESIGN §35 V4–V6).
///
/// A day-grouped list read in the editor's own clothes: the preview uses the
/// same reading renderer the note itself uses, so there is no second renderer
/// to keep honest. Origin chips answer "who wrote this" — and for one human
/// with several devices, the useful author axis is the DEVICE.
///
/// Offline it says so plainly (V6): historical bodies live on the server and
/// are never replicated, so an empty list here would be a lie.
class NoteVersionsScreen extends ConsumerWidget {
  const NoteVersionsScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(noteVersionsProvider(noteId));
    return Scaffold(
      appBar: AppBar(title: Text('versions.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: versions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => AwEmptyState(
              key: const Key('versions-offline'),
              icon: Icons.cloud_off_outlined,
              title: 'versions.offlineTitle'.tr(),
              message: 'versions.offlineBody'.tr(),
            ),
            data: (list) => list.isEmpty
                ? AwEmptyState(
                    icon: Icons.history,
                    title: 'versions.emptyTitle'.tr(),
                    message: 'versions.emptyBody'.tr(),
                  )
                : _VersionList(noteId: noteId, versions: list),
          ),
        ),
      ),
    );
  }
}

/// "Bugün" / "Dün" / the date — the grouping Docs and Notion both use, because
/// a person looks for *when*, not for a row number.
String dayHeaderFor(
  DateTime when, {
  required String dateFormat,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final diff = todayDay.difference(day).inDays;
  if (diff == 0) return 'versions.today'.tr();
  if (diff == 1) return 'versions.yesterday'.tr();
  return awFormatDate(when, format: dateFormat);
}

/// The origin chip's words. `clientId` decides "this device" vs "another one"
/// — the same id the sync engine pushes with.
String originLabel(NoteVersionSummary version, {String? myClientId}) =>
    switch (version.origin) {
      'merge' => 'versions.originMerge'.tr(),
      'conflict' => 'versions.originConflict'.tr(),
      'restore' => 'versions.originRestore'.tr(),
      'import' => 'versions.originImport'.tr(),
      'api' => 'versions.originApi'.tr(),
      'mcp' => 'versions.originAi'.tr(),
      'create' => 'versions.originCreate'.tr(),
      _ =>
        version.clientId != null && version.clientId == myClientId
            ? 'versions.originThisDevice'.tr()
            : 'versions.originOtherDevice'.tr(),
    };

class _VersionList extends ConsumerWidget {
  const _VersionList({required this.noteId, required this.versions});

  final String noteId;
  final List<NoteVersionSummary> versions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = ref.watch(dateFormatProvider);
    final myClientId = ref.watch(syncClientIdProvider).value;
    final theme = Theme.of(context);

    String? lastHeader;
    final children = <Widget>[];
    for (final version in versions) {
      final header = dayHeaderFor(version.createdAt, dateFormat: dateFormat);
      if (header != lastHeader) {
        lastHeader = header;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              AwSpace.x4,
              AwSpace.x4,
              AwSpace.x2,
            ),
            child: Text(header, style: theme.textTheme.labelLarge),
          ),
        );
      }
      children.add(
        Card(
          child: ListTile(
            key: Key('version-${version.id}'),
            title: Text(
              awFormatTime(version.createdAt, format: dateFormat),
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(originLabel(version, myClientId: myClientId)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    NoteVersionPreview(noteId: noteId, version: version),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: awListPadding(context, top: AwSpace.x1),
      children: children,
    );
  }
}

/// One version, read in the note's own reading renderer, with a word-level
/// diff toggle against the body as it is now.
class NoteVersionPreview extends ConsumerStatefulWidget {
  const NoteVersionPreview({
    super.key,
    required this.noteId,
    required this.version,
  });

  final String noteId;
  final NoteVersionSummary version;

  @override
  ConsumerState<NoteVersionPreview> createState() => _NoteVersionPreviewState();
}

class _NoteVersionPreviewState extends ConsumerState<NoteVersionPreview> {
  bool _showDiff = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final arg = (noteId: widget.noteId, versionId: widget.version.id);
    final detail = ref.watch(noteVersionDetailProvider(arg));
    return Scaffold(
      appBar: AppBar(
        title: Text(originLabel(widget.version)),
        actions: [
          IconButton(
            key: const Key('version-diff-toggle'),
            tooltip: 'versions.showDiff'.tr(),
            isSelected: _showDiff,
            icon: const Icon(Icons.difference_outlined),
            onPressed: () => setState(() => _showDiff = !_showDiff),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _showDiff
              ? _DiffView(noteId: widget.noteId, versionId: widget.version.id)
              : detail.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => AwErrorState(
                    message: 'versions.offlineBody'.tr(),
                    onRetry: () =>
                        ref.invalidate(noteVersionDetailProvider(arg)),
                  ),
                  // ReadingMode scrolls itself (it is the note's own reader,
                  // reused whole — V4). Wrapping it in another scroll view is
                  // an unbounded-height crash, which is how this was found.
                  data: (value) => Padding(
                    padding: awListPadding(context, top: AwSpace.x2),
                    child: ReadingMode(markdown: value.markdown),
                  ),
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('version-restore-copy'),
                  onPressed: _busy ? null : () => _restore('copy'),
                  child: Text('versions.restoreCopy'.tr()),
                ),
              ),
              const SizedBox(width: AwSpace.x3),
              Expanded(
                child: FilledButton(
                  key: const Key('version-restore'),
                  onPressed: _busy ? null : () => _confirmRestore(),
                  child: Text('versions.restore'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('versions.restoreConfirmTitle'.tr()),
        // V5's sentence, said where the decision is made: restoring adds to
        // history, it does not rewrite it — so this is undoable in turn.
        content: Text('versions.restoreConfirmBody'.tr()),
        actions: [
          TextButton(
            key: const Key('version-restore-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('version-restore-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('versions.restore'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) await _restore('replace');
  }

  Future<void> _restore(String mode) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(noteVersionsApiProvider)
          .restore(widget.noteId, widget.version.id, mode: mode);
      ref.invalidate(noteVersionsProvider(widget.noteId));
      // The replica catches up through the ordinary pull — the restore is a
      // normal write, which is the whole point of doing it server-side.
      ref.read(syncEngineProvider)?.syncNow();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mode == 'copy'
                ? 'versions.restoredCopy'.tr()
                : 'versions.restored'.tr(),
          ),
        ),
      );
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The server's word-level segments, drawn and nothing more (ADR-0031 §8).
class _DiffView extends ConsumerWidget {
  const _DiffView({required this.noteId, required this.versionId});

  final String noteId;
  final String versionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (noteId: noteId, versionId: versionId);
    final diff = ref.watch(noteVersionDiffProvider(arg));
    final theme = Theme.of(context);
    final tokens = context.awTokens;

    return diff.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => AwErrorState(
        message: 'versions.offlineBody'.tr(),
        onRetry: () => ref.invalidate(noteVersionDiffProvider(arg)),
      ),
      data: (segments) => SingleChildScrollView(
        padding: awListPadding(context, top: AwSpace.x2),
        child: SelectableText.rich(
          key: const Key('version-diff'),
          TextSpan(
            children: [
              for (final segment in segments)
                TextSpan(
                  text: segment.value,
                  style: switch (segment.type) {
                    // Colour is never the only carrier (§3): removed text is
                    // struck through, added text is underlined.
                    'added' => theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.success,
                      decoration: TextDecoration.underline,
                    ),
                    'removed' => theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      decoration: TextDecoration.lineThrough,
                    ),
                    _ => theme.textTheme.bodyMedium,
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
