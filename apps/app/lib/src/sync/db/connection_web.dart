import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import 'flush_after_commit.dart';

/// Web: sqlite compiled to wasm, persisted via OPFS/IndexedDB when the
/// browser allows it (drift picks the best implementation and falls back to
/// in-memory otherwise). The two assets live in `web/` pinned to the resolved
/// package versions: `sqlite3.wasm` (sqlite3 3.4.0) and `drift_worker.js`
/// (drift 2.34.2) — bump them together with pubspec upgrades.
DatabaseConnection openAwConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: 'alliswell',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      final executor = result.resolvedExecutor;
      // N2: an IndexedDB-backed replica persists a transaction only when a
      // statement runs after it — see [FlushAfterCommit].
      return switch (result.chosenImplementation) {
        WasmStorageImplementation.sharedIndexedDb ||
        WasmStorageImplementation.unsafeIndexedDb => executor.interceptWith(
          FlushAfterCommit(executor),
        ),
        _ => executor,
      };
    }),
  );
}
