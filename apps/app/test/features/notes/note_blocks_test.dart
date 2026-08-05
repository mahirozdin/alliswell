import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/note_blocks.dart';

/// Round 16 #3: the delta → block mapping the PDF exporter renders from. Pure,
/// so every structural rule is pinned here rather than inside a PDF byte blob.
void main() {
  test('maps headings, quote and code, and merges consecutive code lines', () {
    final blocks = deltaToBlocks([
      {'insert': 'Başlık'},
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
      {'insert': 'Alt başlık'},
      {
        'insert': '\n',
        'attributes': {'header': 2},
      },
      {'insert': 'Derin başlık'},
      {
        'insert': '\n',
        'attributes': {'header': 4},
      },
      {'insert': 'Alıntı'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': 'satır bir'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
      {'insert': 'satır iki'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
      {'insert': '\n'},
    ]);

    expect(blocks.map((b) => b.kind).toList(), [
      NoteBlockKind.heading1,
      NoteBlockKind.heading2,
      // Deeper than the toolbar offers still renders AS a heading.
      NoteBlockKind.heading3,
      NoteBlockKind.quote,
      NoteBlockKind.code,
    ]);
    // Two code lines, ONE panel.
    expect(blocks.last.text, 'satır bir\nsatır iki');
  });

  test('numbers ordered items and resets the counter when interrupted', () {
    List<Map<String, dynamic>> item(String text, String list) => [
      {'insert': text},
      {
        'insert': '\n',
        'attributes': {'list': list},
      },
    ];

    final blocks = deltaToBlocks([
      ...item('bir', 'ordered'),
      ...item('iki', 'ordered'),
      {'insert': 'araya giren paragraf\n'},
      ...item('yeniden bir', 'ordered'),
      ...item('madde', 'bullet'),
      {'insert': '\n'},
    ]);

    expect(
      blocks
          .map((b) => '${b.kind.name}:${b.ordinal ?? '-'}:${b.text}')
          .toList(),
      [
        'ordered:1:bir',
        'ordered:2:iki',
        'paragraph:-:araya giren paragraf',
        // The paragraph broke the run, so numbering starts over.
        'ordered:1:yeniden bir',
        'bullet:-:madde',
      ],
    );
  });

  test('carries checklist state and inline attributes', () {
    final blocks = deltaToBlocks([
      {'insert': 'yapıldı'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': 'yapılacak'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {'insert': 'düz '},
      {
        'insert': 'kalın',
        'attributes': {'bold': true},
      },
      {'insert': ' ve '},
      {
        'insert': 'bağlantı',
        'attributes': {'link': 'https://alliswell.space'},
      },
      {'insert': '\n\n'},
    ]);

    expect(blocks[0].kind, NoteBlockKind.checked);
    expect(blocks[1].kind, NoteBlockKind.unchecked);
    final spans = blocks[2].spans;
    expect(spans.map((s) => s.text).toList(), [
      'düz ',
      'kalın',
      ' ve ',
      'bağlantı',
    ]);
    expect(spans[1].bold, isTrue);
    expect(spans[3].link, 'https://alliswell.space');
    // A link must not also read as bold just because it is styled.
    expect(spans[3].bold, isFalse);
  });

  test('an embed becomes its own figure and leaves no blank line behind', () {
    final blocks = deltaToBlocks([
      {'insert': 'önce yazı'},
      {
        'insert': {'image': 'alliswell://file/01HZY0000000000000000000AB'},
      },
      {'insert': '\nsonra yazı'},
      {
        'insert': {'video': 'https://example.test/clip.mp4'},
      },
      {'insert': '\n'},
      // Shapes we do not understand drop rather than printing an empty box.
      {
        'insert': {'mystery': 'x'},
      },
      {'insert': '\n'},
    ]);

    expect(blocks.map((b) => b.kind).toList(), [
      NoteBlockKind.paragraph,
      NoteBlockKind.image,
      NoteBlockKind.paragraph,
      NoteBlockKind.attachment,
    ]);
    expect(blocks[1].source, 'alliswell://file/01HZY0000000000000000000AB');
    expect(blocks[3].source, 'https://example.test/clip.mp4');
    // The newline that terminates the embed's OWN line must not become an
    // empty paragraph — that is a visible gap under every image.
    expect(
      blocks.where((b) => b.text.trim().isEmpty && b.source == null),
      isEmpty,
    );
  });

  test(
    'drops the trailing blank paragraphs every Quill document ends with',
    () {
      expect(
        deltaToBlocks([
          {'insert': 'tek satır\n\n\n\n'},
        ]).map((b) => b.text).toList(),
        ['tek satır'],
      );

      // An empty document exports as an empty body, not as a page of blanks.
      expect(
        deltaToBlocks([
          {'insert': '\n'},
        ]),
        isEmpty,
      );
    },
  );
}
