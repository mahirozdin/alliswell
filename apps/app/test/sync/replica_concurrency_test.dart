import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/connection_native.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-318 — the replica has two writers and always has had. The home-screen
/// widget's background isolate opens its own connection to this file while the
/// app is running; a sync pull applies every change in ONE transaction. The
/// pragmas are what keep those two out of each other's way.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    // Two connections to one file is not a mistake here, it is the subject.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = await Directory.systemTemp.createTemp('alliswell-wal');
    file = File('${dir.path}/replica.sqlite');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Opened the way the app opens it — the pragmas under test, not a copy of
  /// them (`connection_native.dart`).
  AwDatabase open() => AwDatabase(
    DatabaseConnection(
      NativeDatabase(
        file,
        setup: (db) {
          for (final pragma in awSqlitePragmas) {
            db.execute(pragma);
          }
        },
      ),
    ),
  );

  Future<String> pragma(AwDatabase db, String name) async {
    final row = await db.customSelect('pragma $name').getSingle();
    return row.data.values.first.toString().toLowerCase();
  }

  test('the pragmas actually take on a real file', () async {
    final db = open();
    addTearDown(db.close);

    // drift does not do this for you: without asking, SQLite journals the old
    // way and a writer blocks every reader for the whole of its transaction.
    expect(await pragma(db, 'journal_mode'), 'wal');
    expect(await pragma(db, 'busy_timeout'), '5000');
  });

  test(
    'WAL is a property of the FILE, so the second opener inherits it',
    () async {
      final first = open();
      await first.customStatement(
        'create table if not exists probe (x integer)',
      );
      await first.close();

      // The widget's background isolate opens the same path with the same setup.
      final second = open();
      addTearDown(second.close);
      expect(await pragma(second, 'journal_mode'), 'wal');
      expect(File('${file.path}-wal').existsSync(), isTrue);
    },
  );

  test(
    'a reader is not blocked by a transaction that is still writing',
    () async {
      final writer = open();
      final reader = open();
      addTearDown(writer.close);
      addTearDown(reader.close);

      await writer.customStatement('create table probe (x integer)');
      await writer.customStatement('insert into probe values (1)');

      final released = Completer<void>();
      final writing = writer.transaction(() async {
        await writer.customStatement('insert into probe values (2)');
        // The write lock is held from here until the transaction ends.
        await released.future;
      });

      // This is the whole acceptance: in the old journal mode it raises
      // SQLITE_BUSY, and the widget's isolate is exactly this reader.
      final rows = await reader.customSelect('select x from probe').get();
      expect(
        rows,
        hasLength(1),
      ); // the uncommitted row is not visible, and that is right

      released.complete();
      await writing;
      expect(
        (await reader.customSelect('select x from probe').get()),
        hasLength(2),
      );
    },
  );
}
