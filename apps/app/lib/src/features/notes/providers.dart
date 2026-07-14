import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/note.dart';
import 'data/notes_api.dart';

final notesApiProvider = Provider<NotesApi>(
  (ref) => NotesApi(ref.watch(apiClientProvider)),
);

enum NotesFilter { all, pinned }

class NotesQuery {
  const NotesQuery({this.filter = NotesFilter.all, this.search = ''});

  final NotesFilter filter;
  final String search;

  NotesQuery copyWith({NotesFilter? filter, String? search}) =>
      NotesQuery(filter: filter ?? this.filter, search: search ?? this.search);
}

class NotesQueryController extends Notifier<NotesQuery> {
  @override
  NotesQuery build() => const NotesQuery();

  void setFilter(NotesFilter filter) => state = state.copyWith(filter: filter);

  void setSearch(String search) => state = state.copyWith(search: search);
}

final notesQueryProvider = NotifierProvider<NotesQueryController, NotesQuery>(
  NotesQueryController.new,
);

/// The Notes section list — reacts to the query (chips + search box).
final notesListProvider = FutureProvider<List<NoteRow>>((ref) async {
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) return const [];
  final query = ref.watch(notesQueryProvider);
  final page = await ref
      .watch(notesApiProvider)
      .list(
        workspaces.first.id,
        pinned: query.filter == NotesFilter.pinned ? true : null,
        query: query.search.trim().isEmpty ? null : query.search.trim(),
        limit: 100,
      );
  return page.items;
});

/// Notes shown on a project's Notes tab (attached ∪ linked).
final projectNotesProvider = FutureProvider.family<List<NoteRow>, String>(
  (ref, projectId) async =>
      (await ref.watch(notesApiProvider).listForProject(projectId)).items,
);

/// Full note for the editor.
final noteDetailProvider = FutureProvider.family<NoteDetail, String>(
  (ref, noteId) => ref.watch(notesApiProvider).get(noteId),
);

/// Call after any note write from screen code.
void invalidateNoteData(WidgetRef ref, {String? noteId, String? projectId}) {
  ref.invalidate(notesListProvider);
  if (noteId != null) ref.invalidate(noteDetailProvider(noteId));
  if (projectId != null) ref.invalidate(projectNotesProvider(projectId));
}
