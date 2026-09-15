import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What every connection to the replica is opened with (OPH-318).
///
/// ── WHY THIS IS NOT THE DEFAULT ───────────────────────────────────────────
///
/// drift does not turn WAL on for you: SQLite's default journal blocks readers
/// for the whole of a write, and the replica already has two writers. The
/// home-screen widget's background isolate opens its own `AwDatabase` on this
/// same file while the app is running (`widget_callback.dart`), and it gets
/// away with it only because its write is one short statement. A sync pull
/// applies every change in ONE transaction (`sync_applier.dart:25`), so the
/// next thing to open a second connection during a pull would meet a lock that
/// lasts as long as the network did.
///
/// WAL lets readers run while a writer holds the file, and `busy_timeout`
/// turns the remaining collision — two writers — from an immediate
/// `SQLITE_BUSY` into a five-second wait, which is longer than any write this
/// app makes. Listed rather than inlined so a test can open a file the same
/// way the app does and prove the pragmas actually took.
const awSqlitePragmas = <String>[
  'pragma journal_mode = WAL',
  'pragma busy_timeout = 5000',
];

/// Native platforms: a background-isolate sqlite file under the app-support
/// directory (never Documents — the replica is disposable cache, MySQL is
/// canonical).
DatabaseConnection openAwConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'alliswell.sqlite'));
      return DatabaseConnection(
        NativeDatabase.createInBackground(
          file,
          setup: (db) {
            for (final pragma in awSqlitePragmas) {
              db.execute(pragma);
            }
          },
        ),
      );
    }),
  );
}
