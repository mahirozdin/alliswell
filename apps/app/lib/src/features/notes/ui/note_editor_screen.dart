import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/tokens.dart';
import '../data/delta_markdown.dart';
import '../data/note.dart';
import '../providers.dart';
import '../../workspaces/workspaces.dart';

/// Rich note editor (OPH-044): flutter_quill content with debounced delta
/// autosave. A new note (noteId == null) is created on the first save; the
/// generated markdown is stored alongside the delta and drives the preview.
class NoteEditorScreen extends ConsumerWidget {
  const NoteEditorScreen({super.key, this.noteId});

  final String? noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
  const _NoteEditor({required this.note});

  final NoteDetail? note;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  static const _autosaveDelay = Duration(milliseconds: 1500);

  late final TextEditingController _title;
  late final QuillController _quill;
  Timer? _debounce;
  String? _noteId;
  bool _isPinned = false;
  bool _isArchived = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteId = widget.note?.id;
    _isPinned = widget.note?.isPinned ?? false;
    _isArchived = widget.note?.isArchived ?? false;
    _title = TextEditingController(text: widget.note?.title ?? '');
    _quill = QuillController.basic();
    final delta = widget.note?.contentDelta;
    if (delta != null && delta.isNotEmpty) {
      _quill.document = Document.fromJson(delta);
    }
    _title.addListener(_markDirty);
    _quill.document.changes.listen((_) => _markDirty());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Flush a pending save without awaiting (screen is going away).
    if (_dirty) unawaited(_save());
    _title.dispose();
    _quill.dispose();
    super.dispose();
  }

  void _markDirty() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, _save);
  }

  List<Map<String, dynamic>> get _deltaJson =>
      _quill.document.toDelta().toJson().cast<Map<String, dynamic>>();

  String get _titleText =>
      _title.text.trim().isEmpty ? 'Untitled' : _title.text.trim();

  /// The title is part of the document (Apple-Notes style): exports lead
  /// with it as an H1 (feedback round 1).
  String get _markdown => '# $_titleText\n\n${deltaToMarkdown(_deltaJson)}';

  Map<String, dynamic> get _body => {
    'title': _titleText,
    'contentDelta': _deltaJson,
    'contentMarkdown': _markdown,
  };

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    _saving = true;
    _dirty = false;
    try {
      final store = ref.read(noteStoreProvider);
      if (_noteId == null) {
        final workspaces = await ref.read(workspacesProvider.future);
        if (workspaces.isEmpty) return;
        _noteId = await store.create(workspaces.first.id, _body);
      } else {
        await store.update(_noteId!, _body);
      }
    } on Object {
      _dirty = true; // keep the changes marked; the next edit retries
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

  void _showMarkdownPreview() {
    final markdown = _markdown;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: SingleChildScrollView(
          child: SelectableText(
            markdown.isEmpty ? '*Empty note*' : markdown,
            key: const Key('markdown-preview'),
            style: const TextStyle(fontFamily: 'monospace', height: 1.6),
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final id = _noteId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
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
    if (mounted) context.go('/notes');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [
          IconButton(
            tooltip: _isPinned ? 'Unpin' : 'Pin',
            icon: Icon(
              _isPinned ? Icons.star : Icons.star_border,
              color: _isPinned ? context.awTokens.warning : null,
            ),
            onPressed: _togglePin,
          ),
          IconButton(
            tooltip: _isArchived ? 'Unarchive' : 'Archive',
            icon: Icon(
              _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            onPressed: _toggleArchived,
          ),
          IconButton(
            tooltip: 'Markdown preview',
            icon: const Icon(Icons.preview_outlined),
            onPressed: _showMarkdownPreview,
          ),
          IconButton(
            tooltip: 'Delete note',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: QuillSimpleToolbar(
                  controller: _quill,
                  config: const QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    showFontFamily: false,
                    showFontSize: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showAlignmentButtons: false,
                    showIndent: false,
                    showDirection: false,
                    showSearchButton: false,
                  ),
                ),
              ),
            ),
          ),
          // Apple-Notes style: the title is the document's fixed first block —
          // an H1 the note content flows under (feedback round 1). Content is
          // width-capped for a readable measure on wide screens.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: TextField(
                        key: const Key('note-title'),
                        controller: _title,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Title',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: QuillEditor.basic(
                          controller: _quill,
                          config: const QuillEditorConfig(
                            placeholder: 'Start writing…',
                            padding: EdgeInsets.only(top: 8, bottom: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
