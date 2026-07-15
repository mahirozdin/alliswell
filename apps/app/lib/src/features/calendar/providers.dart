import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/external_event.dart';

export 'data/external_event.dart' show ExternalEvent;

/// The user's own calendar, from the replica (OPH-083). Read-only by
/// construction — the store has no write path.
final externalEventStoreProvider = Provider<ExternalEventStore>(
  (ref) => ExternalEventStore(ref.watch(databaseProvider)),
);

/// Every synced calendar event of the workspace. Empty when no calendar is
/// connected, which is exactly what the views should show in that case.
final externalEventsProvider = StreamProvider<List<ExternalEvent>>((
  ref,
) async* {
  ref.watch(syncEngineProvider); // keep background sync alive, like tasks do
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  yield* ref.watch(externalEventStoreProvider).watchAll(workspaces.first.id);
});
