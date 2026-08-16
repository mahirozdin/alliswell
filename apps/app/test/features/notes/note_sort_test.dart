import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/list_sort.dart';
import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/data/note_store.dart';

import '../projects/fake_api.dart';
import 'notes_flow_test_support.dart';

/// OPH-258 — the notes list is ordered by when you last touched it (§34 L1),
/// and the choice lives in the app bar without costing a row (L2/L3).
NoteRow _note({
  required String id,
  required String title,
  DateTime? created,
  DateTime? updated,
}) => NoteRow(
  id: id,
  workspaceId: 'w1',
  title: title,
  snippet: '',
  isPinned: false,
  isArchived: false,
  revision: 1,
  createdAt: created,
  updatedAt: updated,
);

extension on NoteRow {
  NoteRow copyPinned() => NoteRow(
    id: id,
    workspaceId: workspaceId,
    title: title,
    snippet: snippet,
    isPinned: true,
    isArchived: isArchived,
    revision: revision,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('the comparator (§34 L1/L3)', () {
    final oldest = _note(
      id: 'C',
      title: 'ırmak',
      created: DateTime.utc(2026, 1, 1),
      updated: DateTime.utc(2026, 8, 9),
    );
    final middle = _note(
      id: 'B',
      title: 'İzmir',
      created: DateTime.utc(2026, 5, 5),
      updated: DateTime.utc(2026, 8, 1),
    );
    final newest = _note(
      id: 'A',
      title: 'ada',
      created: DateTime.utc(2026, 7, 7),
      updated: DateTime.utc(2026, 8, 5),
    );

    List<String> idsFor(String encoded) =>
        ([middle, newest, oldest]..sort(
              noteSortComparator(AwSortState.parse(encoded, kNoteSortChoices)),
            ))
            .map((n) => n.id)
            .toList();

    test('the default is last edited, newest first', () {
      // Not creation order — which is what `id DESC` gave, while the row
      // itself displayed the edited date.
      expect(idsFor('updated:desc'), ['C', 'A', 'B']);
    });

    test('created order is a different order, and available', () {
      expect(idsFor('created:desc'), ['A', 'B', 'C']);
    });

    test('title order folds dotted and dotless i together', () {
      // 'ada' → 'ırmak' → 'İzmir'. Both i's fold to plain `i` (ADR-0013), so
      // they sort as one letter and `r` before `z` decides — which is what
      // makes the two words neighbours instead of strangers. A raw
      // `toLowerCase()` would strand 'İzmir' on a combining dot and push
      // 'ırmak' past 'z' entirely.
      expect(idsFor('title:asc'), ['A', 'C', 'B']);
    });

    test('reversing flips the whole list', () {
      expect(idsFor('updated:asc'), ['B', 'A', 'C']);
    });

    test('starred notes are a group above the list, whatever the sort', () {
      // Owner's call (2026-08-16): §34 L5 had said the star must not disturb
      // the order. It was wrong about what a star means — pinning is how
      // someone keeps a note in sight, and an order that can bury it makes the
      // star a decoration.
      final pinned = _note(
        id: 'P',
        title: 'zzz en eski',
        created: DateTime.utc(2020, 1, 1),
        updated: DateTime.utc(2020, 1, 1),
      ).copyPinned();

      for (final encoded in ['updated:desc', 'created:desc', 'title:asc']) {
        final sorted = [newest, middle, pinned, oldest]
          ..sort(
            noteSortComparator(AwSortState.parse(encoded, kNoteSortChoices)),
          );
        expect(
          sorted.first.id,
          'P',
          reason: 'the star outranks $encoded, which it did not before',
        );
      }
    });

    test('inside a group the chosen order still decides', () {
      final pinnedOld = _note(
        id: 'P1',
        title: 'a',
        updated: DateTime.utc(2026, 1, 1),
      ).copyPinned();
      final pinnedNew = _note(
        id: 'P2',
        title: 'b',
        updated: DateTime.utc(2026, 8, 1),
      ).copyPinned();

      final sorted = [pinnedOld, pinnedNew, newest]
        ..sort(noteSortComparator(const AwSortState('updated')));
      expect(sorted.map((n) => n.id), ['P2', 'P1', 'A']);
    });

    test('a note with no dates sorts last, and stays put', () {
      final dateless = _note(id: 'Z', title: 'tarihsiz');
      final sorted = [dateless, newest]
        ..sort(noteSortComparator(const AwSortState('updated')));
      expect(sorted.map((n) => n.id), ['A', 'Z']);
    });
  });

  group('the app bar menu (§34 L2)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await localKv.remove('alliswell_notes_sort');
      await localKv.remove('alliswell_notes_view_mode');
    });

    testWidgets('picking an order re-lays the list and is remembered', (
      tester,
    ) async {
      // Seeded newest-created last, so creation order and title order differ.
      final api = FakeApi()
        ..seedNote(title: 'Bir')
        ..seedNote(title: 'Üç')
        ..seedNote(title: 'İki');

      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openNotes(tester);

      await tester.tap(find.byKey(const Key('list-sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort-option-title')));
      await tester.pumpAndSettle();

      expect(titlesInOrder(tester), ['Bir', 'İki', 'Üç']);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('alliswell_notes_sort'),
        'title:asc',
        reason: 'a viewing preference outlives the screen that set it',
      );
    });

    testWidgets('reverse flips the order that is already chosen', (
      tester,
    ) async {
      final api = FakeApi()
        ..seedNote(title: 'Bir')
        ..seedNote(title: 'Üç')
        ..seedNote(title: 'İki');

      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openNotes(tester);

      await tester.tap(find.byKey(const Key('list-sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort-option-title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('list-sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort-reverse')));
      await tester.pumpAndSettle();

      expect(titlesInOrder(tester), ['Üç', 'İki', 'Bir']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('alliswell_notes_sort'), 'title:desc');
    });
  });
}
