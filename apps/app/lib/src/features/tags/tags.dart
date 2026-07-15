import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';

/// Mirrors the API's tag shape (apps/api routes/tags.js). Management UI is a
/// later task — v1 needs tags for task labeling only.
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
}

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
