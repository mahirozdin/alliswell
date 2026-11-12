import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/db/flush_after_commit.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what reaches the database itself, outside any transaction — the
/// statements after which drift's wasm delegate flushes to IndexedDB.
class _RootLog extends QueryInterceptor {
  final outside = <String>[];
  var inTransaction = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    inTransaction += 1;
    return parent.beginTransaction();
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    inTransaction -= 1;
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await inner.rollback();
    inTransaction -= 1;
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (inTransaction == 0) outside.add(statement);
    return executor.runCustom(statement, args);
  }
}

/// N2 (UI-AUDIT retest): an offline request draft was gone after a reload,
/// because the web replica writes a transaction back to IndexedDB only when
/// a statement runs after it. Every local write is a transaction — the row
/// and its outbox entry together — so the last one before a reload was lost.
void main() {
  group('a plain executor', () {
    late _RootLog log;
    late AwDatabase db;

    setUp(() {
      log = _RootLog();
      final root = NativeDatabase.memory().interceptWith(log);
      db = AwDatabase(
        DatabaseConnection(root.interceptWith(FlushAfterCommit(root))),
      );
    });

    tearDown(() => db.close());

    Future<void> localWrite() => db.transaction(() async {
      await enqueueMutation(
        db,
        workspaceId: 'W-OWN',
        entityType: 'ee_ticket_draft',
        entityId: 'D-1',
        operation: 'create',
        patch: const {'subject': 'Pres durdu'},
      );
    });

    test('a committed local write is followed by a statement on the database '
        'itself — the point where the web replica reaches IndexedDB', () async {
      await db.customSelect('SELECT 1').get(); // opened, migrations done
      log.outside.clear();

      await localWrite();

      expect(log.outside, [FlushAfterCommit.flushStatement]);
      expect(await db.select(db.pendingMutations).get(), hasLength(1));
    });

    test('a nested transaction does not flush on its own — its parent does, '
        'once', () async {
      await db.customSelect('SELECT 1').get();
      log.outside.clear();

      await db.transaction(() async {
        await localWrite(); // nested: a savepoint
        expect(log.outside, isEmpty);
      });

      expect(log.outside, [FlushAfterCommit.flushStatement]);
    });

    test('a rolled-back transaction asks for nothing', () async {
      await db.customSelect('SELECT 1').get();
      log.outside.clear();

      await expectLater(
        db.transaction(() async {
          await localWrite();
          throw StateError('refused');
        }),
        throwsStateError,
      );

      expect(log.outside, isEmpty);
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    });
  });

  // OPH-480: the web connection is a DatabaseConnection, and drift hands an
  // interceptor wrapped around one the executor INSIDE it as `parent`. Built
  // around the connection itself, FlushAfterCommit never saw a top-level
  // transaction, so the N2 flush never ran on the web.
  group('the web-shaped connection (flushAfterEveryCommit)', () {
    late _RootLog webLog;
    late AwDatabase webDb;

    setUp(() {
      webLog = _RootLog();
      webDb = AwDatabase(
        flushAfterEveryCommit(
          DatabaseConnection(NativeDatabase.memory().interceptWith(webLog)),
        ),
      );
    });

    tearDown(() => webDb.close());

    Future<void> probe() => webDb.customStatement(
      "INSERT INTO action_receipts (event_id, action, applied_at) "
      "VALUES ('FLUSH-PROBE', 'probe', 0)",
    );

    test('a top-level commit on the web-shaped connection is followed by the '
        'flush statement', () async {
      await webDb.customSelect('SELECT 1').get();
      webLog.outside.clear();

      await webDb.transaction(probe);

      expect(webLog.outside, [FlushAfterCommit.flushStatement]);
    });

    test('a savepoint on the web-shaped connection flushes nothing on its '
        'own — its parent flushes once', () async {
      await webDb.customSelect('SELECT 1').get();
      webLog.outside.clear();

      await webDb.transaction(() async {
        await webDb.transaction(probe); // nested: a savepoint
        expect(webLog.outside, isEmpty);
      });

      expect(webLog.outside, [FlushAfterCommit.flushStatement]);
    });
  });
}
