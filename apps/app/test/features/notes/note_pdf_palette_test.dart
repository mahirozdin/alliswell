// Round 19b guard: the page's palette must be the app's LIGHT theme, value for
// value. Eyeballing a "close enough" green is the same class of mismatch this
// round exists to remove, just smaller.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alliswell/src/features/notes/data/note_print_style.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

void main() {
  test('the PDF palette is the light theme, not an approximation', () {
    final scheme = buildAwTheme(Brightness.light).colorScheme;
    const tokens = AwTokens.light;
    // The print palette both writers (PDF, DOCX) draw with. If a token moves,
    // this fails and names which one — the export has no other way to notice.
    expect(
      tokens.success.toARGB32(),
      NotePrintPalette.success,
      reason: 'success',
    );
    expect(
      tokens.warning.toARGB32(),
      NotePrintPalette.warning,
      reason: 'warning',
    );
    expect(
      scheme.secondary.toARGB32(),
      NotePrintPalette.secondary,
      reason: 'secondary',
    );
    expect(scheme.error.toARGB32(), NotePrintPalette.error, reason: 'error');
    expect(
      scheme.primary.toARGB32(),
      NotePrintPalette.accent,
      reason: 'accent',
    );
  });

  test('an alert tint is its edge at 8 % on white paper', () {
    expect(NotePrintPalette.calloutTint('warning'), 0xFFFBF4EB);
    expect(NotePrintPalette.hex(NotePrintPalette.ink), '0F1B2E');
  });
}
