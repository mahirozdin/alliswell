import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/gateway.dart';

/// Every alarm problem has its words in BOTH catalogues (#19).
///
/// The banner, the Settings row and the fix sheet build these keys from the
/// enum's name (`'alarm.problem.${problem.name}'`), which `check:i18n` cannot
/// see — it reads literals. And a widget test cannot see a missing Turkish
/// line either, because `.tr()` falls back to English. So the files are read
/// here directly: a new problem fails this until both languages can say it.
Map<String, dynamic> _catalogue(String language) =>
    jsonDecode(File('assets/i18n/$language.json').readAsStringSync())
        as Map<String, dynamic>;

Object? _lookup(Map<String, dynamic> catalogue, String key) {
  Object? node = catalogue;
  for (final part in key.split('.')) {
    if (node is! Map<String, dynamic>) return null;
    node = node[part];
  }
  return node;
}

void main() {
  for (final language in const ['en', 'tr']) {
    test('$language can name every alarm problem and its fix', () {
      final catalogue = _catalogue(language);
      final keys = [
        for (final problem in AlarmProblem.values) ...[
          'alarm.problem.${problem.name}',
          'alarm.fix.${problem.name}',
        ],
        // The sheet's three buttons.
        'alarm.fix.open',
        'alarm.fix.allow',
        'alarm.fix.checkAgain',
      ];
      for (final key in keys) {
        final value = _lookup(catalogue, key);
        expect(value, isA<String>(), reason: '$language: $key');
        expect((value as String).trim(), isNotEmpty, reason: '$language: $key');
      }
    });
  }
}
