import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OPH-395 (E-26, A-36) — the app never calls itself "open source".
///
/// The licence is PolyForm Noncommercial (ADR-0024): source-available. The
/// server sheet said "AllisWell is open source — …" and the About box and the
/// web app's own meta said the same; a reader who checks the licence finds a
/// claim the app itself contradicts.
final _openSource = RegExp(
  r'open[\s-]source|açık\s+kaynak',
  caseSensitive: false,
);

Map<String, dynamic> _catalogue(String language) =>
    jsonDecode(File('assets/i18n/$language.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  for (final path in const [
    'assets/i18n/en.json',
    'assets/i18n/tr.json',
    'web/index.html',
    'web/manifest.json',
  ]) {
    test('$path never says "open source"', () {
      final hits = [
        for (final line in File(path).readAsLinesSync())
          if (_openSource.hasMatch(line)) line.trim(),
      ];
      expect(hits, isEmpty);
    });
  }

  test('the server sheet uses the A-36 text word for word', () {
    final tr = _catalogue('tr')['settings']['serverUrl']['body'];
    final en = _catalogue('en')['settings']['serverUrl']['body'];
    expect(
      tr,
      "AllisWell'i kendi sunucunda da çalıştırabilirsin. Uygulamayı buradan "
      'ona yönlendir. Sunucuyu değiştirmek oturumunu kapatır.',
    );
    expect(
      en,
      'You can also run AllisWell on your own server. Point this app at it '
      'here. Changing the server signs you out.',
    );
  });
}
