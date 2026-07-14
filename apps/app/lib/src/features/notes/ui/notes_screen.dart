import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../screens/home_shell.dart';
import '../data/note.dart';
import '../providers.dart';

/// Notes section (OPH-043): search box, All/Pinned chips, server-driven list.
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

    return Scaffold(
      appBar: buildSectionAppBar(context, 'Notes'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New note',
        onPressed: () => context.go('/notes/new'),
        child: const Icon(Icons.add),
      ),
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
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: query.filter == NotesFilter.all,
                  onSelected: (_) => ref
                      .read(notesQueryProvider.notifier)
                      .setFilter(NotesFilter.all),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Pinned'),
                  selected: query.filter == NotesFilter.pinned,
                  onSelected: (_) => ref
                      .read(notesQueryProvider.notifier)
                      .setFilter(NotesFilter.pinned),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(notesListProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyNotes()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          NoteTile(note: items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared note row (also used by the project Notes tab).
class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note});

  final NoteRow note;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: note.snippet.isEmpty
          ? null
          : Text(note.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: note.isPinned ? const Icon(Icons.push_pin, size: 18) : null,
      onTap: () => context.go('/notes/${note.id}'),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('No notes here', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Capture the first one with the + button.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
