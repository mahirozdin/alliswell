import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/kv/local_kv.dart';
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

/// Every [SyncEngine] alive right now (OPH-390), kept by the engines
/// themselves: one is added when [syncEngineForProvider] builds it and taken
/// out when that provider lets it go.
///
/// It exists for sign-out. The engines hang off the session
/// (`syncEnginesProvider` → workspaces → `authControllerProvider`), so the
/// controller cannot read them through the graph — Riverpod reports that as a
/// dependency loop and the sign-out never ran (E-01). This set depends on
/// nothing, so the controller can stop every engine without depending on the
/// providers that depend on it.
final runningSyncEnginesProvider = Provider<Set<SyncEngine>>(
  (_) => <SyncEngine>{},
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

/// This device's sync client id (OPH-269): the engine stamps it on every push,
/// so a version row carrying it was written HERE. That is what lets the history
/// say "This device" instead of showing a ULID nobody can read.
///
/// A STREAM since OPH-309, because a fresh install has no `sync_states` row
/// until the engine's first round — and the device registry is waiting for
/// exactly that id. A one-shot read answered `null` and stayed `null`.
///
/// One id per DEVICE: an engine creating the row for another workspace reuses
/// the id an earlier row already holds (`SyncEngine._ensureState`), so the
/// first row answers for all of them.
final syncClientIdProvider = StreamProvider<String?>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.syncStates)
      .watch()
      .map((rows) => rows.isEmpty ? null : rows.first.clientId);
});

/// The workspaces this device keeps in sync.
///
/// A person on their own: the current workspace, as ever. A member of an
/// organisation: EVERY one of its workspaces they are in — their Home gathers
/// their work from all of them, and a list read from a replica that stopped
/// pulling the moment another unit was selected is a list that silently lies
/// (a request assigned to somebody reached their device only once they
/// happened to open that unit).
final syncWorkspaceIdsProvider = Provider<List<String>>((ref) {
  final shared = ref.watch(sharedWorkspacesProvider);
  if (shared.isNotEmpty) return [for (final w in shared) w.id];
  final current = ref.watch(currentWorkspaceProvider).value?.id;
  return current == null ? const [] : [current];
});

/// One engine per synced workspace (and per database). The one on screen
/// pulls on the usual cadence; the others lean on the socket — every one of
/// the person's workspaces sends its `sync:changed` to this device — and pull
/// on a slower fallback. Recreated when the selection moves, which costs one
/// immediate round.
final syncEngineForProvider = Provider.autoDispose.family<SyncEngine, String>((
  ref,
  workspaceId,
) {
  final onScreen =
      ref.watch(currentWorkspaceProvider.select((w) => w.value?.id)) ==
      workspaceId;
  final cadence = ref.watch(syncPullIntervalProvider);
  final db = ref.watch(databaseProvider);
  final engine = SyncEngine(
    db: db,
    api: ref.watch(syncApiProvider),
    workspaceId: workspaceId,
    pullInterval: cadence == null || onScreen ? cadence : cadence * 5,
    debounce: ref.watch(syncDebounceProvider),
  );
  // Read, not watched: what it decides happens once, before the first round,
  // and a rename of the workspace must not rebuild its engine.
  final repull = ref
      .read(sharedWorkspacesProvider)
      .any((w) => w.id == workspaceId && w.reportsOwnership);
  final running = ref.read(runningSyncEnginesProvider)..add(engine);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    running.remove(engine);
    engine.dispose();
  });
  // No session, no engine (OPH-390). A screen still holding the engines when
  // the session ends — the shell covered by Settings — rebuilds this one as
  // the workspace leaves; started, it wrote its state row into the replica
  // the sign-out had just wiped and pulled with no token. It stays stopped
  // until a session builds it again.
  if (ref.watch(currentUserIdProvider) == null) {
    engine.stop();
    return engine;
  }
  unawaited(() async {
    if (repull) await repullOnceForCreatedBy(db, workspaceId);
    // `start` re-arms a stopped engine, so it must not run after disposal.
    if (!disposed) await engine.start();
  }());
  return engine;
});

/// Where [repullOnceForCreatedBy] marks a workspace as done.
const kCreatedByRepullPrefix = 'alliswell_created_by_repull::';

/// EE-296 — pull one of an organisation's workspaces once more, from its
/// beginning.
///
/// Rows pulled before the replica had `tasks.created_by` (v37) carry none,
/// and the "made by me" half of a member's Home reads it: without this, a task
/// they made and nobody took would drop off their Home the day they upgraded.
/// Once per workspace — the marker lives with the device's other small
/// facts — and the caller asks only for a workspace whose server sends the
/// field ([WorkspaceSummary.reportsOwnership]): against an older one the
/// marker would be spent on rows that still lack it.
///
/// Resetting the cursor IS the whole mechanism: the next round pages through
/// everything from revision 0 exactly as a first pull does, and an
/// interrupted one resumes from wherever its last applied page left it.
Future<void> repullOnceForCreatedBy(AwDatabase db, String workspaceId) async {
  final key = '$kCreatedByRepullPrefix$workspaceId';
  if (await localKv.get(key) != null) return;
  await (db.update(db.syncStates)
        ..where((s) => s.workspaceId.equals(workspaceId)))
      .write(const SyncStatesCompanion(lastRevision: Value(0)));
  await localKv.set(key, '1');
}

/// Every running engine, by workspace. Anything that watches it keeps all of
/// them alive (the shell does, for as long as the app is open).
///
/// A workspace that LEAVES the list gets one last round before its engine
/// goes: when access is really gone the server answers that with the refusal
/// that drops the replica and parks what was unsent (EE-058) — the same path
/// every refused pull takes. Offline, or still reachable, it changes nothing.
final syncEnginesProvider = Provider<Map<String, SyncEngine>>((ref) {
  ref.listen<List<String>>(syncWorkspaceIdsProvider, (previous, next) {
    if (previous == null) return;
    // Signed out, every workspace leaves at once and none of them is a lost
    // access: the sign-out stopped the engines and wiped the replica, and a
    // probe would write its state row into it again (OPH-390).
    if (ref.read(currentUserIdProvider) == null) return;
    for (final gone in previous.where((id) => !next.contains(id))) {
      final probe = SyncEngine(
        db: ref.read(databaseProvider),
        api: ref.read(syncApiProvider),
        workspaceId: gone,
      );
      unawaited(probe.syncNow().whenComplete(probe.dispose));
    }
  });
  final ids = ref.watch(syncWorkspaceIdsProvider);
  return {for (final id in ids) id: ref.watch(syncEngineForProvider(id))};
});

/// The engine of the workspace on screen; null while signed out. What a
/// screen that just wrote over REST asks to catch up with the result — that
/// workspace is the one the write went to.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  return ref.watch(syncEngineForProvider(workspace.id));
});

/// Tells every running engine that the replica changed. Each one drains only
/// its own workspace's outbox, so the engine whose workspace the write landed
/// in pushes it and the others find nothing to do. A write goes out even when
/// its workspace is not the one on screen — a task finished on Home that lives
/// in another unit.
void pokeSync(Ref ref) {
  for (final engine in ref.read(syncEnginesProvider).values) {
    engine.notifyLocalWrite();
  }
}

/// Server-refused or LWW-trimmed local writes, surfaced app-wide (OPH-056) —
/// from every engine, since a refusal can come back for any synced workspace.
final syncConflictsProvider = StreamProvider<SyncConflict>((ref) {
  final engines = ref.watch(syncEnginesProvider).values.toList();
  if (engines.isEmpty) return const Stream.empty();
  if (engines.length == 1) return engines.single.conflicts;
  final merged = StreamController<SyncConflict>();
  final subscriptions = [
    for (final engine in engines) engine.conflicts.listen(merged.add),
  ];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    merged.close();
  });
  return merged.stream;
});

/// How sockets get built — widget tests override with `null` (no sockets, no
/// reconnect timers in the fake-async zone).
final syncSocketFactoryProvider = Provider<SyncSocketFactory?>(
  (_) => defaultSyncSocketFactory,
);

/// The live `sync:changed` listener (OPH-057): one socket per signed-in
/// session, rebuilt when the session (and thus the access token) rotates.
/// An event pulls the engine of the workspace it names at once; each engine's
/// periodic pull stays as the fallback for missed sockets.
final syncSocketProvider = Provider<SyncSocketHandle?>((ref) {
  final factory = ref.watch(syncSocketFactoryProvider);
  final syncing = ref.watch(syncEnginesProvider.select((e) => e.isNotEmpty));
  final session = ref.watch(authControllerProvider).value;
  if (factory == null || !syncing || session == null) return null;

  final handle = factory(
    baseUrl: ref.watch(apiClientProvider).options.baseUrl,
    token: session.tokens.accessToken,
    onSyncChanged: (payload) {
      for (final engine in ref.read(syncEnginesProvider).values) {
        if (syncChangedMatches(payload, engine.workspaceId)) {
          unawaited(engine.syncNow());
        }
      }
    },
  );
  ref.onDispose(handle.close);
  return handle;
});
