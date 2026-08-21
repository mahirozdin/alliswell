import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/db/database.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';

/// What another unit shared with this one (EE-060 delivered it, EE-061 shows it).
///
/// Read from the REPLICA, not from the network — which is the whole point of
/// delivering a mirror row through sync rather than exposing a REST list. The
/// list works with no connection, because by then the rows are already here.
///
/// Scoped to the CURRENT workspace: a mirror belongs to the unit it was
/// delivered into, so switching units changes what is shared with you, exactly
/// as switching units changes everything else.
final sharedWithMeProvider = StreamProvider<List<SharedItem>>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return const Stream.empty();
  final db = ref.watch(databaseProvider);
  return (db.select(db.sharedItems)
        ..where((s) => s.workspaceId.equals(workspace.id))
        ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
      .watch();
});
