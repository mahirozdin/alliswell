import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/providers.dart';
import '../features/workspaces/workspaces.dart';
import 'db/connection.dart';
import 'db/database.dart';
import 'sync_api.dart';
import 'sync_engine.dart';
import 'sync_socket.dart';

/// The local replica. Widget tests override this with an in-memory database
/// (the default connection needs platform channels).
final databaseProvider = Provider<AwDatabase>((ref) {
  final db = AwDatabase(openAwConnection());
  ref.onDispose(db.close);
  return db;
});

final syncApiProvider = Provider<SyncApi>(
  (ref) => SyncApi(ref.watch(apiClientProvider)),
);

/// Periodic re-pull cadence (the interim update channel until OPH-057's
/// socket lands). Widget tests override this with `null` so no timer outlives
/// a test body.
final syncPullIntervalProvider = Provider<Duration?>(
  (_) => const Duration(seconds: 60),
);

/// Debounce between an optimistic local write and the push round.
final syncDebounceProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 250),
);

/// One engine per signed-in workspace; null while signed out. Anything that
/// watches it keeps background sync alive.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  final engine = SyncEngine(
    db: ref.watch(databaseProvider),
    api: ref.watch(syncApiProvider),
    workspaceId: workspace.id,
    pullInterval: ref.watch(syncPullIntervalProvider),
    debounce: ref.watch(syncDebounceProvider),
  );
  ref.onDispose(engine.dispose);
  unawaited(engine.start());
  return engine;
});

/// Server-refused or LWW-trimmed local writes, surfaced app-wide (OPH-056).
final syncConflictsProvider = StreamProvider<SyncConflict>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine?.conflicts ?? const Stream.empty();
});

/// How sockets get built — widget tests override with `null` (no sockets, no
/// reconnect timers in the fake-async zone).
final syncSocketFactoryProvider = Provider<SyncSocketFactory?>(
  (_) => defaultSyncSocketFactory,
);

/// The live `sync:changed` listener (OPH-057): one socket per signed-in
/// session, rebuilt when the session (and thus the access token) rotates.
/// A matching event pulls immediately; the engine's periodic pull stays as
/// the fallback for missed sockets.
final syncSocketProvider = Provider<SyncSocketHandle?>((ref) {
  final factory = ref.watch(syncSocketFactoryProvider);
  final engine = ref.watch(syncEngineProvider);
  final session = ref.watch(authControllerProvider).value;
  if (factory == null || engine == null || session == null) return null;

  final handle = factory(
    baseUrl: ref.watch(apiClientProvider).options.baseUrl,
    token: session.tokens.accessToken,
    onSyncChanged: (payload) {
      if (syncChangedMatches(payload, engine.workspaceId)) {
        unawaited(engine.syncNow());
      }
    },
  );
  ref.onDispose(handle.close);
  return handle;
});
