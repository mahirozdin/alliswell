import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/quick_access/data/quick_link.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_navigation.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/search/global_search.dart';
import 'package:alliswell/src/search/providers.dart';
import 'package:alliswell/src/search/search_recents.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// OPH-374 — the global search palette's data: groups over the replica, the
/// recents rules, and the shared "where does this open" table.
void main() {
  group('recents', () {
    const t1 = SearchRecent(GlobalSearchKind.task, 'T1');
    const p1 = SearchRecent(GlobalSearchKind.project, 'P1');

    test('parse tolerates junk and drops what does not parse', () {
      expect(parseSearchRecents(null), isEmpty);
      expect(parseSearchRecents('not json'), isEmpty);
      expect(parseSearchRecents('{"kind":"task"}'), isEmpty);
      expect(
        parseSearchRecents(
          '[{"kind":"task","id":"T1"},{"kind":"nope","id":"X"},'
          '{"id":"Y"},7,{"kind":"project","id":"P1"},'
          '{"kind":"task","id":"T1"}]',
        ),
        [t1, p1],
      );
    });

    test('push dedupes by kind and id, moves to the front, caps at 8', () {
      expect(pushSearchRecent([t1, p1], p1), [p1, t1]);
      // Same id, different kind: two different things.
      const n1 = SearchRecent(GlobalSearchKind.note, 'T1');
      expect(pushSearchRecent([t1], n1), [n1, t1]);
      var list = <SearchRecent>[];
      for (var i = 0; i < 12; i++) {
        list = pushSearchRecent(
          list,
          SearchRecent(GlobalSearchKind.task, 'T$i'),
        );
      }
      expect(list, hasLength(kSearchRecentsLimit));
      expect(list.first.id, 'T11');
    });

    test('encode and parse round-trip', () {
      expect(parseSearchRecents(encodeSearchRecents([t1, p1])), [t1, p1]);
    });

    test('a route visit names its entity, and only an entity', () {
      expect(recentFromLocation('/tasks/X'), t1.withId('X'));
      expect(recentFromLocation('/tasks/X/history'), isNull);
      expect(
        recentFromLocation('/projects/X'),
        const SearchRecent(GlobalSearchKind.project, 'X'),
      );
      expect(recentFromLocation('/projects'), isNull);
      expect(recentFromLocation('/files/folder/X'), isNull);
      expect(recentFromLocation('/notes/new'), isNull);
      expect(recentFromLocation('/notes/import'), isNull);
      expect(recentFromLocation('/notes/file'), isNull);
      expect(
        recentFromLocation('/notes/X'),
        const SearchRecent(GlobalSearchKind.note, 'X'),
      );
      expect(
        recentFromLocation('/edit-note/X'),
        const SearchRecent(GlobalSearchKind.note, 'X'),
      );
      expect(recentFromLocation('/home'), isNull);
      expect(recentFromLocation('/settings/general'), isNull);
    });

    test('they belong to the person: sign-out wipes them', () {
      expect(kUserBoundKvPrefixes.any(kSearchRecentsKey.startsWith), isTrue);
    });
  });

  test('a result and a shortcut open the same thing the same way', () {
    expect(
      (quickDestinationForTarget(QuickKind.task, 'T') as QuickPush).location,
      '/tasks/T',
    );
    expect(
      (quickDestinationForTarget(QuickKind.project, 'P') as QuickGo).location,
      '/projects/P',
    );
    expect(
      (quickDestinationForTarget(QuickKind.note, 'N') as QuickGo).location,
      '/notes/N',
    );
    expect(
      (quickDestinationForTarget(QuickKind.file, 'F') as QuickFileSheet).fileId,
      'F',
    );
  });

  group('globalSearchProvider', () {
    late AwDatabase db;
    late ProviderContainer container;
    const ws = 'W1';

    setUp(() {
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          taskScopeProvider.overrideWith(
            (ref) async => TaskScope.workspace(ws),
          ),
          activeWorkspaceIdProvider.overrideWith((ref) async => ws),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> task(
      String id,
      String title, {
      String status = 'open',
      String? description,
      List<String> tagIds = const [],
    }) async {
      await db
          .into(db.tasks)
          .insertOnConflictUpdate(
            taskCompanion({
              'id': id,
              'workspaceId': ws,
              'title': title,
              'status': status,
              'description': description,
            }),
          );
      await replaceTaskTags(db, id, tagIds);
    }

    Future<List<GlobalSearchGroup>> search(String q) =>
        container.read(globalSearchProvider(q).future);

    test('an empty query is no search at all', () async {
      expect(await search('   '), isEmpty);
    });

    test(
      'groups come in a fixed order, five rows each, with the total',
      () async {
        await db
            .into(db.tags)
            .insert(
              tagCompanion({
                'id': 'G1',
                'workspaceId': ws,
                'name': 'Rapor',
                'slug': 'rapor',
              }),
            );
        for (var i = 0; i < 7; i++) {
          await task('T$i', 'Rapor $i');
        }
        await task('TD', 'Rapor bitti', status: 'completed');
        await task('TC', 'Rapor iptal', status: 'cancelled');
        await task('TT', 'Alakasız', tagIds: ['G1']);
        await db
            .into(db.projects)
            .insert(
              projectCompanion({
                'id': 'P1',
                'workspaceId': ws,
                'name': 'Rapor projesi',
                'status': 'archived',
              }),
            );
        await db
            .into(db.notes)
            .insert(
              noteCompanion({
                'id': 'N1',
                'workspaceId': ws,
                'title': 'Notlar',
                'plainText': 'haftalık rapor taslağı',
              }),
            );
        await db
            .into(db.fileRows)
            .insert(
              fileCompanion({
                'id': 'F1',
                'workspaceId': ws,
                'targetType': 'workspace',
                'targetId': ws,
                'name': 'rapor.pdf',
                'mime': 'application/pdf',
              }),
            );

        final groups = await search('rapor');
        expect(groups.map((g) => g.kind), GlobalSearchKind.values);

        final tasks = groups.first;
        // 7 open + completed + tag hit; cancelled is out.
        expect(tasks.total, 9);
        expect(tasks.items, hasLength(kGlobalSearchGroupLimit));

        // Completed work is found, and marked.
        final all = await container
            .read(searchServiceProvider)
            .searchTasks(ws, 'rapor', statuses: kGlobalSearchTaskStatuses);
        expect(all.map((h) => h.id), contains('TD'));
        expect(all.map((h) => h.id), isNot(contains('TC')));
        final done = await resolveGlobalSearchItems(db, GlobalSearchKind.task, [
          'TD',
        ]);
        expect(done.single.done, isTrue);

        // A tag-tier hit says which tag (DESIGN S3).
        final tagHit = await resolveGlobalSearchItems(
          db,
          GlobalSearchKind.task,
          ['TT'],
          tiers: {'TT': 1},
          words: ['rapor'],
        );
        expect(tagHit.single.context, '#Rapor');

        final project = groups[1].items.single;
        expect(project.archived, isTrue);
        final note = groups[2].items.single;
        expect(note.context, contains('rapor'));
        expect(groups[3].items.single.title, '#Rapor');
        expect(groups[4].items.single.mime, 'application/pdf');
      },
    );
  });
}

extension on SearchRecent {
  SearchRecent withId(String id) => SearchRecent(kind, id);
}
