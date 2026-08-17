import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/fold.dart';
import '../core/ulid.dart';
import 'db/database.dart';
import 'sync_api.dart';
import 'sync_applier.dart';

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
  });

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
      _pullTimer ??= Timer.periodic(pullInterval!, (_) => syncNow());
    }
    await syncNow();
  }

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

  /// Debounced push trigger — call after every optimistic local write.
  void notifyLocalWrite() {
    if (_stopped) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, syncNow);
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
  Future<bool> syncNow() async {
    // Being torn down (workspace switch / sign-out) is not a failure.
    if (_stopped) return true;
    if (_running) {
      // A round IS in flight; its own caller reports its outcome.
      _rerunWanted = true;
      return true;
    }
    _running = true;
    var converged = false;
    try {
      await _pushPending();
      await _pullAll();
      _consecutiveFailures = 0;
      converged = true;
    } catch (_) {
      // Offline or a server hiccup: retry the whole round with backoff. The
      // outbox is durable, so nothing is lost while we wait.
      _consecutiveFailures += 1;
      _scheduleRetry();
    } finally {
      _running = false;
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
    _retryTimer = Timer(
      syncBackoffDelay(_consecutiveFailures, cap: maxBackoff),
      syncNow,
    );
  }

  Future<SyncState> _ensureState() async {
    final existing = await (db.select(
      db.syncStates,
    )..where((s) => s.workspaceId.equals(workspaceId))).getSingleOrNull();
    if (existing != null) return existing;
    final state = SyncStatesCompanion.insert(
      workspaceId: workspaceId,
      clientId: newUlid(),
    );
    await db.into(db.syncStates).insertOnConflictUpdate(state);
    return (db.select(
      db.syncStates,
    )..where((s) => s.workspaceId.equals(workspaceId))).getSingle();
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
        results = (await api.push(
          clientId: state.clientId,
          workspaceId: workspaceId,
          baseRevision: state.lastRevision,
          mutations: [for (final row in rows) _toMutation(row)],
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

    // OPH-268: delete ONLY if this row has not been rewritten since it was
    // read for the push. Outbox coalescing can merge a newer body into a row
    // that is already in flight, and an unconditional delete would throw that
    // newer body away — the very failure mode this task exists to end.
    await (db.delete(db.pendingMutations)..where(
          (m) =>
              m.id.equals(row.id) & m.localUpdatedAt.equals(row.localUpdatedAt),
        ))
        .go();

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
      final state = await _ensureState();
      final page = await api.pull(
        workspaceId,
        sinceRevision: state.lastRevision,
        limit: pullPageSize,
      );
      if (page.changes.isNotEmpty || page.toRevision != state.lastRevision) {
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
