import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_forge/markdown_forge.dart';

import '../../core/api_exception.dart';
import '../../core/list_sort.dart';
import '../../core/persisted_prefs.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import '../auth/providers.dart';
import 'data/note.dart';
import 'data/note_store.dart';
import 'data/note_versions_api.dart';
import 'data/notes_api.dart';

export 'data/note_store.dart'
    show NotesFilter, NotesQuery, kNoteSortChoices, noteSortComparator;

/// Local-first store (OPH-054): reads watch the drift replica, writes are
/// optimistic + outbox'd.
final noteStoreProvider = Provider<NoteStore>(
  (ref) => NoteStore(ref.watch(databaseProvider), () => pokeSync(ref)),
);

/// Note history (OPH-269) — an ONLINE surface: the list is fetched when the
/// screen opens and never cached in the replica (DESIGN §35 V6, the OPH-265
/// rule). Every mutation invalidates rather than patching a local list.
final noteVersionsApiProvider = Provider<NoteVersionsApi>(
  (ref) => NoteVersionsApi(ref.watch(apiClientProvider)),
);

final noteVersionsProvider =
    FutureProvider.family<List<NoteVersionSummary>, String>(
      (ref, noteId) => ref.watch(noteVersionsApiProvider).list(noteId),
    );

final noteVersionDiffProvider =
    FutureProvider.family<
      List<NoteDiffSegment>,
      ({String noteId, String versionId})
    >(
      (ref, arg) =>
          ref.watch(noteVersionsApiProvider).diff(arg.noteId, arg.versionId),
    );

final noteVersionDetailProvider =
    FutureProvider.family<
      NoteVersionDetail,
      ({String noteId, String versionId})
    >(
      (ref, arg) =>
          ref.watch(noteVersionsApiProvider).detail(arg.noteId, arg.versionId),
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
  final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
  if (workspaceId == null) {
    yield const [];
    return;
  }
  final query = ref
      .watch(notesQueryProvider)
      .copyWith(sort: ref.watch(notesSortStateProvider));
  yield* ref.watch(noteStoreProvider).watchList(workspaceId, query);
});

/// The persisted notes order, parsed (OPH-258). Kept out of `NotesQueryController`
/// so the preference stays a device setting rather than transient screen state.
final notesSortStateProvider = Provider<AwSortState>(
  (ref) => AwSortState.parse(ref.watch(notesSortProvider), kNoteSortChoices),
);

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
  final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
  if (workspaceId == null) {
    yield const [];
    return;
  }
  yield* ref.watch(noteStoreProvider).watchForProject(workspaceId, projectId);
});

/// Full note for the editor — live, so pulled edits show up in place.
final noteDetailProvider = StreamProvider.family<NoteDetail, String>((
  ref,
  noteId,
) {
  ref.watch(syncEngineProvider);
  return ref.watch(noteStoreProvider).watchDetail(noteId);
});

/// Why a note's editor has nothing to show (R-05, the OPH-392 task pattern).
enum NoteAbsence {
  /// The server has no such note for this person: deleted, never theirs, or
  /// not a note id at all.
  gone,

  /// The note is not on this device and the server gave no usable answer.
  unreachable,
}

/// The editor's answer while its note is absent from the replica.
///
/// [noteDetailProvider] drops a missing row, so a link to a note that is not
/// on the device — deleted since, mistyped, someone else's — waited on it
/// forever: a bare spinner with no app bar. Asked once: when the server still
/// has the note, null (the pull brings it and the spinner is the truth);
/// 400/403/404 is gone; anything else (no network, 5xx, 429) is unreachable,
/// which the screen offers to retry, so no answer ever means a spinner.
final noteAbsenceProvider = FutureProvider.autoDispose
    .family<NoteAbsence?, String>((ref, noteId) async {
      final store = ref.watch(noteStoreProvider);
      if (await store.detailOnce(noteId) != null) return null;
      try {
        await NotesApi(ref.watch(apiClientProvider)).get(noteId);
        return null;
      } on ApiException catch (error) {
        return switch (error.statusCode) {
          400 || 403 || 404 => NoteAbsence.gone,
          _ => NoteAbsence.unreachable,
        };
      }
    });

/// The parsed source-editor styling (round 19 #4). A junk or retired name
/// resolves to the default rather than to a broken editor — the `parseTaskTime`
/// rule, applied to a display preference.
final noteSourceStylingChoiceProvider = Provider<MdSyntaxStyling>((ref) {
  final raw = ref.watch(noteSourceStylingProvider);
  return MdSyntaxStyling.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => MdSyntaxStyling.markersOnly,
  );
});
