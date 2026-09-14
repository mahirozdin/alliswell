import 'dart:ui' show Color;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
final tagsByIdProvider = Provider<Map<String, Tag>>((ref) {
  final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
  return {for (final tag in tags) tag.id: tag};
});

/// Local-first tag writes (create/rename/recolor/delete) — OPH-165.
final tagStoreProvider = Provider<TagStore>(
  (ref) => TagStore(
    ref.watch(databaseProvider),
    onMutation: () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);

/// Tags of the current workspace (sorted by name) — live from the local
/// replica (OPH-054).
final tagsProvider = StreamProvider<List<Tag>>((ref) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  final db = ref.watch(databaseProvider);
  yield* (db.select(db.tags)
        ..where((t) => t.workspaceId.equals(workspaces.first.id))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            Tag(id: r.id, name: r.name, slug: r.slug, colorRgb: r.colorRgb),
        ],
      );
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
}

final tagFilterProvider = NotifierProvider<TagFilter, String?>(TagFilter.new);
