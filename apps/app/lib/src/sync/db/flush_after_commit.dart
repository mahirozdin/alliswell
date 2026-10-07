import 'package:drift/drift.dart';

/// Makes a committed transaction durable on the web replica (N2, UI-AUDIT
/// retest — an offline request draft lost on reload).
///
/// ── WHY A COMMIT WAS NOT ENOUGH ──────────────────────────────────────────
///
/// On the web the replica is sqlite on an IndexedDB file system that writes
/// back only when it is told to: drift's wasm delegate flushes after a
/// statement that runs OUTSIDE a transaction. A transaction's own `COMMIT`
/// runs while the delegate still counts itself inside one, so the commit is
/// not flushed — it sits in the worker's memory until some later
/// non-transactional write happens to flush it. Every local write here is a
/// transaction (the optimistic row and its outbox entry together), so a
/// write made offline, with nothing after it, never reached IndexedDB: the
/// screen showed it, a reload lost it, and nothing had queued a push.
/// Measured on the retest stack: the draft's bytes never appeared in the
/// `alliswell/blocks` store, while the pull cursors written outside
/// transactions did.
///
/// So after every top-level commit this runs one statement on the database
/// itself — outside any transaction — which is the delegate's flush point.
/// Nested transactions (savepoints) are left alone: their parent's commit is
/// the one that has to land, and a statement on the database while the parent
/// holds it would wait for the parent forever.
class FlushAfterCommit extends QueryInterceptor {
  FlushAfterCommit(this._root);

  /// The executor this interceptor wraps — where the flushing statement runs.
  final QueryExecutor _root;

  final Expando<bool> _topLevel = Expando('topLevelTransaction');

  /// What runs after a top-level commit. A no-op for sqlite, a flush for the
  /// wasm delegate.
  static const String flushStatement = 'SELECT 1';

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final transaction = parent.beginTransaction();
    if (identical(parent, _root)) _topLevel[transaction] = true;
    return transaction;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    if (_topLevel[inner] == true) {
      await _root.runCustom(flushStatement, const []);
    }
  }
}
