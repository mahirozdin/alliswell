import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/fold.dart';

/// ADR-0013 — the one fold. These pairs are the product promise from
/// BLUEPRINT §12.10; the API's `src/lib/fold.js` must agree (parity fixture
/// arrives with OPH-167's engine work).
void main() {
  test('Turkish equivalence classes fold to one form', () {
    expect(foldSearchText('Çay'), 'cay');
    expect(foldSearchText('cay'), 'cay');
    expect(foldSearchText('ISI'), 'isi'); // I → i (not Turkish casing!)
    expect(
      foldSearchText('ısı'),
      'isi',
    ); // dotless ı → i — nothing engine-side does this
    expect(foldSearchText('İstanbul'), 'istanbul'); // İ → i
    expect(foldSearchText('ÜLKÜ'), 'ulku');
    expect(foldSearchText('göğüş'), 'gogus');
    expect(foldSearchText('şeker'), 'seker');
    expect(foldSearchText('kâğıt'), 'kagit');
  });

  test('case-insensitivity is total across the mapped range', () {
    expect(foldSearchText('ÇAĞRI Ölçer'), foldSearchText('çağrı ölçer'));
    expect(foldSearchText('IŞIK'), foldSearchText('ışık'));
  });

  test('common European accents fold too', () {
    expect(foldSearchText('café'), 'cafe');
    expect(foldSearchText('Großmann'), 'grossmann');
    expect(foldSearchText('naïve'), 'naive');
    expect(foldSearchText('Łódź'), 'lodz');
  });

  test('whitespace collapses and trims', () {
    expect(foldSearchText('  çok   boşluk  '), 'cok bosluk');
  });

  test('non-Latin passes through casefolded, untouched otherwise', () {
    expect(foldSearchText('Дом 123'), 'дом 123');
  });

  test('matches the cross-stack parity fixture (fold.js twin)', () {
    final fixture =
        jsonDecode(File('test/fixtures/fold_parity.json').readAsStringSync())
            as Map<String, dynamic>;
    final pairs = (fixture['pairs'] as Map<String, dynamic>)
        .cast<String, String>();
    for (final entry in pairs.entries) {
      expect(
        foldSearchText(entry.key),
        entry.value,
        reason: 'fold(${entry.key})',
      );
      // Idempotence: folding folded text changes nothing.
      expect(foldSearchText(entry.value), entry.value);
    }
  });
}
