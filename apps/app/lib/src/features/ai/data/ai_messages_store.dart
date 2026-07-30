import 'package:drift/drift.dart';

import '../../../sync/db/database.dart';

/// Device-local AI chat history (OPH-221) — the AlarmLog ring-buffer pattern.
/// Never synced, never pushed; swallows its own errors (a broken history must
/// never break the bubble).
class AiMessagesStore {
  AiMessagesStore(this._db);
  final AwDatabase _db;

  Future<void> add({
    required String workspaceId,
    required String role,
    required String content,
    String status = 'done',
    String? contextJson,
    String? requestId,
  }) async {
    try {
      await _db
          .into(_db.aiMessages)
          .insert(
            AiMessagesCompanion.insert(
              workspaceId: workspaceId,
              role: role,
              content: content,
              status: Value(status),
              contextJson: Value(contextJson),
              requestId: Value(requestId),
              createdAt: DateTime.now().toUtc(),
            ),
          );
      await _trim();
    } on Object {
      // Swallowed on purpose — history is a convenience, not a guarantee.
    }
  }

  Stream<List<AiMessage>> watchRecent(
    String workspaceId, {
    int limit = kAiMessageLimit,
  }) =>
      (_db.select(_db.aiMessages)
            ..where((m) => m.workspaceId.equals(workspaceId))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
            ..limit(limit))
          .watch();

  Future<void> clear(String workspaceId) => (_db.delete(
    _db.aiMessages,
  )..where((m) => m.workspaceId.equals(workspaceId))).go();

  Future<void> _trim() async {
    final keep =
        await (_db.select(_db.aiMessages)
              ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
              ..limit(kAiMessageLimit))
            .get();
    if (keep.length < kAiMessageLimit) return;
    final cutoff = keep.last.createdAt;
    await (_db.delete(
      _db.aiMessages,
    )..where((m) => m.createdAt.isSmallerThanValue(cutoff))).go();
  }
}
