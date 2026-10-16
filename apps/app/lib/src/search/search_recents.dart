/// What the global search palette shows before anything is typed (OPH-374,
/// ADR-0055): the tasks, projects, notes, tags and files this person opened
/// last, on this device.
///
/// Modelled on `features/notes/data/external_recents.dart` — pure parse /
/// push / encode, most recent first, deduplicated, capped, tolerant of junk —
/// so the rules are table-tested without a widget in sight.
///
/// Device-local and PERSON-bound: the key is in `kUserBoundKvPrefixes`, so
/// sign-out wipes it. What somebody opened is theirs, and the next person on
/// a shared tablet must not see it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/kv/local_kv.dart';
import '../features/workspaces/workspaces.dart' show currentUserIdProvider;
import '../sync/providers.dart';
import 'global_search.dart';

const String kSearchRecentsKey = 'search.recent';

/// Enough for "what I was just in", short enough to scan without searching.
const int kSearchRecentsLimit = 8;

class SearchRecent {
  const SearchRecent(this.kind, this.id);

  final GlobalSearchKind kind;
  final String id;

  Map<String, String> toJson() => {'kind': kind.name, 'id': id};

  static SearchRecent? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = GlobalSearchKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final id = json['id'];
    if (kind == null || id is! String || id.isEmpty) return null;
    return SearchRecent(kind, id);
  }

  @override
  bool operator ==(Object other) =>
      other is SearchRecent && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// The stored list, dropping whatever does not parse — losing one row beats
/// losing the list.
List<SearchRecent> parseSearchRecents(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final out = <SearchRecent>[];
  for (final entry in decoded) {
    final recent = SearchRecent.fromJson(entry);
    if (recent == null || out.contains(recent)) continue;
    out.add(recent);
    if (out.length == kSearchRecentsLimit) break;
  }
  return out;
}

/// Most recent first, deduplicated by kind + id, capped.
List<SearchRecent> pushSearchRecent(
  List<SearchRecent> recents,
  SearchRecent recent,
) {
  final out = [recent, ...recents.where((r) => r != recent)];
  return out.length <= kSearchRecentsLimit
      ? out
      : out.sublist(0, kSearchRecentsLimit);
}

String encodeSearchRecents(List<SearchRecent> recents) =>
    jsonEncode([for (final r in recents) r.toJson()]);

/// The entity an app address shows, or null when it shows none.
///
/// Recents come from ROUTE VISITS — a task opened from Home, a note from the
/// Notes list, a project from Quick Access — not only from the palette: the
/// thing somebody wants back is the thing they were just in, wherever they
/// came from. Tags and files have no address; the palette records those.
SearchRecent? recentFromLocation(String path) {
  final segments = Uri.parse(path).pathSegments;
  if (segments.length != 2) return null;
  final id = segments[1];
  if (id.isEmpty) return null;
  switch (segments[0]) {
    case 'tasks':
      return SearchRecent(GlobalSearchKind.task, id);
    case 'projects':
      return SearchRecent(GlobalSearchKind.project, id);
    case 'notes':
      const notNotes = {'new', 'import', 'file'};
      return notNotes.contains(id)
          ? null
          : SearchRecent(GlobalSearchKind.note, id);
    case 'edit-note':
      return SearchRecent(GlobalSearchKind.note, id);
  }
  return null;
}

class SearchRecents extends Notifier<List<SearchRecent>> {
  @override
  List<SearchRecent> build() {
    // Rebuilt for every person: sign-out wipes the stored list, and the one
    // held in memory must not carry over to whoever signs in next.
    _hydrated = false;
    if (ref.watch(currentUserIdProvider) == null) return const [];
    unawaited(_hydrate());
    return const [];
  }

  bool _hydrated = false;

  Future<void> _hydrate() async {
    final parsed = parseSearchRecents(await localKv.get(kSearchRecentsKey));
    if (_hydrated) {
      // A visit recorded before the stored list arrived goes on top of it.
      var merged = parsed;
      for (final recent in state.reversed) {
        merged = pushSearchRecent(merged, recent);
      }
      state = merged;
    } else if (parsed.isNotEmpty) {
      state = parsed;
    }
    _hydrated = true;
  }

  Future<void> record(SearchRecent recent) async {
    if (state.isNotEmpty && state.first == recent) return;
    _hydrated = true;
    state = pushSearchRecent(state, recent);
    await localKv.set(kSearchRecentsKey, encodeSearchRecents(state));
  }
}

final searchRecentsProvider =
    NotifierProvider<SearchRecents, List<SearchRecent>>(SearchRecents.new);

/// The recents as palette rows, read from the replica. A row that is gone (a
/// deleted task, another person's workspace after a switch) is dropped
/// silently — a recents list of dead rows is worse than a short one.
final recentSearchItemsProvider =
    FutureProvider.autoDispose<List<GlobalSearchItem>>((ref) async {
      final recents = ref.watch(searchRecentsProvider);
      if (recents.isEmpty) return const [];
      final db = ref.watch(databaseProvider);
      final resolved = <SearchRecent, GlobalSearchItem>{};
      for (final kind in GlobalSearchKind.values) {
        final ids = [
          for (final r in recents)
            if (r.kind == kind) r.id,
        ];
        for (final item in await resolveGlobalSearchItems(db, kind, ids)) {
          resolved[SearchRecent(kind, item.id)] = item;
        }
      }
      return [
        for (final r in recents)
          if (resolved[r] != null) resolved[r]!,
      ];
    });
