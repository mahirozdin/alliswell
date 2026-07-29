import 'dart:convert';

import 'package:alliswell/src/features/quick_access/data/quick_access_store.dart';
import 'package:alliswell/src/features/quick_access/data/quick_link.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-198 — the Quick Access replica + store (ADR-0018).
void main() {
  late AwDatabase db;
  late QuickAccessStore store;
  const ws = 'W1';
  const me = 'user-1';
  const other = 'user-2';

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    store = QuickAccessStore(db);
  });

  tearDown(() => db.close());

  Future<void> seedProject(
    String id, {
    String name = 'Ahmet',
    String status = 'active',
  }) => db
      .into(db.projects)
      .insert(
        ProjectsCompanion.insert(
          id: id,
          workspaceId: ws,
          name: name,
          status: Value(status),
        ),
      );

  Future<List<PendingMutation>> mutations() =>
      db.select(db.pendingMutations).get();

  test(
    'add writes the row and ONE create mutation with the wire patch',
    () async {
      await seedProject('P1');
      final id = await store.add(
        workspaceId: ws,
        userId: me,
        kind: QuickKind.project,
        targetId: 'P1',
        title: 'Ahmet',
        emoji: '🚀',
      );
      expect(id, isNotNull);

      final rows = await store.watchMine(ws, me).first;
      expect(rows, hasLength(1));
      expect(rows.single.link.title, 'Ahmet');
      expect(rows.single.link.emoji, '🚀');
      expect(rows.single.targetTitle, 'Ahmet');
      expect(rows.single.isBroken, isFalse);

      final queued = await mutations();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'quick_link');
      expect(queued.single.operation, 'create');
      final patch =
          jsonDecode(queued.single.patchJson!) as Map<String, dynamic>;
      expect(patch, {
        'kind': 'project',
        'title': 'Ahmet',
        'targetId': 'P1',
        'emoji': '🚀',
      });
      // Null fields are absent, never explicit nulls: on a create, null would
      // mean "clear this", which is a different statement.
      expect(patch.containsKey('url'), isFalse);
      expect(patch.containsKey('colorRgb'), isFalse);
    },
  );

  test('adding the same target twice is a no-op, not a second row', () async {
    await seedProject('P1');
    final first = await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.project,
      targetId: 'P1',
      title: 'Ahmet',
    );
    final again = await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.project,
      targetId: 'P1',
      title: 'Ahmet yine',
    );
    expect(again, first);
    expect(await store.watchMine(ws, me).first, hasLength(1));
    expect(await mutations(), hasLength(1));
  });

  test('the 50 limit is enforced offline too', () async {
    for (var i = 0; i < QuickAccessStore.maxLinks; i++) {
      final id = await store.add(
        workspaceId: ws,
        userId: me,
        kind: QuickKind.url,
        url: 'https://x.dev/$i',
        title: 'L$i',
      );
      expect(id, isNotNull);
    }
    final over = await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.url,
      url: 'https://x.dev/51',
      title: 'Fazla',
    );
    expect(over, isNull, reason: 'the UI shows the honest limit message');
    expect(await store.countMine(ws, me), QuickAccessStore.maxLinks);
  });

  test('reorder writes ONE mutation carrying the id list', () async {
    final ids = <String>[];
    for (final title in ['A', 'B', 'C']) {
      ids.add(
        (await store.add(
          workspaceId: ws,
          userId: me,
          kind: QuickKind.url,
          url: 'https://x.dev/$title',
          title: title,
        ))!,
      );
    }
    await db.delete(db.pendingMutations).go(); // ignore the three creates

    final reversed = ids.reversed.toList();
    await store.reorder(ws, reversed);

    final rows = await store.watchMine(ws, me).first;
    expect(rows.map((r) => r.link.title), ['C', 'B', 'A']);
    expect(rows.map((r) => r.link.sortOrder), [0, 1024, 2048]);

    final queued = await mutations();
    expect(
      queued,
      hasLength(1),
      reason: 'fifty updates would be fifty revisions',
    );
    expect(queued.single.operation, 'update');
    expect(
      queued.single.entityId,
      reversed.first,
      reason: 'the anchor is the head',
    );
    final patch = jsonDecode(queued.single.patchJson!) as Map<String, dynamic>;
    expect(patch, {'orderedIds': reversed});
  });

  test('rename, emoji and colour each push their own patch', () async {
    final id = (await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.url,
      url: 'https://x.dev',
      title: 'Site',
    ))!;
    await db.delete(db.pendingMutations).go();

    await store.rename(id, '  Yeni ad  ');
    await store.setEmoji(id, null);
    await store.setColor(id, '#2563EB');

    final queued = await mutations();
    expect(queued.map((m) => m.operation), ['update', 'update', 'update']);
    final patches = [
      for (final m in queued) jsonDecode(m.patchJson!) as Map<String, dynamic>,
    ];
    expect(patches[0], {'title': 'Yeni ad'});
    expect(patches[1], {'emoji': null}); // an explicit null CLEARS the emoji
    expect(patches[2], {'colorRgb': '#2563EB'});

    final row = (await store.watchMine(ws, me).first).single;
    expect(row.link.title, 'Yeni ad');
    expect(row.link.colorRgb, '#2563EB');
  });

  test('one rail per user and per workspace', () async {
    await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.url,
      url: 'https://x.dev/mine',
      title: 'Benim',
    );
    await store.add(
      workspaceId: ws,
      userId: other,
      kind: QuickKind.url,
      url: 'https://x.dev/theirs',
      title: 'Onunki',
    );
    await store.add(
      workspaceId: 'W2',
      userId: me,
      kind: QuickKind.url,
      url: 'https://x.dev/other-ws',
      title: 'Başka alan',
    );

    expect((await store.watchMine(ws, me).first).map((r) => r.link.title), [
      'Benim',
    ]);
    expect((await store.watchMine(ws, other).first).map((r) => r.link.title), [
      'Onunki',
    ]);
    expect((await store.watchMine('W2', me).first).map((r) => r.link.title), [
      'Başka alan',
    ]);
  });

  test(
    'a target the replica does not have reads as broken; url rows never do',
    () async {
      await store.add(
        workspaceId: ws,
        userId: me,
        kind: QuickKind.project,
        targetId: 'GHOST',
        title: 'Kayıp',
      );
      await store.add(
        workspaceId: ws,
        userId: me,
        kind: QuickKind.url,
        url: 'https://x.dev',
        title: 'Site',
      );
      final rows = await store.watchMine(ws, me).first;
      expect(rows.firstWhere((r) => r.link.title == 'Kayıp').isBroken, isTrue);
      expect(rows.firstWhere((r) => r.link.title == 'Site').isBroken, isFalse);
    },
  );

  test('an archived target stays usable and is flagged, not broken', () async {
    await seedProject('P1', status: 'archived');
    await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.project,
      targetId: 'P1',
      title: 'Ahmet',
    );
    final row = (await store.watchMine(ws, me).first).single;
    expect(row.isArchived, isTrue);
    expect(row.isBroken, isFalse);
  });

  test(
    'renaming the target updates the rail live, without touching the shortcut name',
    () async {
      await seedProject('P1', name: 'Ahmet');
      await store.add(
        workspaceId: ws,
        userId: me,
        kind: QuickKind.project,
        targetId: 'P1',
        title: 'Ahmet',
      );
      final stream = store.watchMine(ws, me);
      expect((await stream.first).single.targetRenamed, isFalse);

      await (db.update(db.projects)..where((p) => p.id.equals('P1'))).write(
        const ProjectsCompanion(name: Value('Ahmet Yılmaz')),
      );

      // The JOIN's readsFrom is what makes this re-emit: without `projects` in
      // that set the rail would silently freeze on the old name.
      final row = (await stream.first).single;
      expect(row.targetTitle, 'Ahmet Yılmaz');
      expect(row.link.title, 'Ahmet', reason: 'the title belongs to the user');
      expect(row.targetRenamed, isTrue);
    },
  );

  test('remove deletes locally and queues one delete mutation', () async {
    final id = (await store.add(
      workspaceId: ws,
      userId: me,
      kind: QuickKind.url,
      url: 'https://x.dev',
      title: 'Site',
    ))!;
    await db.delete(db.pendingMutations).go();

    await store.remove(id);
    expect(await store.watchMine(ws, me).first, isEmpty);
    final queued = await mutations();
    expect(queued, hasLength(1));
    expect(queued.single.operation, 'delete');
    expect(queued.single.entityId, id);
  });

  test(
    'forgetting a dead target writes NO mutation — the server cascades',
    () async {
      await seedProject('P1');
      await store.add(
        workspaceId: ws,
        userId: me,
        kind: QuickKind.project,
        targetId: 'P1',
        title: 'Ahmet',
      );
      await db.delete(db.pendingMutations).go();

      await store.forgetTargets(ws, QuickKind.project, ['P1']);
      expect(await store.watchMine(ws, me).first, isEmpty);
      expect(await mutations(), isEmpty);
    },
  );

  test('the applier round-trips a snapshot and honours a tombstone', () async {
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 7,
      changes: [
        SyncChange(
          revision: 7,
          entityType: 'quick_link',
          entityId: 'Q1',
          operation: 'create',
          data: const {
            'id': 'Q1',
            'workspaceId': ws,
            'userId': me,
            'kind': 'url',
            'targetId': null,
            'url': 'https://alliswell.space',
            'title': 'Site',
            'emoji': null,
            'colorRgb': null,
            'sortOrder': 2048,
            'revision': 7,
          },
        ),
      ],
    );
    final row = (await store.watchMine(ws, me).first).single;
    expect(row.link.url, 'https://alliswell.space');
    expect(row.link.sortOrder, 2048);

    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 8,
      changes: [
        const SyncChange(
          revision: 8,
          entityType: 'quick_link',
          entityId: 'Q1',
          operation: 'delete',
          data: null,
        ),
      ],
    );
    expect(await store.watchMine(ws, me).first, isEmpty);
  });
}
