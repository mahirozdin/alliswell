import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persisted_prefs.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../projects/providers.dart';
import '../data/note.dart';
import '../providers.dart';

String _shortDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// Notes section (OPH-043 + feedback round 1): search, All/Pinned/Archived
/// chips, list ↔ A4-card grid view toggle (persisted), quick pin stars and
/// archive actions.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(notesQueryProvider);
    final notes = ref.watch(notesListProvider);
    final viewMode = ref.watch(notesViewModeProvider);
    final isGrid = viewMode == 'grid';
    final projects = ref.watch(projectsControllerProvider).value ?? const [];
    final projectNames = {for (final p in projects) p.id: p.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            key: const Key('notes-view-toggle'),
            tooltip: isGrid ? 'List view' : 'Card view',
            icon: Icon(
              isGrid ? Icons.view_list_outlined : Icons.grid_view_outlined,
            ),
            onPressed: () => ref
                .read(notesViewModeProvider.notifier)
                .set(isGrid ? 'list' : 'grid'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      // FAB hoisted to HomeShell (OPH-101).
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('notes-search'),
              controller: _search,
              onSubmitted: (v) =>
                  ref.read(notesQueryProvider.notifier).setSearch(v),
              decoration: InputDecoration(
                hintText: 'Search notes…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          ref.read(notesQueryProvider.notifier).setSearch('');
                        },
                      ),
              ),
            ),
          ),
          // Horizontally scrollable so the filter strip never overflows on
          // phones (and survives extra chips like OPH-109's 'READMEs').
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (filter, label) in [
                  (NotesFilter.all, 'All'),
                  (NotesFilter.pinned, 'Pinned'),
                  (NotesFilter.archived, 'Archive'),
                  (NotesFilter.readmes, 'READMEs'),
                ]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: query.filter == filter,
                    onSelected: (_) =>
                        ref.read(notesQueryProvider.notifier).setFilter(filter),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: '$error',
                onRetry: () => ref.invalidate(notesListProvider),
              ),
              data: (items) => items.isEmpty
                  ? _EmptyNotes(archived: query.filter == NotesFilter.archived)
                  : isGrid
                  ? _NotesGrid(notes: items, projectNames: projectNames)
                  : ListView.builder(
                      padding: awListPadding(context, extraBottom: 72),
                      itemCount: items.length,
                      itemBuilder: (context, index) => NoteTile(
                        note: items[index],
                        projectName: projectNames[items[index].projectId],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared note row (also used by the project Notes tab): quick-pin star in
/// front, metadata line (edited/created/project), archive menu.
class NoteTile extends ConsumerWidget {
  const NoteTile({super.key, required this.note, this.projectName});

  final NoteRow note;
  final String? projectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = [
      'Edited ${_shortDate(note.updatedAt)}',
      'Created ${_shortDate(note.createdAt)}',
      ?projectName,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
          leading: IconButton(
            key: Key('pin-${note.id}'),
            tooltip: note.isPinned ? 'Unpin' : 'Pin',
            icon: Icon(
              note.isPinned ? Icons.star : Icons.star_border,
              color: note.isPinned ? context.awTokens.warning : null,
            ),
            onPressed: () => toggleNotePinned(ref, note),
          ),
          title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            note.snippet.isEmpty ? meta : '${note.snippet}\n$meta',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _NoteMenu(note: note),
          onTap: () => context.go('/notes/${note.id}'),
        ),
      ),
    );
  }
}

class _NoteMenu extends ConsumerWidget {
  const _NoteMenu({required this.note});

  final NoteRow note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Note actions',
      onSelected: (action) {
        if (action == 'archive') setNoteArchived(ref, note, !note.isArchived);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'archive',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              note.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(note.isArchived ? 'Unarchive' : 'Archive'),
          ),
        ),
      ],
    );
  }
}

/// A4-proportioned cards, Google-Docs-home style.
class _NotesGrid extends ConsumerWidget {
  const _NotesGrid({required this.notes, required this.projectNames});

  final List<NoteRow> notes;
  final Map<String, String> projectNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: awListPadding(context, top: AwSpace.x4, extraBottom: 72),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 210 / 297, // A4
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/notes/${note.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: note.isPinned ? 'Unpin' : 'Pin',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => toggleNotePinned(ref, note),
                        icon: Icon(
                          note.isPinned ? Icons.star : Icons.star_border,
                          size: 18,
                          color: note.isPinned
                              ? context.awTokens.warning
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        note.snippet,
                        overflow: TextOverflow.fade,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Edited ${_shortDate(note.updatedAt)}'
                    '${projectNames[note.projectId] != null ? ' · ${projectNames[note.projectId]}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    return AwEmptyState(
      icon: archived ? Icons.archive_outlined : Icons.description,
      title: archived ? 'Archive is empty' : 'No notes here',
      message: archived
          ? 'Archived notes land here for safekeeping.'
          : 'Capture the first one with the + button.',
    );
  }
}
