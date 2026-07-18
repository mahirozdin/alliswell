import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/delta_markdown.dart';
import 'package:alliswell/src/features/notes/data/note.dart';

void main() {
  test('converts headers, inline styles, links and lists', () {
    final markdown = deltaToMarkdown([
      {'insert': 'Başlık'},
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
      {'insert': 'Normal ve '},
      {
        'insert': 'kalın',
        'attributes': {'bold': true},
      },
      {'insert': ' ve '},
      {
        'insert': 'italik',
        'attributes': {'italic': true},
      },
      {'insert': ' ve '},
      {
        'insert': 'bağlantı',
        'attributes': {'link': 'https://alliswell.dev'},
      },
      {'insert': '\nMadde bir'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': 'Yapıldı'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
    ]);

    expect(markdown.split('\n'), [
      '# Başlık',
      'Normal ve **kalın** ve _italik_ ve [bağlantı](https://alliswell.dev)',
      '- Madde bir',
      '- [x] Yapıldı',
    ]);
  });

  test('merges consecutive code lines into one fenced block, renders embeds inline', () {
    final markdown = deltaToMarkdown([
      {'insert': 'const a = 1;'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
      {'insert': 'const b = 2;'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
      // Since OPH-156 image embeds render as markdown images (server parity —
      // they used to be dropped); attachment coverage: note_media_test.dart.
      {
        'insert': {'image': 'x.png'},
      },
      {'insert': 'son satır\n'},
    ]);

    expect(markdown.split('\n'), [
      '```',
      'const a = 1;',
      'const b = 2;',
      '```',
      '![](x.png)son satır',
    ]);
  });

  test('empty and trailing-newline documents come out clean', () {
    expect(deltaToMarkdown([]), '');
    expect(
      deltaToMarkdown([
        {'insert': 'tek satır\n'},
      ]),
      'tek satır',
    );
  });

  test('NoteDetail.fromJson carries delta, markdown and links', () {
    final note = NoteDetail.fromJson({
      'id': 'n1',
      'workspaceId': 'ws1',
      'title': 'Not',
      'snippet': 'kısa',
      'isPinned': true,
      'isArchived': false,
      'revision': 2,
      'contentDelta': [
        {'insert': 'içerik\n'},
      ],
      'contentMarkdown': 'içerik',
      'links': [
        {'id': 'l1', 'entityType': 'task', 'entityId': 't1'},
      ],
    });
    expect(note.isPinned, isTrue);
    expect(note.contentDelta, hasLength(1));
    expect(note.links.single.entityType, 'task');
  });
}
