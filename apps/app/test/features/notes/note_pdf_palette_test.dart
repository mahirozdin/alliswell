// Round 19b guard: the page's palette must be the app's LIGHT theme, value for
// value. Eyeballing a "close enough" green is the same class of mismatch this
// round exists to remove, just smaller.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

void main() {
  test('the PDF palette is the light theme, not an approximation', () {
    final scheme = buildAwTheme(Brightness.light).colorScheme;
    const tokens = AwTokens.light;
    // Mirrors the constants in note_pdf.dart. If a token moves, this fails and
    // names which one — the export has no other way to notice.
    expect(tokens.success.toARGB32(), 0xFF0D7A33, reason: '_success');
    expect(tokens.warning.toARGB32(), 0xFFC77700, reason: '_warning');
    expect(scheme.secondary.toARGB32(), 0xFF5A50E0, reason: '_secondary');
    expect(scheme.error.toARGB32(), 0xFFD70015, reason: '_error');
    expect(scheme.primary.toARGB32(), 0xFF0A5CFF, reason: '_accent');
  });
}
