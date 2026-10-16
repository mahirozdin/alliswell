import 'dart:ui' show Color;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/db/database.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/tag_store.dart';

/// Mirrors the API's tag shape (apps/api routes/tags.js). Round 8 (OPH-165)
/// gave tags a real UI: the chip-input creates/assigns them, the manage sheet
/// renames/recolors/deletes.
class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.slug,
    required this.colorRgb,
  });

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    colorRgb: json['colorRgb'] as String,
  );

  final String id;
  final String name;
  final String slug;
  final String colorRgb;

  /// `#RRGGBB` → paintable color (the project-dot idiom — hex never shown).
  Color get color =>
      Color(0xFF000000 | int.parse(colorRgb.substring(1), radix: 16));
}

/// Tags by id — list rows resolve their chips from this (OPH-165, T4).
///
/// Every synced workspace's tags, not only the selected one's: in an
/// organisation a row on Home may come from any unit the person is in, and
/// its chips must resolve there too (EE-296). On one's own it is the one
/// workspace, as before.
final tagsByIdProvider = Provider<Map<String, Tag>>((ref) {
  final tags = ref.watch(listedTagsProvider).value ?? const <Tag>[];
  return {for (final tag in tags) tag.id: tag};
});

/// The tags behind [tagsByIdProvider].
final listedTagsProvider = StreamProvider<List<Tag>>((ref) {
  final workspaceIds = ref.watch(syncWorkspaceIdsProvider);
  if (workspaceIds.isEmpty) return Stream.value(const <Tag>[]);
  return _watchTags(ref.watch(databaseProvider), workspaceIds);
});

/// The tags of ONE workspace — what a task's own tag field offers and
/// creates in: a task opened from Home may live in a unit other than the one
/// selected, and a tag from another workspace cannot be put on it.
final workspaceTagsProvider = StreamProvider.family<List<Tag>, String>(
  (ref, workspaceId) => _watchTags(ref.watch(databaseProvider), [workspaceId]),
);

Stream<List<Tag>> _watchTags(AwDatabase db, List<String> workspaceIds) =>
    (db.select(db.tags)
          ..where((t) => t.workspaceId.isIn(workspaceIds))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              Tag(id: r.id, name: r.name, slug: r.slug, colorRgb: r.colorRgb),
          ],
        );

/// Local-first tag writes (create/rename/recolor/delete) — OPH-165.
final tagStoreProvider = Provider<TagStore>(
  (ref) =>
      TagStore(ref.watch(databaseProvider), onMutation: () => pokeSync(ref)),
);

/// Tags of the current workspace (sorted by name) — live from the local
/// replica (OPH-054).
final tagsProvider = StreamProvider<List<Tag>>((ref) async* {
  ref.watch(syncEngineProvider);
  final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
  if (workspaceId == null) {
    yield const [];
    return;
  }
  yield* _watchTags(ref.watch(databaseProvider), [workspaceId]);
});

/// Which tag Home is filtered by, or null (OPH-306).
///
/// **In memory on purpose, and that is the whole design.** Every other list
/// preference in the app persists — sort orders, view modes, calendar
/// visibility — because they describe how you like to look at things. A filter
/// does not: it hides work. Epic 17 wrote the rule after Home's selected
/// calendar day did exactly this, and §16 repeats it for the same reason — *a
/// filter you can no longer see must not keep filtering*. A tag filter restored
/// on a cold start would hide half somebody's day behind a control they never
/// touched in this session and have no reason to look for.
///
/// The surfaces that can SET it are named deliberately (DESIGN §22): the tag
/// chips on Home's task rows, in both the list and the board — the two places
/// the filter's own bar is visible in the same frame. Chips elsewhere (a
/// project's Tasks tab, Completed, the EE assignment screen) stay inert rather
/// than quietly filtering a list on a screen you are not on.
class TagFilter extends Notifier<String?> {
  @override
  String? build() => null;

  /// Tapping the tag you are already filtered by clears it — the calendar day's
  /// gesture, so one habit covers both.
  void toggle(String tagId) => state = state == tagId ? null : tagId;

  void clear() => state = null;

  /// Filter by [tagId] whatever was set before — the global search's tag
  /// result (OPH-374) is "show me this tag", never a toggle that could clear.
  void select(String tagId) => state = tagId;
}

final tagFilterProvider = NotifierProvider<TagFilter, String?>(TagFilter.new);
