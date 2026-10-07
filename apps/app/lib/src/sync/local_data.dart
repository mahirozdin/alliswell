import '../core/kv/local_kv.dart';
import '../features/ai/data/ai_action_reporter.dart';
import '../features/ai/providers.dart';
import '../features/ee/approvals_providers.dart';
import '../features/ee/providers.dart';
import '../features/workspaces/workspaces.dart';
import 'db/database.dart';
import 'providers.dart' show kCreatedByRepullPrefix;
import 'revocation.dart';

/// Whose replica this device holds (OPH-355, UI-AUDIT #3).
///
/// ── THE REPLICA BELONGS TO ONE PERSON ─────────────────────────────────────
///
/// One browser, one shared factory-floor tablet: people sign out and the next
/// one signs in. Before this the replica outlived the sign-out — the requests,
/// their internal notes and the first person's notifications stayed readable
/// in IndexedDB, and the second person's centre showed them. So:
///
///   • sign-out WIPES the replica and the person's small facts (after the
///     sign-out screen has asked about unsent changes — [unsentChangeCount]);
///   • sign-in into a replica owned by SOMEBODY ELSE wipes it before the
///     session is exposed, so before any screen or engine reads it — the
///     sign-out may have been skipped (a forced one, a crash, an older build).
const String kReplicaOwnerKey = 'alliswell_replica_owner';

/// The LocalKv keys that belong to a PERSON rather than to the device — the
/// one list sign-out reads. Everything else (server address, language, theme,
/// date format, widget and quick-access preferences) is the device's and
/// stays. Prefixes: a key matches when it starts with one of these.
const List<String> kUserBoundKvPrefixes = [
  kWorkspacesCachePrefix,
  kSelectedWorkspacePrefix,
  kAiStatusCachePrefix,
  kAiConsentPrefix,
  kAiPendingActionsKey,
  kEeStatusCachePrefix,
  kEePermissionsCachePrefix,
  kEeApprovalsDoorCachePrefix,
  kCreatedByRepullPrefix,
  kReplicaOwnerKey,
];

/// Writes that exist on this device and nowhere else: the outbox, plus what
/// the server refused and is kept for the person to decide on. What sign-out
/// would destroy, and so what it asks about first.
Future<int> unsentChangeCount(AwDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM pending_mutations) + '
        '(SELECT COUNT(*) FROM rejected_mutations) AS n',
        readsFrom: {db.pendingMutations, db.rejectedMutations},
      )
      .getSingle();
  return row.read<int>('n');
}

/// Empties the replica IN PLACE, keeping only [kDeviceLocalTables] (the
/// device's own content-free diagnostic logs).
///
/// In place rather than closing and deleting the file: the database is open
/// on more than one connection (the home-screen widget's isolate holds its
/// own on native), and a file unlinked under an open connection lives on as
/// that connection's inode — the wipe would be a rename. `secure_delete`
/// overwrites what the deletes free and VACUUM rebuilds the file without
/// those pages, so the bytes are gone from the storage too (on web the
/// IndexedDB blocks hold the same file), not merely unreachable.
Future<void> wipeReplica(AwDatabase db) async {
  await _quietly(() => db.customStatement('PRAGMA secure_delete = ON'));
  await db.transaction(() async {
    for (final table in db.allTables) {
      if (kDeviceLocalTables.contains(table.actualTableName)) continue;
      await db.delete(table).go();
    }
  });
  await _quietly(() => db.customStatement('VACUUM'));
  await _quietly(() => db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)'));
  await _quietly(() => db.customStatement('PRAGMA secure_delete = OFF'));
}

/// The sign-out and sign-in halves of "the replica is one person's".
class LocalDataGuard {
  LocalDataGuard({required this._database, LocalKv? kv, this._clearAlerts})
    : _kv = kv ?? localKv;

  final AwDatabase Function() _database;
  final LocalKv _kv;
  final Future<void> Function()? _clearAlerts;

  /// Everything a person leaves on the device, gone. Best effort per part and
  /// never throws: a sign-out must always complete, and one part failing
  /// (a blocked browser store) must not keep the others. Returns whether the
  /// replica itself was emptied.
  Future<bool> wipe() async {
    final wiped = await _quietly(() => wipeReplica(_database()));
    final clearAlerts = _clearAlerts;
    if (clearAlerts != null) await _quietly(clearAlerts);
    await _kv.removeWhere(
      (key) => kUserBoundKvPrefixes.any((prefix) => key.startsWith(prefix)),
    );
    return wiped;
  }

  /// Called with the person a session is about to start for, BEFORE anything
  /// reads the replica as theirs.
  ///
  /// [restored] — the session came back from storage at app start. With no
  /// recorded owner (a build from before this) that session's person is the
  /// one the replica was filled for, so they adopt it instead of paying a full
  /// re-pull. A fresh sign-in with no recorded owner cannot know whose rows
  /// these are, and wipes.
  Future<void> claimFor(String userId, {bool restored = false}) async {
    final owner = await _kv.get(kReplicaOwnerKey);
    if (owner == userId) return;
    if (owner == null && restored) {
      await _kv.set(kReplicaOwnerKey, userId);
      return;
    }
    // Owner recorded only once the rows are really gone: a failed wipe is
    // retried by the next sign-in rather than blessed by this one.
    if (await wipe()) await _kv.set(kReplicaOwnerKey, userId);
  }
}

Future<bool> _quietly(Future<void> Function() step) async {
  try {
    await step();
    return true;
  } on Object {
    // Best effort: see [LocalDataGuard.wipe].
    return false;
  }
}
