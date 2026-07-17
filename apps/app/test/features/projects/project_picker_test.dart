import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/ui/project_picker.dart';

Project _p(String id, String name, {String status = 'active'}) => Project(
  id: id,
  workspaceId: 'W1',
  name: name,
  colorRgb: '#2563EB',
  status: status,
  sortOrder: 0,
  isFavorite: false,
  revision: 1,
);

String _labelOf(DropdownMenuItem<String?> item) {
  final row = item.child as Row;
  final flexible = row.children.whereType<Flexible>().first;
  return (flexible.child as Text).data!;
}

void main() {
  test('always leads with a No project entry', () {
    final items = projectDropdownItems(const []);
    expect(items, hasLength(1));
    expect(items.single.value, isNull);
  });

  test('lists active projects after No project', () {
    final items = projectDropdownItems([_p('P1', 'Alpha'), _p('P2', 'Beta')]);
    expect(items.map((i) => i.value), [null, 'P1', 'P2']);
  });

  test('hides archived projects', () {
    final items = projectDropdownItems([
      _p('P1', 'Alpha'),
      _p('P2', 'Eski', status: 'archived'),
    ]);
    expect(items.map((i) => i.value), [null, 'P1']);
  });

  test('keeps an archived project as the current value, suffixed', () {
    final items = projectDropdownItems([
      _p('P1', 'Alpha'),
      _p('P2', 'Eski', status: 'archived'),
    ], currentValue: 'P2');
    expect(items.map((i) => i.value), [null, 'P1', 'P2']);
    final archived = items.firstWhere((i) => i.value == 'P2');
    expect(_labelOf(archived), 'Eski (archived)');
    // An active project keeps its plain name.
    expect(_labelOf(items.firstWhere((i) => i.value == 'P1')), 'Alpha');
  });
}
