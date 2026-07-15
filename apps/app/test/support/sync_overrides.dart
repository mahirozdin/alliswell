import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_socket.dart';

/// Overrides every widget test pumping the full app needs since local-first
/// (OPH-054): an in-memory replica instead of the platform-channel database,
/// no periodic pull timer (would outlive the test body), and a zero debounce
/// so a pumpAndSettle carries writes through push+pull deterministically.
/// Pass [socketFactory] to observe/drive the live socket (default: none).
List<Override> syncTestOverrides({SyncSocketFactory? socketFactory}) => [
  databaseProvider.overrideWith((ref) {
    // closeStreamsSynchronously: drift otherwise keeps a Timer.run alive per
    // cancelled watch stream (its stream cache), which trips flutter_test's
    // pending-timer teardown check.
    final db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ref.onDispose(db.close);
    return db;
  }),
  syncPullIntervalProvider.overrideWithValue(null),
  syncDebounceProvider.overrideWithValue(Duration.zero),
  // No real sockets (and no reconnect timers) inside the fake-async zone.
  syncSocketFactoryProvider.overrideWithValue(socketFactory),
];
