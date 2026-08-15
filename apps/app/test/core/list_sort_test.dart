import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/list_sort.dart';

/// OPH-258 — how a list says which way it is ordered (DESIGN §34).
void main() {
  const choices = [
    AwSortChoice(id: 'updated', labelKey: 'sort.updated'),
    AwSortChoice(id: 'created', labelKey: 'sort.created'),
    AwSortChoice(
      id: 'title',
      labelKey: 'sort.title',
      descendingByDefault: false,
    ),
  ];

  group('the persisted string', () {
    test('round-trips field and direction', () {
      const state = AwSortState('created', descending: false);
      expect(state.encode(), 'created:asc');
      expect(AwSortState.parse('created:asc', choices), state);
    });

    test('an unknown field falls back to the first choice', () {
      // Someone downgrades, or a preference outlives the option that wrote it.
      final parsed = AwSortState.parse('whatever:desc', choices);
      expect(parsed.id, 'updated');
    });

    test('a bare field takes that field\'s natural direction', () {
      expect(AwSortState.parse('title', choices).descending, isFalse);
      expect(AwSortState.parse('updated', choices).descending, isTrue);
      expect(AwSortState.parse('', choices).id, 'updated');
    });
  });

  group('choosing and reversing', () {
    test('a new field arrives in its natural direction', () {
      // Dates want newest first; names want A→Z. Carrying "descending" over
      // from a date onto a title would open the list at Z.
      const fromDate = AwSortState('updated');
      final toTitle = fromDate.select(choices[2]);
      expect(toTitle.id, 'title');
      expect(toTitle.descending, isFalse);
    });

    test('re-picking the field already in use keeps the direction', () {
      const reversedDate = AwSortState('updated', descending: false);
      expect(reversedDate.select(choices[0]), reversedDate);
    });

    test('reverse flips only the direction', () {
      expect(
        const AwSortState('title', descending: false).reversed(),
        const AwSortState('title'),
      );
    });
  });

  group('the comparator', () {
    int byLength(String a, String b) => a.length.compareTo(b.length);

    test('ascending is the comparator as written', () {
      final sorted = ['ccc', 'a', 'bb']
        ..sort(const AwSortState('x', descending: false).comparator(byLength));
      expect(sorted, ['a', 'bb', 'ccc']);
    });

    test('descending is the same comparator, read backwards', () {
      final sorted = ['a', 'ccc', 'bb']
        ..sort(const AwSortState('x').comparator(byLength));
      expect(sorted, ['ccc', 'bb', 'a']);
    });
  });
}
