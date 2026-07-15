import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/note.dart';
import 'data/note_store.dart';

export 'data/note_store.dart' show NotesFilter, NotesQuery;

/// Local-first store (OPH-054): reads watch the drift replica, writes are
/// optimistic + outbox'd.
final noteStoreProvider = Provider<NoteStore>(
  (ref) => NoteStore(
    ref.watch(databaseProvider),
    () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);

class NotesQueryController extends Notifier<NotesQuery> {
  @override
  NotesQuery build() => const NotesQuery();

  void setFilter(NotesFilter filter) => state = state.copyWith(filter: filter);

  void setSearch(String search) => state = state.copyWith(search: search);
}

final notesQueryProvider = NotifierProvider<NotesQueryController, NotesQuery>(
  NotesQueryController.new,
);

/// The Notes section list — reacts to the query (chips + search box). Search
/// is a local substring scan while offline-first (server FULLTEXT remains the
/// canonical ranking).
final notesListProvider = StreamProvider<List<NoteRow>>((ref) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  final query = ref.watch(notesQueryProvider);
  yield* ref.watch(noteStoreProvider).watchList(workspaces.first.id, query);
});

/// Star tap on a note row: flip the pin without opening the editor.
Future<void> toggleNotePinned(WidgetRef ref, NoteRow note) =>
    ref.read(noteStoreProvider).update(note.id, {'isPinned': !note.isPinned});

/// Archive/unarchive a note from its row menu or the editor.
Future<void> setNoteArchived(WidgetRef ref, NoteRow note, bool archived) =>
    ref.read(noteStoreProvider).update(note.id, {'isArchived': archived});

/// Notes shown on a project's Notes tab (attached ∪ linked).
final projectNotesProvider = StreamProvider.family<List<NoteRow>, String>((
  ref,
  projectId,
) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  yield* ref
      .watch(noteStoreProvider)
      .watchForProject(workspaces.first.id, projectId);
});

/// Full note for the editor — live, so pulled edits show up in place.
final noteDetailProvider = StreamProvider.family<NoteDetail, String>((
  ref,
  noteId,
) {
  ref.watch(syncEngineProvider);
  return ref.watch(noteStoreProvider).watchDetail(noteId);
});
