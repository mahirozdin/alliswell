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
    await db.customStatement('DROP TABLE share_events'); // v16
    await db.customStatement('DROP TABLE ai_messages'); // v15
    await db.customStatement('DROP TABLE task_series'); // v14
    await db.customStatement('ALTER TABLE tasks DROP COLUMN series_id'); // v14
    await db.customStatement(
      'ALTER TABLE tasks DROP COLUMN occurrence_date', // v14
    );
    await db.customStatement('DROP TABLE quick_links'); // v13
    await db.customStatement(
      'ALTER TABLE tasks DROP COLUMN alarms_muted_at', // v11
    );
    await db.customStatement(
      'ALTER TABLE reminders DROP COLUMN snooze_count', // v10
    );
    await db.customStatement('DROP TABLE alarm_events'); // v9
    await db.customStatement('ALTER TABLE reminders DROP COLUMN kind'); // v8
    await db.customStatement('DROP TABLE folders'); // v7
    await db.customStatement(
      'ALTER TABLE file_rows DROP COLUMN folder_id', // v7
    );
    for (final drop in [
      // v6 (OPH-167): fold shadows on the tables v1 already had.
      'ALTER TABLE tasks DROP COLUMN title_fold',
      'ALTER TABLE tasks DROP COLUMN description_fold',
      'ALTER TABLE projects DROP COLUMN name_fold',
      'ALTER TABLE projects DROP COLUMN description_fold',
      'ALTER TABLE tags DROP COLUMN name_fold',
      'ALTER TABLE notes DROP COLUMN title_fold',
      'ALTER TABLE notes DROP COLUMN body_fold',
    ]) {
      await db.customStatement(drop);
    }
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
      // v7 (OPH-170): the folder tree, created empty — push-pull fills it.
      expect(await db.select(db.folders).get(), isEmpty);
      // v6 (OPH-167): the backfill folded the pre-existing row's text —
      // Turkish 'iş' matched by a plain 'is' query is the whole point.
      expect(task.titleFold, 'v1 tarihinden kalma is');
      // v9 (OPH-176): the device-only alarm log, created empty.
      expect(await db.select(db.alarmEvents).get(), isEmpty);
      // v8 (OPH-175): a reminder row from before the split reads as the nudge.
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              id: 'R1'.padRight(26, '0'),
              taskId: 'T1',
              remindAt: DateTime.utc(2026, 7, 20, 8, 30),
            ),
          );
      final reminder = await db.select(db.reminders).getSingle();
      expect(reminder.kind, 'remind');
      // v10 (OPH-177): rounds start counting from zero — we cannot invent how
      // many an already-snoozed alarm had before we counted.
      expect(reminder.snoozeCount, 0);
      // v11 (OPH-178): every existing task keeps its alarms — silence is asked
      // for, never inherited.
      expect(task.alarmsMutedAt, equals(null));
      // v12 (OPH-186): the Completed archive's index exists after the upgrade.
      // Asserted from sqlite's own catalogue, not from the migration code —
      // an index the migration "ran" but SQLite never created is the failure
      // mode worth catching.
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_tasks_completed'",
          )
          .get();
      expect(indexes, hasLength(1));
      // v13 (OPH-198): the quick access rail, created empty — the next pull
      // fills it with whatever this user has on their other devices.
      expect(await db.select(db.quickLinks).get(), isEmpty);
      // v15 (OPH-221): the AI bubble's device-local chat history, created
      // empty — it is never synced, so it starts blank on every device.
      expect(await db.select(db.aiMessages).get(), isEmpty);
      // v16 (OPH-242): the share pipeline's diagnostic trail, same story —
      // device-local, never synced, blank until something is shared here.
      expect(await db.select(db.shareEvents).get(), isEmpty);

      // The outbox came through: nothing the user wrote offline was stranded.
      final pending = await db.select(db.pendingMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityId, 'T1');

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 16);
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

      // A fresh install gets the ad-hoc index too: drift's `createAll` only
      // builds tables, so `onCreate` has to create it explicitly — otherwise
      // new users would silently be the only ones on the full-scan path.
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_tasks_completed'",
          )
          .get();
      expect(indexes, hasLength(1));

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 16);
      await db.close();
    },
  );
}
