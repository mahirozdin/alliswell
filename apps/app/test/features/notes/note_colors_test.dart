import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/delta_markdown.dart';
import 'package:alliswell/src/features/notes/data/markdown_delta.dart';
import 'package:alliswell/src/features/notes/data/note_colors.dart';

/// OPH-259 — a note stores the NAME of a colour, and the theme decides what it
/// looks like (DESIGN §33 R4).
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

    test('the palette flutter_quill resolves through covers every name', () {
      final light = awNoteColorPalette(Brightness.light);
      final dark = awNoteColorPalette(Brightness.dark);

      for (final color in kAwNoteColors) {
        expect(light[color.id], color.light);
        expect(dark[color.id], color.dark);
      }
      expect(light, hasLength(kAwNoteColors.length));
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

    test('markdown → delta gives it a NAME, never a hex', () {
      final delta = markdownToDelta('==dikkat==');
      final op = delta.firstWhere(
        (op) => (op['attributes'] as Map?)?.containsKey('background') ?? false,
      );

      expect(op['insert'], 'dikkat');
      expect((op['attributes'] as Map)['background'], kAwDefaultHighlightId);
      expect(
        awNoteColorById(kAwDefaultHighlightId),
        isNotNull,
        reason: 'the default must be a colour the themes can resolve',
      );
    });

    test('a highlight survives the round trip', () {
      const original = [
        {
          'insert': 'dikkat',
          'attributes': {'background': kAwDefaultHighlightId},
        },
        {'insert': '\n'},
      ];

      final back = markdownToDelta(deltaToMarkdown(original));
      final op = back.firstWhere(
        (op) => (op['attributes'] as Map?)?.containsKey('background') ?? false,
      );

      expect(op['insert'], 'dikkat');
      expect((op['attributes'] as Map)['background'], kAwDefaultHighlightId);
    });
  });

  group('the stock hex dialog is gone for good', () {
    test('the toolbar config disables both colour buttons', () {
      // The complaint that started §33: flutter_quill's own dialog carries a
      // hex TEXT FIELD, which round 1 forbade. A config test rather than a
      // widget test because this is a promise about configuration — and it
      // fails the moment someone flips either flag back.
      const config = QuillSimpleToolbarConfig(
        showColorButton: false,
        showBackgroundColorButton: false,
      );

      expect(config.showColorButton, isFalse);
      expect(config.showBackgroundColorButton, isFalse);
      // The defaults are ON, which is why they must be written out.
      expect(const QuillSimpleToolbarConfig().showColorButton, isTrue);
    });
  });
}
