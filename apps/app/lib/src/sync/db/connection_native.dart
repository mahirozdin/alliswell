import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native platforms: a background-isolate sqlite file under the app-support
/// directory (never Documents — the replica is disposable cache, MySQL is
/// canonical).
DatabaseConnection openAwConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'alliswell.sqlite'));
      return DatabaseConnection(NativeDatabase.createInBackground(file));
    }),
  );
}
