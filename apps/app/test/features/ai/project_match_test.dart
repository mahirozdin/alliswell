import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/project_match.dart';

/// OPH-222 — the Dart half of the project-match parity pair. The JS half
/// (apps/api/test/unit/ai-project-match.test.js) runs the SAME fixture; change
/// one side alone and the other fails (the fold_parity model).
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/project_match_parity.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final names = (fixture['projects'] as List).cast<String>();
  final projects = [
    for (var i = 0; i < names.length; i++)
      ProjectRef(id: 'P$i', name: names[i]),
  ];
  final byName = {for (final p in projects) p.name: p};

  for (final testCase
      in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test(
      '"${testCase['query']}" → ${testCase['tier']} (${testCase['note']})',
      () {
        final result = matchProject(testCase['query'] as String, projects);
        expect(result.tier, testCase['tier']);
        expect(
          result.candidates.map((c) => c.name).toList(),
          (testCase['candidates'] as List).cast<String>(),
        );
        final expected = testCase['match'] as String?;
        if (expected == null) {
          expect(result.match, isNull);
        } else {
          expect(result.match, byName[expected]);
        }
      },
    );
  }
}
