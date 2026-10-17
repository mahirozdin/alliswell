import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/tasks/data/task_when.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-107 — Inbox captures (`status: inbox`) stay off planning lists until a
/// date or project triages them into a real 'open' task.
void main() {
  late AwDatabase db;
  late TaskStore store;
  const ws = 'W1';

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    store = TaskStore(db, () {});
  });
  tearDown(() => db.close());

  Future<String> capture(String title) =>
      store.create(ws, {'title': title, 'status': 'inbox'});

  Future<String> statusOf(String id) async => (await (db.select(
    db.tasks,
  )..where((t) => t.id.equals(id))).getSingle()).status;

  test('a capture stays off planning lists but shows in the Inbox', () async {
    await capture('Fikir');
    expect(await store.watchOpen(ws).first, isEmpty);
    expect((await store.watchInbox(ws).first).map((t) => t.title), ['Fikir']);
  });

  test('a date promotes a capture to open and off the Inbox', () async {
    final id = await capture('Tarih');
    await store.update(id, {'dueAt': DateTime.utc(2030).toIso8601String()});
    expect(await statusOf(id), 'open');
    expect(await store.watchInbox(ws).first, isEmpty);
    expect((await store.watchOpen(ws).first).single.id, id);
  });

  test('a project promotes a capture to open', () async {
    final id = await capture('Proje');
    await store.update(id, {'projectId': 'P1'.padRight(26, '0')});
    expect(await statusOf(id), 'open');
  });

  test('an unrelated edit does NOT promote a capture', () async {
    final id = await capture('Başlık');
    await store.update(id, {'title': 'Yeni'});
    expect(await statusOf(id), 'inbox');
    expect(await store.watchOpen(ws).first, isEmpty);
  });

  test('clearing a date (null) does not promote', () async {
    final id = await capture('Boş tarih');
    await store.update(id, {'dueAt': null});
    expect(await statusOf(id), 'inbox');
  });

  test('an explicit status on the patch wins over auto-promote', () async {
    final id = await capture('Elle');
    await store.update(id, {
      'dueAt': DateTime.utc(2030).toIso8601String(),
      'status': 'waiting',
    });
    expect(await statusOf(id), 'waiting');
  });

  test('a task created WITH a date is born open, not a capture', () async {
    final id = await store.create(ws, {
      'title': 'Tarihli',
      'status': 'inbox',
      'dueAt': DateTime.utc(2030).toIso8601String(),
    });
    expect(await statusOf(id), 'open');
  });

  test(
    'promotion rides ONE outbox mutation that carries the new status',
    () async {
      final id = await capture('Tek mutation');
      await store.update(id, {'projectId': 'P2'.padRight(26, '0')});

      final rows = await (db.select(
        db.pendingMutations,
      )..where((m) => m.entityId.equals(id))).get();
      final updates = rows.where((r) => r.operation == 'update').toList();
      expect(updates, hasLength(1), reason: 'one write → one mutation');
      final patch =
          jsonDecode(updates.single.patchJson!) as Map<String, dynamic>;
      expect(patch['status'], 'open');
      expect(patch['projectId'], 'P2'.padRight(26, '0'));
    },
  );
  // OPH-372: a "when" is a date too — the capture has been planned.
  test('a "when" promotes a capture to open in the SAME mutation', () async {
    final id = await capture('Ne zaman');
    await store.setWhen(id, DateTime(2030, 6, 3));
    expect(await statusOf(id), 'open');
    final rows = await (db.select(
      db.pendingMutations,
    )..where((m) => m.entityId.equals(id))).get();
    final updates = rows.where((r) => r.operation == 'update').toList();
    expect(updates, hasLength(1));
    final patch = jsonDecode(updates.single.patchJson!) as Map<String, dynamic>;
    expect(patch['status'], 'open');
    expect(patch['startAt'], awWhenIso(DateTime(2030, 6, 3)));
  });

  test('a capture created WITH a "when" is born open', () async {
    final id = await store.create(ws, {
      'title': 'Ne zamanlı',
      'status': 'inbox',
      'startAt': awWhenIso(DateTime(2030, 6, 3)),
    });
    expect(await statusOf(id), 'open');
  });

  test('a duration alone does not promote, and is kept on the row', () async {
    final id = await capture('Süreli');
    await store.setDuration(id, 45);
    expect(await statusOf(id), 'inbox');
    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.estimatedMinutes, 45);
  });
}
