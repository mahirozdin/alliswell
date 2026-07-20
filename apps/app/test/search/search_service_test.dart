import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/search/search.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// OPH-167 (ADR-0013) — the tiered fold search over the replica. Rows arrive
/// through the REAL applier, so these tests also prove the applier populates
/// the fold shadows for every searched entity type.
void main() {
  late AwDatabase db;
  late SearchService service;
  const ws = 'W1';

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    service = SearchService(db);
  });

  tearDown(() => db.close());

  Future<void> applyTask(
    String id,
    String title, {
    String? description,
    String status = 'open',
    List<String> tagIds = const [],
  }) async {
    await db
        .into(db.tasks)
        .insertOnConflictUpdate(
          taskCompanion({
            'id': id,
            'workspaceId': ws,
            'title': title,
            'description': description,
            'status': status,
          }),
        );
    await replaceTaskTags(db, id, tagIds);
  }

  Future<void> applyTag(String id, String name) => db
      .into(db.tags)
      .insertOnConflictUpdate(
        tagCompanion({
          'id': id,
          'workspaceId': ws,
          'name': name,
          'slug': name.toLowerCase(),
        }),
      );

  test('ranks title > tag > description and folds Turkish both ways', () async {
    await applyTag('G1', 'Çay');
    await applyTask('T-title', 'Çay siparişi');
    await applyTask('T-tag', 'Mutfak alışverişi', tagIds: ['G1']);
    await applyTask(
      'T-body',
      'Toplantı',
      description: 'çay servisi unutulmasın',
    );
    await applyTask('T-none', 'Alakasız iş');

    // ASCII query finds the Turkish text (cay → Çay), ranked by tier.
    final hits = await service.searchTasks(ws, 'cay', statuses: ['open']);
    expect(hits.map((h) => h.id).toList(), ['T-title', 'T-tag', 'T-body']);
    expect(hits.map((h) => h.tier).toList(), [0, 1, 2]);

    // And the reverse: a Turkish query finds ASCII-ish text.
    final reverse = await service.searchTasks(ws, 'ÇAY', statuses: ['open']);
    expect(reverse.map((h) => h.id), contains('T-title'));
  });

  test('multi-word queries AND their words, order-free', () async {
    await applyTask('T1', 'Sunum hazırla', description: 'pazartesi teslim');
    await applyTask('T2', 'Sunum izle');

    final both = await service.searchTasks(
      ws,
      'teslim sunum', // reversed order, split across title+description
      statuses: ['open'],
    );
    expect(both.map((h) => h.id).toList(), ['T1']);
    // Words split across FIELDS match the entity but no single field has
    // them all → body tier.
    expect(both.single.tier, 2);
  });

  test(
    'status scope is honored (inbox captures searchable on demand)',
    () async {
      await applyTask('T-in', 'Fikir: çay makinesi', status: 'inbox');
      expect(await service.searchTasks(ws, 'cay', statuses: ['open']), isEmpty);
      final withInbox = await service.searchTasks(
        ws,
        'cay',
        statuses: ['open', 'inbox'],
      );
      expect(withInbox.single.id, 'T-in');
    },
  );

  test('events search summary (tier 0) and location (tier 2)', () async {
    await db
        .into(db.externalEvents)
        .insertOnConflictUpdate(
          externalEventCompanion({
            'id': 'E1',
            'workspaceId': ws,
            'summary': 'Diş randevusu',
            'location': 'Kadıköy',
            'startsAt': '2026-08-01T09:00:00.000Z',
            'endsAt': '2026-08-01T10:00:00.000Z',
          }),
        );
    final bySummary = await service.searchEvents(ws, 'dis randevu');
    expect(bySummary.single.tier, 0);
    final byLocation = await service.searchEvents(ws, 'kadikoy');
    expect(byLocation.single.tier, 2);
  });

  test('projects search name (0) and description (2)', () async {
    await db
        .into(db.projects)
        .insertOnConflictUpdate(
          projectCompanion({
            'id': 'P1',
            'workspaceId': ws,
            'name': 'Yazılım',
            'description': 'iç araçlar',
          }),
        );
    expect((await service.searchProjects(ws, 'yazilim')).single.tier, 0);
    expect((await service.searchProjects(ws, 'araclar')).single.tier, 2);
  });

  test('LIKE wildcards in the query are literals, not wildcards', () async {
    await applyTask('T%', 'yüzde %20 indirim');
    await applyTask('TX', 'indirimsiz');
    final hits = await service.searchTasks(ws, '%20', statuses: ['open']);
    expect(hits.map((h) => h.id).toList(), ['T%']);
  });

  test('searchSnippet windows around the folded match', () {
    const body =
        'Uzun bir açıklamanın ortasında çay servisi geçiyor ve devamında '
        'başka şeyler anlatılıyor.';
    final snippet = searchSnippet(body, 'cay');
    expect(snippet, contains('çay servisi'));
    expect(snippet.length, lessThan(body.length));
  });
}
