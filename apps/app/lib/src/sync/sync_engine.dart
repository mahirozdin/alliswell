import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/ulid.dart';
import 'db/database.dart';
import 'outbox.dart';
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
    this.conflictCopyNoteId,
  });

  final String entityType;
  final String entityId;
  final String operation;

  /// conflict | rejected | applied (applied only with discardedFields).
  final String status;
  final String? errorCode;
  final List<String> discardedFields;

  /// Set when a note-content conflict spawned a local "conflicted copy".
  final String? conflictCopyNoteId;
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
  Future<void> syncNow() async {
    if (_stopped) return;
    if (_running) {
      _rerunWanted = true;
      return;
    }
    _running = true;
    try {
      await _pushPending();
      await _pullAll();
      _consecutiveFailures = 0;
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
      await syncNow();
    }
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
  );

  /// The server answered for this mutation — the outbox row is done either
  /// way; conflicts/rejections additionally surface to the user (OPH-056).
  Future<void> _settleResult(PendingMutation row, SyncPushResult result) async {
    String? copyNoteId;
    if (result.status == 'conflict' &&
        result.errorCode == 'NOTE_CONTENT_CONFLICT') {
      copyNoteId = await _createNoteConflictCopy(row);
    }

    await (db.delete(
      db.pendingMutations,
    )..where((m) => m.id.equals(row.id))).go();

    final lostSomething =
        result.status != 'applied' || result.discardedFields.isNotEmpty;
    if (lostSomething && !result.replayed) {
      _conflicts.add(
        SyncConflict(
          entityType: row.entityType,
          entityId: row.entityId,
          operation: row.operation,
          status: result.status,
          errorCode: result.errorCode,
          discardedFields: result.discardedFields,
          conflictCopyNoteId: copyNoteId,
          at: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// BLUEPRINT §6.5 v1 policy: the server kept its version of the note
  /// content, so the local edit becomes a NEW note ("çakışan kopya") that
  /// syncs up as a create — nothing the user typed is ever lost. The
  /// following pull restores the server content into the original note.
  Future<String?> _createNoteConflictCopy(PendingMutation row) async {
    final local = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(row.entityId))).getSingleOrNull();
    if (local == null) return null;

    final copyId = newUlid();
    final patch = <String, dynamic>{
      'title': '${local.title} (çakışan kopya)',
      if (local.contentDelta != null)
        'contentDelta': jsonDecode(local.contentDelta!),
      if (local.contentMarkdown != null)
        'contentMarkdown': local.contentMarkdown,
      if (local.projectId != null) 'projectId': local.projectId,
    };
    await db.transaction(() async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: copyId,
              workspaceId: local.workspaceId,
              projectId: Value(local.projectId),
              title: patch['title'] as String,
              contentDelta: Value(local.contentDelta),
              contentMarkdown: Value(local.contentMarkdown),
              plainText: Value(local.plainText),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await enqueueMutation(
        db,
        workspaceId: workspaceId,
        entityType: 'note',
        entityId: copyId,
        operation: 'create',
        patch: patch,
      );
    });
    return copyId;
  }

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
