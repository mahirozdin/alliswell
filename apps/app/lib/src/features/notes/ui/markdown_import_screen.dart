/// Read a `.md` file in AllisWell, then keep it if you want to.
///
/// Two entry points, one screen: the Notes tab's "Open a markdown file…", and
/// the OS handing us a document because AllisWell is registered for `.md`
/// (Android `ACTION_VIEW`, iOS/macOS `CFBundleDocumentTypes`).
///
/// The preview is a READ-ONLY `QuillEditor` over the very delta an import would
/// write — not a second markdown renderer. A separate preview widget could
/// drift from the importer and show the user something they will not get; this
/// way what you read is exactly what you save.
library;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../files/ui/note_media.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../../workspaces/workspaces.dart';
import '../data/delta_markdown.dart';
import '../data/markdown_delta.dart';
import '../data/markdown_source.dart';
import '../providers.dart';

/// Holds a document the OS handed us until the viewer picks it up — the
/// `PendingSharePayload` pattern, and for the same reason: the file can arrive
/// before any screen is mounted.
class PendingMarkdown extends Notifier<MarkdownDocument?> {
  @override
  MarkdownDocument? build() => null;

  void remember(MarkdownDocument doc) => state = doc;

  MarkdownDocument? take() {
    final pending = state;
    if (pending != null) state = null;
    return pending;
  }
}

final pendingMarkdownProvider =
    NotifierProvider<PendingMarkdown, MarkdownDocument?>(PendingMarkdown.new);

/// Opens the picker and routes to the viewer. Returns false when the user
/// backed out, so the caller can leave its menu open.
Future<bool> openMarkdownFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  MarkdownDocument? doc;
  try {
    doc = await ref.read(markdownSourceProvider).pick();
  } on MarkdownTooLarge catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'note.mdTooLarge'.tr(
            args: {'size': (e.bytes / (1024 * 1024)).toStringAsFixed(1)},
          ),
        ),
      ),
    );
    return false;
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text('note.mdOpenFailed'.tr())));
    return false;
  }
  if (doc == null) return false;
  ref.read(pendingMarkdownProvider.notifier).remember(doc);
  router.push('/notes/import');
  return true;
}

class MarkdownImportScreen extends ConsumerStatefulWidget {
  const MarkdownImportScreen({super.key});

  @override
  ConsumerState<MarkdownImportScreen> createState() =>
      _MarkdownImportScreenState();
}

class _MarkdownImportScreenState extends ConsumerState<MarkdownImportScreen> {
  MarkdownDocument? _doc;
  QuillController? _preview;
  late final TextEditingController _title = TextEditingController();
  String? _projectId;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    // READ here, CLEAR after the frame. Riverpod forbids writing to a provider
    // during a widget life-cycle, and `take()` writes — the AI share path gets
    // away with it only because it runs inside a `ref.listen` callback. The
    // document is still consumed exactly once (the PendingDeepLink rule): come
    // back to this route later and you get the empty state, not a replay.
    final doc = ref.read(pendingMarkdownProvider);
    if (doc == null) return;
    _load(doc);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pendingMarkdownProvider.notifier).take();
    });
  }

  void _load(MarkdownDocument doc) {
    final split = splitMarkdownTitle(doc.markdown, fallback: doc.baseName);
    _doc = doc;
    _title.text = split.title;
    final controller = QuillController.basic()
      ..readOnly = true
      ..document = Document.fromJson(markdownToDelta(split.body));
    _preview = controller;
  }

  @override
  void dispose() {
    _preview?.dispose();
    _title.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _delta =>
      _preview!.document.toDelta().toJson().cast<Map<String, dynamic>>();

  Future<void> _import() async {
    final doc = _doc;
    if (doc == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final workspaces = await ref.read(workspacesProvider.future);
      if (workspaces.isEmpty) return;
      final title = _title.text.trim().isEmpty
          ? doc.baseName
          : _title.text.trim();
      final delta = _delta;
      final noteId = await ref
          .read(noteStoreProvider)
          .create(workspaces.first.id, {
            'title': title,
            'projectId': _projectId,
            'contentDelta': delta,
            'contentMarkdown': '# $title\n\n${deltaToMarkdown(delta)}',
          });
      messenger.showSnackBar(
        SnackBar(content: Text('note.mdImported'.tr(args: {'name': doc.name}))),
      );
      // Straight into the note: the point of importing is to have it, and the
      // viewer has nothing left to say.
      router.pushReplacement('/notes/$noteId');
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('note.mdImportFailed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = _doc;
    final preview = _preview;

    if (doc == null || preview == null) {
      // Reached directly (a deep link, a reload) with nothing to show.
      return Scaffold(
        appBar: AppBar(title: Text('note.mdViewerTitle'.tr())),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'note.mdNothingOpen'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('md-open-empty'),
                  onPressed: () => openMarkdownFile(context, ref),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text('note.mdOpen'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final projects = ref.watch(projectsControllerProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text('note.mdViewerTitle'.tr()),
        actions: [
          IconButton(
            key: const Key('md-open-another'),
            tooltip: 'note.mdOpen'.tr(),
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => openMarkdownFile(context, ref),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Provenance first: this is somebody else's file, and the user
              // should see which one before deciding to keep it.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doc.name,
                        key: const Key('md-source-name'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: TextField(
                  key: const Key('md-title'),
                  controller: _title,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'note.titleHint'.tr(),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const Divider(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: QuillEditor.basic(
                    controller: preview,
                    config: QuillEditorConfig(
                      // Reading, not editing — the import is the way to edit.
                      showCursor: false,
                      padding: const EdgeInsets.only(top: 4, bottom: 16),
                      embedBuilders: awNoteEmbedBuilders(),
                    ),
                  ),
                ),
              ),
              _ImportBar(
                projects: projects,
                projectId: _projectId,
                onProject: (id) => setState(() => _projectId = id),
                saving: _saving,
                onImport: _import,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportBar extends StatelessWidget {
  const _ImportBar({
    required this.projects,
    required this.projectId,
    required this.onProject,
    required this.saving,
    required this.onImport,
  });

  final List<dynamic> projects;
  final String? projectId;
  final ValueChanged<String?> onProject;
  final bool saving;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: context.awTokens.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "Add to a project" is the SAME control the create sheet uses, so
            // importing does not invent a second way to choose a project.
            ProjectPickerField(
              key: const Key('md-project'),
              projects: projects.cast(),
              value: projectId,
              onChanged: onProject,
              decoration: InputDecoration(
                labelText: 'note.mdProject'.tr(),
                helperText: 'note.mdProjectHint'.tr(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('md-import'),
              onPressed: saving ? null : onImport,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.note_add_outlined),
              label: Text('note.mdImport'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
