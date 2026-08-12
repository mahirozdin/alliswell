import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../quick_access/data/quick_link.dart';
import '../../quick_access/ui/quick_access_add.dart';
import '../../../i18n/i18n.dart';
import '../../files/providers.dart';
import '../../files/ui/file_widgets.dart' show UploadRowTile;
import '../../files/ui/note_drop_target.dart';
import '../../files/ui/note_media.dart';
import '../../../theme/tokens.dart';
import '../data/note.dart';
import '../data/external_document.dart';
import '../data/external_session.dart';
import '../data/note_document.dart';
import 'external_doc_band.dart';
import '../providers.dart';
import 'modes/note_mode_control.dart';
import 'modes/reading_mode.dart';
import 'modes/source_mode.dart';
import 'note_export.dart';
import '../../workspaces/workspaces.dart';

/// The note editor (OPH-044, rebuilt for three modes in OPH-248).
///
/// A note is a DOCUMENT (DESIGN §29). What it is made of decides which surfaces
/// may edit it — `NoteDocument` owns that decision, and this screen is the
/// shell around it: app bar, mode control, autosave.
///
/// The old `_showMarkdownPreview()` is gone. It was a read-only monospace sheet
/// of the generated markdown, which is neither Reading (that renders now) nor
/// Source (that edits now); keeping it would have left three ways to look at
/// one document, two of them worse.
class NoteEditorScreen extends ConsumerWidget {
  const NoteEditorScreen({super.key, this.noteId, this.external = false});

  final String? noteId;

  /// Whether this is somebody else's FILE rather than one of our notes
  /// (OPH-251). The same editor either way — same modes, same toolbar — which
  /// is the point: it is the same job. What changes is that the document is
  /// permanently marked (W1) and never autosaved (W2).
  final bool external;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (external) return const _NoteEditor(note: null, external: true);
    if (noteId == null) return const _NoteEditor(note: null);
    final note = ref.watch(noteDetailProvider(noteId!));
    return note.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$error')),
      ),
      data: (value) => _NoteEditor(note: value),
    );
  }
}

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({required this.note, this.external = false});

  final NoteDetail? note;
  final bool external;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  static const _autosaveDelay = Duration(milliseconds: 1500);

  late final NoteDocument _doc;
  Timer? _debounce;
  String? _noteId;
  bool _isPinned = false;
  bool _isArchived = false;
  bool _dirty = false;
  bool _saving = false;

  /// D21: autosave stops being silent.
  ///
  /// "Silent autosave plus an eventual failure is how people lose work and
  /// trust." Before this the editor saved without a word AND swallowed its
  /// errors — `_save`'s catch simply re-marked the note dirty and hoped the
  /// next keystroke would retry.
  _SaveState _saveState = _SaveState.idle;

  /// `State.mounted` is still TRUE inside `dispose()`, and `dispose` flushes a
  /// pending save — so the indicator's `setState` fired on a widget being torn
  /// down and the framework asserted "defunct". `mounted` is the wrong guard
  /// here; this is the right one.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _noteId = widget.note?.id;
    _isPinned = widget.note?.isPinned ?? false;
    _isArchived = widget.note?.isArchived ?? false;
    _doc = NoteDocument(note: widget.note ?? _externalSeed())
      ..addListener(_onDocChanged);
    // D1 opens a document that came from a file in Reading, which is right
    // when the OS handed it to us. This entry point is "Edit a file…", so it
    // lands on the editor instead — the mode control still offers both.
    if (widget.external) _doc.setMode(_doc.editorMode);
    _doc.title.addListener(_markDirty);
    _doc.quill.document.changes.listen((_) => _markDirty());
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    // Flush a pending save without awaiting (screen is going away) — but never
    // for an external document: leaving is not consent to write (W2).
    if (_dirty && !widget.external) unawaited(_save());
    _doc
      ..removeListener(_onDocChanged)
      ..dispose();
    super.dispose();
  }

  void _onDocChanged() {
    if (!_disposed && mounted) setState(() {});
  }

  void _setSaveState(_SaveState next) {
    if (_disposed || !mounted) return;
    setState(() => _saveState = next);
  }

  /// The document the external session opened, as a markdown-canonical note
  /// the editor already knows how to hold. Null for an ordinary new note.
  NoteDetail? _externalSeed() {
    if (!widget.external) return null;
    final session = ref.read(externalSessionProvider);
    if (session == null) return null;
    return NoteDetail(
      id: '',
      workspaceId: '',
      title: session.document.name,
      snippet: '',
      isPinned: false,
      isArchived: false,
      revision: 0,
      contentFormat: NoteFormat.markdown.wire,
      contentMarkdown: session.document.markdown,
    );
  }

  /// W3/W4 in one place: the saver exists only when the OS allows the write
  /// AND the bytes survive the round trip.
  ExternalSaver? get _externalSaver {
    final session = ref.watch(externalSessionProvider);
    return session == null ? null : saverFor(session);
  }

  /// The deliberate write (W2). Autosave never reaches this.
  Future<void> _saveExternal() async {
    final saved = await saveExternal(context, ref, _doc.markdown);
    if (!mounted) return;
    if (saved) {
      setState(() => _dirty = false);
      return;
    }
    // The conflict sheet's "reload" leg replaces the document under us, so the
    // editor has to take the new text rather than keep showing ours.
    final session = ref.read(externalSessionProvider);
    if (session != null && session.document.markdown != _doc.source.text) {
      setState(() {
        _doc.source.text = session.document.markdown;
        _dirty = false;
      });
    }
  }

  /// W4's other half, and the answer for a file we may not write: keep it here
  /// instead. Always available, because it never touches the file.
  Future<void> _saveExternalAsNote() async {
    final messenger = ScaffoldMessenger.of(context);
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty || !mounted) return;
    await ref
        .read(noteStoreProvider)
        .create(workspaces.first.id, _doc.bodyFor(_titleText));
    if (!mounted) return;
    setState(() => _dirty = false);
    messenger.showSnackBar(SnackBar(content: Text('note.extSavedAsNote'.tr())));
  }

  void _markDirty() {
    _dirty = true;
    // W2: autosave belongs to AllisWell's own notes. An external file — and
    // the note it would otherwise be silently imported as — changes only on a
    // deliberate action, so the timer is not started at all.
    if (widget.external) {
      if (!_disposed && mounted) setState(() {});
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, _save);
  }

  /// Media uploads need a target id: force-create a brand-new note first
  /// (the editor autosaves anyway — this just does it NOW). OPH-156.
  Future<({String noteId, String workspaceId})?> _ensureNote() async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return null;
    if (_noteId == null) {
      _dirty = true; // _save() is a no-op unless something is dirty
      await _save();
    }
    final id = _noteId;
    if (id == null) return null;
    return (noteId: id, workspaceId: workspaces.first.id);
  }

  String get _titleText => _doc.title.text.trim().isEmpty
      ? 'note.untitled'.tr()
      : _doc.title.text.trim();

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    _saving = true;
    _dirty = false;
    _setSaveState(_SaveState.saving);
    try {
      final store = ref.read(noteStoreProvider);
      final body = _doc.bodyFor(_titleText);
      if (_noteId == null) {
        final workspaces = await ref.read(workspacesProvider.future);
        if (workspaces.isEmpty) return;
        _noteId = await store.create(workspaces.first.id, body);
      } else {
        await store.update(_noteId!, body);
      }
      _setSaveState(_SaveState.saved);
    } on Object {
      _dirty = true; // keep the changes marked; the next edit retries
      // The retry behaviour is unchanged — what changes is that the reader can
      // SEE it did not land.
      _setSaveState(_SaveState.failed);
    } finally {
      _saving = false;
    }
  }

  Future<void> _togglePin() async {
    // Pinning needs a persisted note — force the first save if necessary.
    if (_noteId == null) {
      _dirty = true;
      await _save();
      if (_noteId == null) return;
    }
    final next = !_isPinned;
    setState(() => _isPinned = next);
    await ref.read(noteStoreProvider).update(_noteId!, {'isPinned': next});
  }

  Future<void> _toggleArchived() async {
    if (_noteId == null) {
      _dirty = true;
      await _save();
      if (_noteId == null) return;
    }
    final next = !_isArchived;
    setState(() => _isArchived = next);
    await ref.read(noteStoreProvider).update(_noteId!, {'isArchived': next});
  }

  /// The conversion door (DESIGN §29 D1, as amended in OPH-248).
  ///
  /// Named, deliberate, and warned — never a silent reinterpretation of
  /// somebody's note. Going to markdown flattens what Delta could hold; coming
  /// back parses what markdown can express. Either way the OTHER form is
  /// rebuilt from this one, so it is one-way in effect even though the button
  /// exists in both directions.
  Future<void> _convert() async {
    final toMarkdown = _doc.convertTarget == NoteFormat.markdown;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          toMarkdown
              ? 'note.convertToMarkdown'.tr()
              : 'note.convertToRich'.tr(),
        ),
        content: Text(
          toMarkdown
              ? 'note.convertToMarkdownBody'.tr()
              : 'note.convertToRichBody'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('note-convert-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('note.convertAction'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _doc.convert();
    _markDirty();
  }

  Future<void> _delete() async {
    final id = _noteId;
    final confirmed = await showDialog<bool>(
      context: context,
      // Round 13 #2: dialogs go to the ROOT navigator for the same
      // reason sheets do (OPH-212) — inside a shell branch the
      // Scaffold's own bar and FAB paint over them.
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('note.deleteTitle'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _debounce?.cancel();
    _dirty = false;
    if (id != null) {
      await ref.read(noteStoreProvider).delete(id);
    }
    if (!mounted) return;
    // Pop back to wherever we came from — the project Overview when opened via
    // /edit-note (OPH-109), or the notes list when opened from there. Fall back
    // to the Notes tab if this is somehow the only page.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/notes');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.external ? 'note.extTitle'.tr() : 'note.detailTitle'.tr(),
        ),
        actions: [
          // W3/W4: built ONLY when a saver exists. `saverFor` returns one only
          // from the writable arm of a sealed type, so on a read-only file —
          // or a non-UTF-8 one — there is nothing to bind this to and it does
          // not exist. A disabled button would be the dead affordance §22
          // forbids; the band says why instead.
          if (widget.external) ...[
            if (_externalSaver != null)
              IconButton(
                key: const Key('external-save'),
                tooltip: 'note.extSave'.tr(),
                icon: const Icon(Icons.save_outlined),
                onPressed: _saveExternal,
              ),
            IconButton(
              key: const Key('external-save-as-note'),
              tooltip: 'note.extSaveAsNote'.tr(),
              icon: const Icon(Icons.note_add_outlined),
              onPressed: _saveExternalAsNote,
            ),
          ] else ...[
            IconButton(
              tooltip: _isPinned ? 'note.unpin'.tr() : 'note.pin'.tr(),
              icon: Icon(
                _isPinned ? Icons.star : Icons.star_border,
                color: _isPinned ? context.awTokens.warning : null,
              ),
              onPressed: _togglePin,
            ),
            IconButton(
              tooltip: _isArchived
                  ? 'note.unarchive'.tr()
                  : 'note.archive'.tr(),
              icon: Icon(
                _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              onPressed: _toggleArchived,
            ),
            IconButton(
              tooltip: 'note.deleteTooltip'.tr(),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
          // OPH-201: an overflow rather than a sixth icon — this app bar is
          // already at the phone's limit. The mode control took the preview
          // button's place (OPH-248), so the count did not grow.
          //
          // Hidden for an external document: pin, archive, delete and quick
          // access all name a NOTE by id, and this one has none until the user
          // saves it as one.
          if (!widget.external)
            PopupMenuButton<String>(
              key: const Key('note-quick-menu'),
              tooltip: 'quick.actions'.tr(),
              onSelected: (value) {
                if (value == 'export-pdf') {
                  unawaited(
                    exportNoteAsPdf(
                      context,
                      ref,
                      title: _titleText,
                      deltaJson: _doc.deltaJson,
                      updatedAt: widget.note?.updatedAt,
                    ),
                  );
                  return;
                }
                if (value == 'convert') {
                  unawaited(_convert());
                  return;
                }
                if (_noteId case final id?) {
                  toggleQuickAccess(
                    context,
                    ref,
                    kind: QuickKind.note,
                    targetId: id,
                    suggestedTitle: _doc.title.text,
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: const Key('note-export-pdf'),
                  value: 'export-pdf',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text('note.exportPdf'.tr()),
                  ),
                ),
                PopupMenuItem(
                  key: const Key('note-convert'),
                  value: 'convert',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(
                      _doc.convertTarget == NoteFormat.markdown
                          ? 'note.convertToMarkdown'.tr()
                          : 'note.convertToRich'.tr(),
                    ),
                  ),
                ),
                if (_noteId case final id?)
                  quickAccessMenuItem(
                    value: 'quick',
                    isSaved: isInQuickAccess(ref, QuickKind.note, id),
                  ),
              ],
            ),
        ],
      ),
      body: NoteDropTarget(
        onFiles: _uploadDropped,
        child: Column(
          children: [
            // W1: above everything, so it is present in Reading, Live and
            // Source alike — "which file am I changing" stops being a nicety
            // the moment editing is possible.
            if (widget.external) ExternalDocBand(dirty: _dirty),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: NoteModeControl(
                      modes: _doc.availableModes,
                      active: _doc.mode,
                      onChanged: _doc.setMode,
                    ),
                  ),
                  _SaveIndicator(state: _saveState),
                ],
              ),
            ),
            if (_doc.mode == NoteMode.live) _liveToolbar(),
            // In-flight/failed media uploads for THIS note (F2: visible state).
            for (final job
                in ref
                    .watch(uploadsProvider)
                    .where(
                      (j) => j.targetType == 'note' && j.targetId == _noteId,
                    ))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: UploadRowTile(job: job),
              ),
            // Apple-Notes style: the title is the document's fixed first block —
            // an H1 the note content flows under (feedback round 1). Content is
            // width-capped for a readable measure on wide screens, EXCEPT in the
            // split view, which wants the whole window.
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _doc.mode == NoteMode.source ? 1400 : 760,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: TextField(
                          key: const Key('note-title'),
                          controller: _doc.title,
                          maxLines: null,
                          readOnly: _doc.mode == NoteMode.reading,
                          decoration: InputDecoration(
                            hintText: 'note.titleHint'.tr(),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                          ),
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      Expanded(child: _body()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A file dropped onto the editor: upload it to THIS note, then let the
  /// document decide where it lands (Live gets an embed, Source gets markdown).
  ///
  /// Same three steps the insert buttons take — ensure the note exists so the
  /// upload has a target, upload, insert — because a drop is a different door
  /// to the same room, not a different feature.
  Future<void> _uploadDropped(List<PickedUpload> picks) async {
    if (picks.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final target = await _ensureNote();
    if (target == null) return;

    for (final pick in picks) {
      final fileId = await ref
          .read(uploadsProvider.notifier)
          .start(
            workspaceId: target.workspaceId,
            targetType: 'note',
            targetId: target.noteId,
            source: pick,
          );
      if (fileId == null) continue; // the upload strip shows the failure
      final outcome = _doc.insertFile(
        fileId: fileId,
        name: pick.name,
        mime: pick.mime ?? mimeForName(pick.name),
      );
      if (outcome == NoteInsert.attachedOnly) {
        messenger?.showSnackBar(
          SnackBar(content: Text('file.attachedNotEmbedded'.tr())),
        );
      }
      _markDirty();
    }
  }

  Widget _liveToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: QuillSimpleToolbar(
                controller: _doc.quill,
                config: const QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showAlignmentButtons: false,
                  showIndent: false,
                  showDirection: false,
                  showSearchButton:
                      true, // D15: it shipped disabled — a control that did nothing (§22).
                ),
              ),
            ),
            // Epic 14 (OPH-156): inline images/videos.
            NoteMediaButtons(document: _doc, ensureNote: _ensureNote),
          ],
        ),
      ),
    ),
  );

  Widget _body() => switch (_doc.mode) {
    // D4: Reading is never editable-looking — no caret, no placeholder, no
    // toolbar. (Tappable task-list checkboxes that write back are OPH-249's,
    // and they need the source map this renderer already carries.)
    // D13/D14/D16 live in ReadingMode: the outline, folding and `#anchor`
    // jumps all need the same block index, so they share one owner.
    NoteMode.reading => ReadingMode(markdown: _doc.markdown),
    NoteMode.source => SourceMode(document: _doc, onChanged: _markDirty),
    NoteMode.live => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: QuillEditor.basic(
        controller: _doc.quill,
        config: QuillEditorConfig(
          placeholder: 'note.startWriting'.tr(),
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          embedBuilders: awNoteEmbedBuilders(),
        ),
      ),
    ),
  };
}

/// What autosave last did (D21).
enum _SaveState { idle, saving, saved, failed }

/// Small, non-blocking, and silent when there is nothing to say.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state});

  final _SaveState state;

  @override
  Widget build(BuildContext context) {
    if (state == _SaveState.idle) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final failed = state == _SaveState.failed;

    return Padding(
      key: const Key('note-save-state'),
      padding: const EdgeInsets.only(left: AwSpace.x2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (state) {
              _SaveState.saving => Icons.sync,
              _SaveState.saved => Icons.cloud_done_outlined,
              _ => Icons.cloud_off_outlined,
            },
            size: 16,
            color: failed ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x1),
          Text(
            switch (state) {
              _SaveState.saving => 'note.saving'.tr(),
              _SaveState.saved => 'note.saved'.tr(),
              _ => 'note.saveFailed'.tr(),
            },
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: failed ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
