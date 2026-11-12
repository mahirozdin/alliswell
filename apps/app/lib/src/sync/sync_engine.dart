import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/fold.dart';
import '../core/http_timeouts.dart';
import '../core/kv/local_kv.dart';
import '../core/ulid.dart';
import 'db/database.dart';
import 'sync_api.dart';
import 'revocation.dart';
import 'sync_applier.dart';

/// Where an account switch leaves this install's sync client id
/// (signin-binds-discarded-client-id, OPH-447): `LocalDataGuard.claimFor`
/// writes it after the wipe that dropped `sync_states`, and the next engine to
/// create a state row takes it instead of minting a new one.
///
/// The id names the INSTALL to the server — the device registry's row and the
/// device a session family is bound to on sign-in — and the sign-in already
/// sent it before the switch was known. A new id here would leave the new
/// person's session bound to an id nothing lists, so removing the device
/// elsewhere could never sign it out. A person's own sign-out removes it
/// (`kUserBoundKvPrefixes`): only the switch carries it over.
const String kInstallClientIdKey = 'alliswell_install_client_id';

Future<String?> _storedInstallClientId() => localKv.get(kInstallClientIdKey);

/// A push outcome the user may need to know about (OPH-056): the server
/// refused or LWW-discarded a local write. `discardedFields` carries partial
/// losses on otherwise-applied mutations.
class SyncConflict {
  const SyncConflict({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.status,
    required this.at,
    this.errorCode,
    this.discardedFields = const [],
    this.conflictVersionId,
  });

  final String entityType;
  final String entityId;
  final String operation;

  /// conflict | rejected | applied (applied only with discardedFields).
  final String status;
  final String? errorCode;
  final List<String> discardedFields;

  /// OPH-268: where the server kept the body it refused. The note carries the
  /// same id, which is what raises its banner; this is the snackbar's cue that
  /// something needs the user's eyes — and its proof that nothing was lost.
  final String? conflictVersionId;
  final DateTime at;
}

/// Exponential backoff for failed push/pull rounds: 1s, 2s, 4s… capped.
Duration syncBackoffDelay(
  int failures, {
  Duration cap = const Duration(seconds: 60),
}) {
  final seconds = min(cap.inSeconds, 1 << min(failures - 1, 10));
  return Duration(seconds: max(1, seconds));
}

/// Local-first sync driver (OPH-055): drains the outbox in order, applies the
/// results, then pulls the workspace forward. One engine per (workspace,
/// database); the UI never talks to it directly — repositories poke
/// [notifyLocalWrite] after every optimistic write.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.api,
    required this.workspaceId,
    this.pushBatchSize = 100,
    this.pullPageSize = 200,
    this.debounce = const Duration(milliseconds: 250),
    this.pullInterval,
    this.maxBackoff = const Duration(seconds: 60),
    this.requestTimeout = kApiCallDeadline,
    Future<String?> Function()? installClientId,
  }) : _installClientId = installClientId ?? _storedInstallClientId,
       _zone = _zoneOutsideTransactions(db);

  /// The id an account switch carried over ([kInstallClientIdKey]), read only
  /// when the replica holds no state row to take it from.
  final Future<String?> Function() _installClientId;

  /// The zone the engine was made in, with every drift transaction of [db]
  /// stepped out of. Its rounds and every timer (debounce, retry, periodic
  /// pull) run here, never in a caller's: a round asked for from inside a
  /// transaction — a poke from a receipted alarm action (OPH-427), or an
  /// engine a provider first built during one — would otherwise query that
  /// transaction after it closed; on the remote executor of a release build
  /// the request never answers and the engine stays running for good.
  ///
  /// Not [Zone.root]: a widget test's fake clock is the zone the engine is
  /// made in, and a round outside it would never finish under that clock.
  final Zone _zone;

  /// The nearest zone at or above the current one in which [db] resolves to
  /// itself, i.e. no transaction of it is open there.
  static Zone _zoneOutsideTransactions(AwDatabase db) {
    var zone = Zone.current;
    while (zone.run(() => db.inTransactionZone)) {
      zone = zone.parent ?? Zone.root;
    }
    return zone;
  }

  final AwDatabase db;
  final SyncApi api;
  final String workspaceId;
  final int pushBatchSize;
  final int pullPageSize;
  final Duration debounce;

  /// Periodic re-pull while running (null = only on demand). OPH-057's socket
  /// signal will make this a fallback rather than the primary trigger.
  final Duration? pullInterval;
  final Duration maxBackoff;

  /// How long one push or pull may stay unanswered (OPH-427, #46/#48). The
  /// engine runs one round at a time, so a request that never answers would
  /// otherwise hold every later round — a poke, the periodic pull — behind it
  /// until the app restarts. Past it the round fails like an offline one and
  /// the backoff retries. A push that did land before its answer was lost is
  /// safe to resend: the server dedupes by (clientId, clientMutationId).
  /// Only the network calls are bounded, never a database transaction.
  final Duration requestTimeout;

  final _conflicts = StreamController<SyncConflict>.broadcast();
  Stream<SyncConflict> get conflicts => _conflicts.stream;

  Timer? _debounceTimer;
  Timer? _retryTimer;
  Timer? _pullTimer;
  bool _running = false;
  bool _rerunWanted = false;
  bool _stopped = false;
  int _consecutiveFailures = 0;

  /// Idempotent: makes sure the sync state row exists, then converges once
  /// and (optionally) keeps pulling on [pullInterval].
  Future<void> start() async {
    _stopped = false;
    await _ensureState();
    if (pullInterval != null) {
      _pullTimer ??= _zone.run(
        () => Timer.periodic(pullInterval!, (_) => syncNow()),
      );
    }
    await syncNow();
  }

  /// Whether [stop] (or [halt]) ran and no [start] re-armed it since —
  /// what sign-out leaves every engine in (OPH-390).
  bool get isStopped => _stopped;

  void stop() {
    _stopped = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _pullTimer?.cancel();
    _pullTimer = null;
  }

  void dispose() {
    stop();
    _conflicts.close();
  }

  /// [stop], then wait for a round already in flight to finish (OPH-355).
  ///
  /// Sign-out wipes the replica right after; a pull that was mid-flight would
  /// otherwise land its page on the empty database a moment later and leave
  /// the previous person's rows on the device.
  Future<void> halt() async {
    stop();
    while (_running) {
      await (_idle?.future ?? Future<void>.value());
    }
  }

  Completer<void>? _idle;

  /// Debounced push trigger — call after every optimistic local write.
  void notifyLocalWrite() {
    if (_stopped) return;
    _debounceTimer?.cancel();
    _debounceTimer = _zone.run(() => Timer(debounce, syncNow));
  }

  /// Runs one push+pull convergence round. Serialized: a call while a round
  /// is in flight queues exactly one follow-up round.
  ///
  /// Returns whether there is nothing to report: true when the round converged
  /// (or when there was nothing to do), false when it failed and a backoff
  /// retry is armed — the outbox is durable, so nothing is lost either way.
  /// Pull-to-refresh (OPH-171) is the only caller that reads this: a user who
  /// just asked for a refresh must be told when it did not happen (DESIGN §15
  /// R4). Every background caller keeps ignoring it.
  Future<bool> syncNow() => _zone.run(_syncRound);

  Future<bool> _syncRound() async {
    // Being torn down (workspace switch / sign-out) is not a failure.
    if (_stopped) return true;
    if (_running) {
      // A round IS in flight; its own caller reports its outcome.
      _rerunWanted = true;
      return true;
    }
    _running = true;
    final idle = _idle = Completer<void>();
    var converged = false;
    try {
      await _pushPending();
      await _pullAll();
      _consecutiveFailures = 0;
      converged = true;
    } on ApiException catch (e) {
      // EE-058 — the one failure that is not a hiccup. `AUTH_WORKSPACE_FORBIDDEN`
      // on sync means this workspace is no longer this person's, and no amount
      // of backing off will change that. Treated as offline (which it was
      // until now) it leaves a full replica of content they may no longer see
      // on the device, forever, while the engine retries a permanent
      // condition. Nothing else about the error path changes.
      if (e.code == kWorkspaceForbiddenCode) {
        await _revoke();
      } else {
        _consecutiveFailures += 1;
        _scheduleRetry();
      }
    } catch (_) {
      // Offline or a server hiccup: retry the whole round with backoff. The
      // outbox is durable, so nothing is lost while we wait.
      _consecutiveFailures += 1;
      _scheduleRetry();
    } finally {
      _running = false;
      idle.complete();
    }
    if (_rerunWanted && !_stopped) {
      _rerunWanted = false;
      return syncNow();
    }
    return converged;
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retryTimer?.cancel();
    _retryTimer = _zone.run(
      () => Timer(
        syncBackoffDelay(_consecutiveFailures, cap: maxBackoff),
        syncNow,
      ),
    );
  }

  /// Access to this workspace is gone (EE-058, ADR-0008 D2).
  ///
  /// Drop the replica, park what was unsent, and STOP — re-arming the timer
  /// here would be the same permanent-condition loop in a smaller shape.
  /// The engine is not restarted by anything short of a fresh one being built
  /// for a workspace this person actually has.
  Future<void> _revoke() async {
    _revokedParkedCount = await revokeWorkspaceReplica(db, workspaceId);
    _revoked = true;
    stop();
  }

  /// True once the server has told this engine the workspace is not ours.
  /// Read by the UI, which owes the person a sentence about it.
  bool get revoked => _revoked;
  bool _revoked = false;

  /// How many unsent mutations were parked when that happened. They are in
  /// `rejected_mutations`, not gone.
  int get revokedParkedCount => _revokedParkedCount;
  int _revokedParkedCount = 0;

  Future<SyncState> _ensureState() async {
    final existing = await (db.select(
      db.syncStates,
    )..where((s) => s.workspaceId.equals(workspaceId))).getSingleOrNull();
    if (existing != null) return existing;
    // One client id per DEVICE, not per workspace: the device registry and
    // "This device" in a note's history read it from the first row, and a
    // member syncs several workspaces at once. The server keys what it records
    // by (client, workspace), so sharing the id costs nothing there.
    final any = await (db.select(db.syncStates)..limit(1)).getSingleOrNull();
    final state = SyncStatesCompanion.insert(
      workspaceId: workspaceId,
      clientId: any?.clientId ?? await _carriedOverClientId() ?? newUlid(),
    );
    await db.into(db.syncStates).insertOnConflictUpdate(state);
    return (db.select(
      db.syncStates,
    )..where((s) => s.workspaceId.equals(workspaceId))).getSingle();
  }

  Future<String?> _carriedOverClientId() async {
    try {
      final id = await _installClientId();
      return id == null || id.isEmpty ? null : id;
    } on Object {
      return null;
    }
  }

  Future<void> _pushPending() async {
    while (true) {
      final state = await _ensureState();
      final rows =
          await (db.select(db.pendingMutations)
                ..where((m) => m.workspaceId.equals(workspaceId))
                ..orderBy([
                  (m) => OrderingTerm.asc(m.createdAt),
                  (m) => OrderingTerm.asc(m.id),
                ])
                ..limit(pushBatchSize))
              .get();
      if (rows.isEmpty) return;

      List<SyncPushResult> results;
      try {
        results = (await _bounded(
          api.push(
            clientId: state.clientId,
            workspaceId: workspaceId,
            baseRevision: state.lastRevision,
            mutations: [for (final row in rows) _toMutation(row)],
          ),
        )).results;
      } catch (_) {
        await _bumpAttempts(rows);
        rethrow;
      }

      final byId = {for (final r in results) r.clientMutationId: r};
      for (final row in rows) {
        final result = byId[row.id];
        if (result == null) continue; // defensive: keep for the next round
        await _settleResult(row, result);
      }
      if (rows.length < pushBatchSize) return;
    }
  }

  /// [requestTimeout] around one network call, failing as the offline error
  /// does so the round takes the ordinary backoff path. A late answer to the
  /// abandoned call is dropped: the revision was not advanced, so the next
  /// round asks for the same page again.
  Future<T> _bounded<T>(Future<T> call) => call.timeout(
    requestTimeout,
    onTimeout: () => throw const ApiException(
      'NETWORK_ERROR',
      'The AllisWell server did not answer in time',
    ),
  );

  Future<void> _bumpAttempts(List<PendingMutation> rows) async {
    for (final row in rows) {
      await (db.update(
        db.pendingMutations,
      )..where((m) => m.id.equals(row.id))).write(
        PendingMutationsCompanion(
          attempts: Value(row.attempts + 1),
          lastError: const Value('network'),
        ),
      );
    }
  }

  SyncMutation _toMutation(PendingMutation row) => SyncMutation(
    clientMutationId: row.id,
    entityType: row.entityType,
    entityId: row.entityId,
    operation: row.operation,
    patch: row.patchJson == null
        ? null
        : (jsonDecode(row.patchJson!) as Map<String, dynamic>),
    localUpdatedAt: row.localUpdatedAt,
    baseRevision: row.baseRevision,
  );

  /// The server answered for this mutation — the outbox row is done either
  /// way; conflicts/rejections additionally surface to the user (OPH-056).
  Future<void> _settleResult(PendingMutation row, SyncPushResult result) async {
    if (row.entityType == 'note') {
      await _settleNote(row, result);
    }

    // EE-051: a refusal is KEPT, not forgotten. Settling the outbox row is
    // what stops an old client looping on an answer it does not understand —
    // but settling used to mean deleting, and the person's typing went with
    // it while the replica quietly kept showing a write the server never
    // accepted. So: park the mutation, then put the row back the way the
    // server has it.
    if (result.status == 'rejected' && !result.replayed) {
      await _parkRejection(row, result);
    }

    // OPH-268: delete ONLY if this row has not been rewritten since it was
    // read for the push. Outbox coalescing can merge a newer body into a row
    // that is already in flight, and an unconditional delete would throw that
    // newer body away — the very failure mode this task exists to end.
    await (db.delete(db.pendingMutations)..where(
          (m) =>
              m.id.equals(row.id) & m.localUpdatedAt.equals(row.localUpdatedAt),
        ))
        .go();

    // OPH-362 (UI-AUDIT R2-1): accepted, and retired by the server's own
    // rules in the same transaction — a request draft that became a request
    // on arrival. The answer says so itself, so the replica drops the row now
    // instead of waiting for a pull that may never come (the courier that
    // pushed it stands down the moment its outbox is empty). Replays too: a
    // device that lost the first answer hears the same fact on its resend.
    final settled = result.rebase;
    if (result.applied && settled != null && !settled.present) {
      await applyRebase(
        db,
        entityType: settled.entityType,
        entityId: settled.entityId,
        present: false,
        workspaceId: workspaceId,
      );
    }

    final lostSomething = !result.applied || result.discardedFields.isNotEmpty;
    if (lostSomething && !result.replayed) {
      _conflicts.add(
        SyncConflict(
          entityType: row.entityType,
          entityId: row.entityId,
          operation: row.operation,
          status: result.status,
          errorCode: result.errorCode,
          discardedFields: result.discardedFields,
          conflictVersionId: result.conflictVersionId,
          at: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// EE-051 — the two halves of "refused, and nothing lost".
  ///
  /// KEEP: the refused patch goes into `rejected_mutations` with the server's
  /// code, so what the person wrote survives the refusal and something can
  /// offer it back to them.
  ///
  /// REBASE: the local row is put back the way the server actually has it.
  /// Without this the replica keeps an edit that was never accepted and
  /// incremental pull never corrects it — the server row did not change, so
  /// it appears in no future page. A refused CREATE is the loudest case: a
  /// task that exists on exactly one device, forever.
  ///
  /// A REPLAYED result is skipped: the server is repeating an answer this
  /// client was already given, and parking it twice would show the same
  /// refusal to the user again.
  Future<void> _parkRejection(
    PendingMutation row,
    SyncPushResult result,
  ) async {
    await db
        .into(db.rejectedMutations)
        .insert(
          RejectedMutationsCompanion.insert(
            id: row.id,
            workspaceId: workspaceId,
            entityType: row.entityType,
            entityId: row.entityId,
            operation: row.operation,
            patchJson: Value(row.patchJson),
            errorCode: Value(result.errorCode),
            rejectedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );

    final rebase = result.rebase;
    if (rebase == null) return;
    await applyRebase(
      db,
      entityType: rebase.entityType,
      entityId: rebase.entityId,
      present: rebase.present,
      data: rebase.data,
      workspaceId: workspaceId,
    );
  }

  /// What a note's own push result does to the replica (OPH-268).
  ///
  /// Three things, and the first is the one that stops fake conflicts: a
  /// successful push ADVANCES this note's local revision, so the next autosave
  /// carries a base the server recognises instead of the one from before our
  /// own write.
  Future<void> _settleNote(PendingMutation row, SyncPushResult result) async {
    if (result.applied && result.revision != null) {
      await (db.update(db.notes)..where((n) => n.id.equals(row.entityId)))
          .write(NotesCompanion(revision: Value(result.revision!)));
    }
    // The server merged our text with somebody else's: the merged body IS the
    // note now, so the replica takes it (an open editor reads the replica).
    if (result.merged && result.mergedMarkdown != null) {
      await (db.update(
        db.notes,
      )..where((n) => n.id.equals(row.entityId))).write(
        NotesCompanion(
          contentMarkdown: Value(result.mergedMarkdown),
          contentFormat: const Value('markdown'),
          plainText: Value(result.mergedMarkdown),
          bodyFold: Value(foldSearchText(result.mergedMarkdown!)),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
    // Refused: the server kept our body as a version. We record WHERE, and the
    // note raises a banner (OPH-269 draws it). No automatic sibling copy —
    // making that decision for the user was decision #8's mistake to undo.
    if (result.status == 'conflict' &&
        result.errorCode == 'NOTE_CONTENT_CONFLICT' &&
        result.conflictVersionId != null) {
      await (db.update(
        db.notes,
      )..where((n) => n.id.equals(row.entityId))).write(
        NotesCompanion(conflictVersionId: Value(result.conflictVersionId)),
      );
    }
  }

  // The automatic "çakışan kopya" note is GONE (OPH-268, decision #8).
  //
  // It was the v1 answer to a lock that could not merge: duplicate the note
  // and let the user sort it out. Three things made it wrong — it fired on
  // conflicts the server can now merge, it produced one copy per queued
  // autosave (finding #3), and the copy was born without `contentFormat`, so a
  // markdown note's copy came back as rich text. Splitting a note into two is
  // now a thing the USER chooses, from the banner, with the losing body safe
  // in the server's history either way.

  Future<void> _pullAll() async {
    while (true) {
      if (_stopped) return;
      final state = await _ensureState();
      final page = await _bounded(
        api.pull(
          workspaceId,
          sinceRevision: state.lastRevision,
          limit: pullPageSize,
        ),
      );
      // Stopped while the request was out: sign-out gives up waiting after a
      // bound and wipes the replica, and somebody else may already be signed
      // in. A page answered after that belongs to nobody on this device — it
      // is dropped, never applied (E35 G-A review r1). The revision is not
      // advanced, so a running engine would simply pull it again.
      if (_stopped) return;
      // OPH-394: the first pull is applied even when it brings nothing — an
      // empty workspace at revision 0 otherwise never stamps `lastPulledAt`,
      // and Home could not tell "nothing pulled yet" from "pulled: empty".
      if (page.changes.isNotEmpty ||
          page.toRevision != state.lastRevision ||
          state.lastPulledAt == null) {
        await applyPulledChanges(
          db,
          workspaceId: workspaceId,
          changes: page.changes,
          toRevision: page.toRevision,
        );
      }
      if (!page.hasMore) return;
    }
  }

  @visibleForTesting
  int get consecutiveFailures => _consecutiveFailures;
}
