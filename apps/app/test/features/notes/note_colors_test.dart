import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/delta_markdown.dart';
import 'package:alliswell/src/features/notes/data/note_colors.dart';

/// OPH-259 — a highlight stores the NAME of a colour, and the theme decides
/// what it looks like (DESIGN §33 R4).
///
/// ADR-0033 took half of this away with the rich editor. TEXT colour is gone:
/// GFM has no syntax for it, so `aw:text-*` had nowhere to live once markdown
/// became the only canonical form (§33 R6 had already parked it, with that
/// reason). The HIGHLIGHT survived, because markdown does have a mark —
/// `==like this==` — and the renderer draws it from these same names.
///
/// The rule this replaces promised twelve text colours legible on both themes
/// from one hex each. Measured, that is impossible: the surface under the text
/// and the ink over a highlight both move with the theme, and no single value
/// serves both. These tests pin the mechanism that makes it possible instead.
void main() {
  group('names, not hexes', () {
    test('every colour resolves differently per theme', () {
      for (final color in kAwNoteColors) {
        expect(
          color.forBrightness(Brightness.light),
          isNot(color.forBrightness(Brightness.dark)),
          reason:
              '${color.id} would be the same value in both themes, which '
              'is exactly what cannot be made readable',
        );
      }
    });

    test('ids are unique — the palette is one map', () {
      final ids = {for (final c in kAwNoteColors) c.id};
      expect(ids, hasLength(kAwNoteColors.length));
    });

    test('a value that is not ours resolves to nothing, not to black', () {
      // An older build, or another editor, may have written a raw hex.
      expect(awResolveNoteColor('#FF0000', Brightness.light), isNull);
      expect(awResolveNoteColor(null, Brightness.light), isNull);
    });
  });

  group('the conversion carries a highlight', () {
    test('delta → markdown writes the mark markdown has', () {
      final markdown = deltaToMarkdown([
        {
          'insert': 'dikkat',
          'attributes': {'background': 'aw:mark-yellow'},
        },
        {'insert': '\n'},
      ]);

      expect(markdown.trim(), '==dikkat==');
    });

    test('the default highlight is a name the themes can resolve', () {
      expect(
        awNoteColorById(kAwDefaultHighlightId),
        isNotNull,
        reason: 'the default must be a colour the themes can resolve',
      );
    });
  });

  group('the stock hex dialog is gone for good', () {
    test('there is no colour picker left to leak a hex field', () {
      // The complaint that started §33: flutter_quill's own colour dialog
      // carried a hex TEXT FIELD, which round 1 forbade, so OPH-259 replaced
      // both buttons with ours. ADR-0033 removed the package entirely — the
      // promise is now kept by the dependency not existing, which is the
      // strongest form it can take. What remains is that every highlight the
      // renderer can draw is a NAME.
      for (final color in kAwNoteHighlightColors) {
        expect(color.id, startsWith('aw:'));
        expect(color.id, isNot(startsWith('#')));
      }
    });
  });
}
