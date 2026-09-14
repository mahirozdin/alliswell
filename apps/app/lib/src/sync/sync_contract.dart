/// The push contract, as the client sees it (OPH-300).
///
/// The server's field tables decide which keys a mutation may carry, and it
/// refuses the WHOLE mutation on the first key it does not know. That rule was
/// never visible from this side, so the two halves drifted: the app added
/// `fromTaskId` to its `task_series` patch, the server's table had four keys,
/// and every repeat the app started was refused for six weeks while 2394 tests
/// stayed green (OPH-299).
///
/// The generated half of this pair — [kAwSyncFields], re-exported below — comes
/// from `SYNC_ENTITY_FIELDS` in `apps/api/src/routes/sync.js` via
/// `scripts/sync/fields.mjs`, and `npm run check:sync-fields` fails the build
/// when the two drift again.
library;

import 'sync_fields.g.dart';

// Re-exported so a caller needs one import, not two — and so the generated
// file is never imported directly, which keeps its name an implementation
// detail of this contract rather than a dependency spread across the app.
export 'sync_fields.g.dart';

/// One entity's accepted keys, and the two subsets that are operation-bound.
class AwSyncEntityFields {
  const AwSyncEntityFields({
    required this.all,
    required this.createOnly,
    required this.updateOnly,
  });

  /// Every key the server will accept, for any operation.
  final Set<String> all;

  /// Keys the server accepts ONLY on `create` (e.g. a checklist item's task).
  final Set<String> createOnly;

  /// Keys the server accepts ONLY on `update` (e.g. a reorder's `orderedIds`).
  final Set<String> updateOnly;
}

/// Why the server would refuse this patch, or null when it would take it.
///
/// Deliberately a *message* rather than a bool: the whole point is that
/// `SYNC_UNKNOWN_FIELD` arriving from production tells you nothing about which
/// key was wrong. Failing here says the key, the entity and the operation.
///
/// This checks the SHAPE of the agreement — which keys, on which operation —
/// and not the values. Value rules (`ulid`, `str(500)`, enum membership) stay
/// on the server, where they can refuse a hostile client too; duplicating them
/// here would be a second source of truth pretending to be a safety net.
String? awSyncPatchProblem(
  String entityType,
  String operation, [
  Map<String, dynamic>? patch,
]) {
  // A delete carries no patch, and the server skips field validation for it.
  if (patch == null || operation == 'delete') return null;

  // The EE overlay registers its entities at runtime
  // (`app.ee.registerSyncEntity`), so the generated contract cannot list them.
  // "Not mine to check" must not read the same as "nobody accepts this".
  if (entityType.startsWith('ee_')) return null;

  final spec = kAwSyncFields[entityType];
  if (spec == null) {
    return 'sync contract: no entity type "$entityType" — the server would '
        'answer SYNC_UNSUPPORTED_ENTITY. Register it in SYNC_ENTITY_FIELDS '
        '(apps/api/src/routes/sync.js) and regenerate, or use the ee_ prefix.';
  }

  for (final key in patch.keys) {
    if (!spec.all.contains(key)) {
      return 'sync contract: "$entityType" has no field "$key" — the server '
          'would answer SYNC_UNKNOWN_FIELD and drop the WHOLE mutation. '
          'Accepted: ${(spec.all.toList()..sort()).join(', ')}.';
    }
    if (operation != 'create' && spec.createOnly.contains(key)) {
      return 'sync contract: "$entityType.$key" is create-only — the server '
          'would refuse it on a $operation.';
    }
    if (operation != 'update' && spec.updateOnly.contains(key)) {
      return 'sync contract: "$entityType.$key" is update-only — the server '
          'would refuse it on a $operation.';
    }
  }
  return null;
}
