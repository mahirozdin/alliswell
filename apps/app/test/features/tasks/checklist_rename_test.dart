import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../projects/fake_api.dart';
import 'tasks_flow_test.dart' show signedInAppWith, wideSurface, isoAt;

/// OPH-416 — issue #38: a checklist item's text is editable in place; only
/// the checkbox ticks it. Before, the whole row was a CheckboxListTile, so a
/// tap on the words toggled the item and there was no way to fix a typo.
void main() {
  group('TaskStore.renameChecklistItem', () {
    late AwDatabase db;
    late TaskStore store;

    setUp(() {
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
      store = TaskStore(db, () {});
    });
    tearDown(() => db.close());

    Future<(String, String)> seed() async {
      final taskId = await store.create('W1', {'title': 'Alışveriş'});
      await store.addChecklistItem(taskId, 'süt');
      final item = await db.select(db.checklistItems).getSingle();
      await db.delete(db.pendingMutations).go();
      return (taskId, item.id);
    }

    test('updates the replica and enqueues an update carrying only the '
        'trimmed title', () async {
      final (taskId, itemId) = await seed();
      await store.renameChecklistItem(taskId, itemId, '  yulaf sütü ');

      final item = await db.select(db.checklistItems).getSingle();
      expect(item.title, 'yulaf sütü');
      expect(item.isDone, isFalse, reason: 'renaming never ticks');

      final row = await db.select(db.pendingMutations).getSingle();
      expect(row.entityType, 'checklist_item');
      expect(row.entityId, itemId);
      expect(row.operation, 'update');
      expect(jsonDecode(row.patchJson!), {'title': 'yulaf sütü'});
    });

    test('an empty or unchanged title writes nothing', () async {
      final (taskId, itemId) = await seed();
      await store.renameChecklistItem(taskId, itemId, '   ');
      await store.renameChecklistItem(taskId, itemId, 'süt');
      expect((await db.select(db.checklistItems).getSingle()).title, 'süt');
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    });

    test('a title over the server limit (500) is clamped', () async {
      final (taskId, itemId) = await seed();
      await store.renameChecklistItem(taskId, itemId, 'a' * 600);
      final row = await db.select(db.pendingMutations).getSingle();
      final patch = jsonDecode(row.patchJson!) as Map<String, dynamic>;
      expect((patch['title'] as String).length, 500);
    });
  });

  group('task detail checklist row', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Future<FakeApi> openDetail(WidgetTester tester) async {
      await wideSurface(tester);
      // Tall enough that the checklist card is built without scrolling.
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      final api = FakeApi()
        ..seedTask(
          title: 'Listeli iş',
          dueAt: isoAt(today.add(const Duration(days: 2, hours: 12))),
          checklist: [
            {
              'id': 'C1'.padRight(26, '0'),
              'title': 'süt',
              'isDone': false,
              'sortOrder': 0,
              'revision': 1,
            },
          ],
        );
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listeli iş'));
      await tester.pumpAndSettle();
      return api;
    }

    final itemId = 'C1'.padRight(26, '0');
    Finder editor() => find.byKey(Key('checklist-item-edit-$itemId'));
    List<Map<String, dynamic>> itemMutations(FakeApi api) => api.pushedMutations
        .where((m) => m['entityType'] == 'checklist_item')
        .toList();
    Map<String, dynamic> serverItem(FakeApi api) =>
        ((api.tasks.single['checklist'] as List).single as Map)
            .cast<String, dynamic>();

    testWidgets('tapping the text edits it and does not tick the item', (
      tester,
    ) async {
      final api = await openDetail(tester);
      await tester.tap(find.byKey(Key('checklist-item-title-$itemId')));
      await tester.pumpAndSettle();

      expect(editor(), findsOneWidget);
      final field = tester.widget<TextField>(editor());
      expect(field.focusNode?.hasFocus, isTrue, reason: 'cursor is in it');
      expect(itemMutations(api), isEmpty, reason: 'a tap on text never ticks');

      await tester.enterText(editor(), '  yulaf sütü  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(editor(), findsNothing);
      expect(serverItem(api)['title'], 'yulaf sütü');
      expect(serverItem(api)['isDone'], isFalse);
      final patches = itemMutations(api).map((m) => m['patch']).toList();
      expect(patches, [
        {'title': 'yulaf sütü'},
      ]);
      expect(find.text('yulaf sütü'), findsOneWidget);
    });

    testWidgets('an empty title restores the old one and writes nothing', (
      tester,
    ) async {
      final api = await openDetail(tester);
      await tester.tap(find.byKey(Key('checklist-item-title-$itemId')));
      await tester.pumpAndSettle();
      await tester.enterText(editor(), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(editor(), findsNothing);
      expect(find.text('süt'), findsOneWidget);
      expect(itemMutations(api), isEmpty);
    });

    testWidgets('Escape cancels the edit', (tester) async {
      final api = await openDetail(tester);
      await tester.tap(find.byKey(Key('checklist-item-title-$itemId')));
      await tester.pumpAndSettle();
      await tester.enterText(editor(), 'vazgeçilen');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(editor(), findsNothing);
      expect(find.text('süt'), findsOneWidget);
      expect(find.text('vazgeçilen'), findsNothing);
      expect(itemMutations(api), isEmpty);
    });

    testWidgets('the checkbox ticks the item without opening the editor', (
      tester,
    ) async {
      final api = await openDetail(tester);
      final box = find.byKey(Key('checklist-item-check-$itemId'));
      expect(tester.getSize(box).height, greaterThanOrEqualTo(44));
      await tester.tap(box);
      await tester.pumpAndSettle();

      expect(editor(), findsNothing);
      expect(serverItem(api)['isDone'], isTrue);
      expect(itemMutations(api).map((m) => m['patch']).toList(), [
        {'isDone': true},
      ]);
    });
  });
}
