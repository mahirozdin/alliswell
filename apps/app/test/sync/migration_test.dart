import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';

/// OPH-081 — the replica's FIRST schema migration (v1 → v2: the calendar
/// mirror flag). The plan is in docs/TASKS.md; this is the proof.
///
/// Why it is worth a file of its own: the replica is not just cache, it holds
/// the **outbox**. A migration that fails to open, or that drops rows, strands
/// writes that never reached the server — the one class of data loss a
/// local-first app can actually inflict.
///
/// Drift's sanctioned harness (`drift_dev schema dump` → generated verifiers)
/// cannot run on this toolchain — drift_dev 2.34.0's verifier calls
/// `allSchemaEntities`, which drift 2.34.2's drift3-preview `GeneratedDatabase`
/// does not define. So we manufacture a genuine v1 database on disk instead and
/// let the real `AwDatabase.migration` run against it. No mocks, real SQLite,
/// real migration code path.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('alliswell-migration');
    file = File('${dir.path}/replica.sqlite');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Builds the schema as v1 shipped it — every table, minus what v2/v3 add,
  /// with `user_version = 1` — and leaves one task and one queued mutation in
  /// it, the way a real install would look.
  Future<void> seedV1Database() async {
    final db = AwDatabase(DatabaseConnection(NativeDatabase(file)));
    // Opening creates the CURRENT schema, so walk it back to v1: undo what each
    // later version added, then rewind the version.
    await db.customStatement('DROP TABLE external_events'); // v3
    await db.customStatement(
      'ALTER TABLE tasks DROP COLUMN calendar_mirror_enabled', // v2
    );
    await db.customStatement('PRAGMA user_version = 1');
    await db.customStatement('''
      INSERT INTO tasks (id, workspace_id, title, status, priority, timezone,
                         is_urgent, requires_acknowledgement, sort_order, revision)
      VALUES ('T1', 'W1', 'v1 tarihinden kalma iş', 'open', 'high',
              'Europe/Istanbul', 0, 0, 0, 7)
    ''');
    // Timestamps are ISO text in this database (OPH-054 — DATETIME(3)
    // precision round-trips), not unix ints.
    await db.customStatement('''
      INSERT INTO pending_mutations (id, workspace_id, entity_type, entity_id,
                                     operation, local_updated_at, created_at, attempts)
      VALUES ('M1', 'W1', 'task', 'T1', 'update',
              '2026-07-15T10:00:00.000Z', '2026-07-15T10:00:00.000Z', 0)
    ''');
    await db.close();
  }

  test(
    'v1 → latest keeps every row and adds what each version brought',
    () async {
      await seedV1Database();

      // Reopening runs the real onUpgrade — every step, in order.
      var db = AwDatabase(DatabaseConnection(NativeDatabase(file)));
      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('T1'))).getSingle();

      expect(task.title, 'v1 tarihinden kalma iş');
      expect(task.priority, 'high'); // the row survived intact…
      expect(task.revision, 7);
      expect(
        task.calendarMirrorEnabled,
        isFalse,
      ); // …and took v2's NOT NULL default

      // v3 (OPH-083): a brand new table, empty until the next pull fills it.
      expect(await db.select(db.externalEvents).get(), isEmpty);
      // v4 (OPH-078): the device-local Apple map, likewise created empty.
      expect(await db.select(db.appleEventLinks).get(), isEmpty);
      // v5 (OPH-153): attachment metadata, created empty — pull-only.
      expect(await db.select(db.fileRows).get(), isEmpty);

      // The outbox came through: nothing the user wrote offline was stranded.
      final pending = await db.select(db.pendingMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityId, 'T1');

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 5);
      await db.close();

      // Opening an already-migrated file is a no-op, not a second ALTER (which
      // would throw "duplicate column name").
      db = AwDatabase(DatabaseConnection(NativeDatabase(file)));
      await expectLater(
        (db.select(db.tasks)..where((t) => t.id.equals('T1'))).getSingle(),
        completes,
      );
      await db.close();
    },
  );

  test(
    'a fresh install creates the latest schema directly, no migration involved',
    () async {
      final db = AwDatabase(DatabaseConnection(NativeDatabase(file)));
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'T2'.padRight(26, '0'),
              workspaceId: 'W1'.padRight(26, '0'),
              title: 'Yeni kurulum',
              calendarMirrorEnabled: const Value(true),
            ),
          );

      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('T2'.padRight(26, '0')))).getSingle();
      expect(task.calendarMirrorEnabled, isTrue);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 5);
      await db.close();
    },
  );
}
