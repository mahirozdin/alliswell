import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/connection_native.dart';
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
    // v20–v29 are all NEW TABLES, and until EE-188 none of them was undone
    // here: the fixture walked back to v18 and stopped, so every table added
    // after it still existed in the "v1" database. The v1 → latest test then
    // asserted those tables were present *after* migrating — which they were
    // before it, too. Deleting the v29 step left the suite green; that is how
    // this was found, and it had been true for ten versions.
    //
    // Children before parents: drift opens with foreign keys on.
    for (final drop in [
      'DROP TABLE kb_articles', // v31
      'DROP TABLE assets', // v30
      'DROP TABLE problems', // v29
      'DROP TABLE changes', // v28
      'DROP TABLE ticket_assignments', // v25
      'DROP TABLE ticket_comments', // v24
      'DROP TABLE tickets', // v24 (carries v26/v27's columns; those steps are
      // guarded `from >= 24`, so a v1 install never runs them — it gets the
      // current definition straight from createTable.)
      'DROP TABLE notifications', // v23
      'DROP TABLE task_assignments', // v22
      'DROP TABLE member_profiles', // v22
      'DROP TABLE shared_items', // v21
      'DROP TABLE rejected_mutations', // v20
    ]) {
      await db.customStatement(drop);
    }
    await db.customStatement(
      'ALTER TABLE notes DROP COLUMN conflict_version_id', // v18
    );
    await db.customStatement(
      'ALTER TABLE pending_mutations DROP COLUMN base_revision', // v18
    );
    await db.customStatement(
      'ALTER TABLE notes DROP COLUMN content_format', // v17
    );
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
    // A note as the rich editor left it: a Delta, no markdown, and a
    // `plain_text` derived from the ops. This is what every note in every
    // replica looked like before ADR-0033, and it is what v19 has to convert.
    await db.customStatement(r'''
      INSERT INTO notes (id, workspace_id, title, content_delta, plain_text,
                         is_pinned, is_archived, revision)
      VALUES ('N1', 'W1', 'Eski not',
              '[{"insert":"kalın","attributes":{"bold":true}},{"insert":"\n"}]',
              'kalın', 0, 0, 3)
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
      // v17 (OPH-248) added a `content_format` COLUMN with no backfill.
      // v19 (OPH-274, ADR-0033) is the backfill it never needed until markdown
      // became the only canonical form — and it is the one migration in this
      // file that rewrites CONTENT, so it is worth being specific about.
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('N1'))).getSingle();
      expect(note.contentFormat, 'markdown');
      expect(
        note.contentMarkdown,
        '**kalın**',
        reason:
            'the Delta was converted in place, not left for the next pull '
            '— a device that stays offline would otherwise render an empty '
            'body, because its markdown column was never filled',
      );
      // The delta is NOT cleared: an escape hatch a human can still read.
      expect(note.contentDelta, isNot(null));
      // The search columns follow the new canonical field. They were derived
      // from the delta, and offline search reads whatever is canonical.
      expect(note.plainText, 'kalın');
      expect(note.bodyFold, 'kalin');
      // v18 (OPH-268): no note arrives from a migration in conflict — the
      // pointer is written by a push result, never by an upgrade.
      expect(note.conflictVersionId, null);

      // The outbox came through: nothing the user wrote offline was stranded.
      final pending = await db.select(db.pendingMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityId, 'T1');
      // v18: the queued write survived AND gained the new column, empty —
      // an offline write made before the upgrade simply carries no base, which
      // is exactly the old-client path the server still honours.
      expect(pending.single.baseRevision, null);

      // v20 (EE-051): a brand-new table for refused writes. It arrives empty
      // on an upgrade, which is the honest state — a device that has never
      // been refused has nothing parked.
      expect(await db.select(db.rejectedMutations).get(), isEmpty);

      // v21 (EE-061): shared_items — what another unit shared with this one.
      // Also empty on an upgrade: the rows arrive by pull, never by migration,
      // because the replica does not author them (they are pull-only).
      expect(await db.select(db.sharedItems).get(), isEmpty);

      // v22 (EE-068): member_profiles + task_assignments. Empty for the same
      // reason — both fill from the next pull. The roster half is a REPAIR:
      // the server has been sending `ee_member_profile` since EE-017 and the
      // applier had no case for it, so every device threw it away. An upgraded
      // device gets it on the first pull after this migration.
      expect(await db.select(db.memberProfiles).get(), isEmpty);
      expect(await db.select(db.taskAssignments).get(), isEmpty);

      // v23 (EE-077): notifications — the inbox behind the centre and its
      // badge. Empty for the same reason as every table above it: the rows
      // arrive by pull. A device that upgrades mid-week gets its whole inbox
      // on the first sync after, because the server keeps it.
      expect(await db.select(db.notifications).get(), isEmpty);

      // v24/v25 (EE-084, EE-086): the service desk. Three tables, all empty
      // for the same reason as everything above — the rows arrive by pull, and
      // an upgrading device gets its unit's queue on the first sync after.
      //
      // These are listed one by one rather than trusted to the version number,
      // because that is the whole point of this test: a step that creates no
      // table still bumps `user_version`, so only naming the tables proves the
      // step ran. (E09 shipped three of them and this file was not updated —
      // the assertion below went red on CI and nowhere else, which is how the
      // gap was found.)
      expect(await db.select(db.tickets).get(), isEmpty);
      expect(await db.select(db.ticketComments).get(), isEmpty);
      expect(await db.select(db.ticketAssignments).get(), isEmpty);

      // v26 (EE-097): the SLA badge, as two COLUMNS rather than a table — so
      // the idiom above cannot prove it. An empty `select` would pass whether
      // or not the ALTER ran; naming the columns in SQL throws if it did not,
      // which is the same "prove the step, not the number" rule read on a
      // migration that adds no table.
      await db.customSelect('SELECT sla_due_at, sla_status FROM tickets').get();

      // v27 (EE-167 + EE-169): three more columns on `tickets` and one on
      // `ticket_comments`, proved the same way and for the same reason — an
      // empty select would pass whether or not the ALTER ran.
      await db
          .customSelect('SELECT number, subject_fold, body_fold FROM tickets')
          .get();
      await db.customSelect('SELECT body_fold FROM ticket_comments').get();

      // v28 (EE-186 / OPH-327): a new table, so the empty-select idiom proves
      // it directly — and the fold columns are named in SQL for the v26 reason,
      // since a `select *` would pass whether or not OPH-326's shadows landed.
      expect(await db.select(db.changes).get(), isEmpty);
      await db
          .customSelect('SELECT title_fold, impact_fold FROM changes')
          .get();

      // v29 (EE-188 / OPH-327): the second of OPH-327's tables, in a step of
      // its own — their shapes come from separate extension records that land
      // in different phases, so one step for all four was never buildable.
      expect(await db.select(db.problems).get(), isEmpty);
      await db
          .customSelect('SELECT title_fold, symptom_fold FROM problems')
          .get();

      // v30 (EE-191 / OPH-327): the third. The tag is folded beside the name
      // because a technician at the machine searches for the number on the
      // sticker — and the DATE columns are TEXT, which this asserts by
      // writing a day into one and reading it back unchanged.
      expect(await db.select(db.assets).get(), isEmpty);
      await db.customSelect('SELECT name_fold, tag_fold FROM assets').get();
      await db.customStatement(
        "INSERT INTO assets (id, workspace_id, type, name, tag, status, "
        "warranty_until, revision) VALUES ('a1', 'w1', 'machine', 'Lathe', "
        "'TAG-1', 'in_stock', '2027-03-01', 0)",
      );
      final day = await db
          .customSelect('SELECT warranty_until FROM assets')
          .getSingle();
      expect(day.data['warranty_until'], '2027-03-01');
      await db.customStatement('DELETE FROM assets');

      // v31 (EE-195 / OPH-327): the FOURTH and last, which is what lets that
      // hub close. The SOLUTION is deliberately not folded — somebody
      // searching describes what they SEE, and matching on the procedure would
      // rank the article whose steps share a word with the machine in front of
      // them. Asserting the two shadows that DO exist is therefore also an
      // assertion about the one that does not.
      expect(await db.select(db.kbArticles).get(), isEmpty);
      await db
          .customSelect('SELECT title_fold, symptom_fold FROM kb_articles')
          .get();

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 31);
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
      expect(version.data['user_version'], 31);
      await db.close();
    },
  );

  // OPH-318 — the upgrade every existing install actually performs: a replica
  // written with the old rollback journal, opened for the first time by a
  // build that asks for WAL. The file shape changes (`-wal`/`-shm` siblings
  // appear) at the same moment the schema migration runs, and the replica is
  // where the OUTBOX lives — a write that never reached the server is the one
  // kind of data this app can lose for good.
  test(
    'an old install switches to WAL without losing what it was holding',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      await seedV1Database();
      expect(File('${file.path}-wal').existsSync(), isFalse);

      final db = AwDatabase(
        DatabaseConnection(
          NativeDatabase(
            file,
            setup: (raw) {
              for (final pragma in awSqlitePragmas) {
                raw.execute(pragma);
              }
            },
          ),
        ),
      );

      // The queued write from before the upgrade — the thing that must not be
      // lost — and the row it belongs to.
      final pending = await db.select(db.pendingMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityId, 'T1');

      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('T1'))).getSingle();
      expect(task.title, 'v1 tarihinden kalma iş');

      final mode = await db.customSelect('pragma journal_mode').getSingle();
      expect(mode.data.values.first.toString().toLowerCase(), 'wal');
      expect(File('${file.path}-wal').existsSync(), isTrue);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 31);
      await db.close();
    },
  );
}
