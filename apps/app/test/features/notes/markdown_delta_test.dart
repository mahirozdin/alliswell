import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/delta_markdown.dart';
import 'package:alliswell/src/features/notes/data/markdown_delta.dart';

/// Round 16 follow-up — markdown → delta, the inverse of `deltaToMarkdown`.
///
/// The strongest test here is the ROUND TRIP: the two converters are written
/// against each other, so a delta that survives delta→md→delta unchanged pins
/// both at once. Hand-made fixtures only cover what the author thought of.
void main() {
  group('block structure', () {
    test('headings, quote, lists and checklists', () {
      final delta = markdownToDelta(
        '# Başlık\n'
        '## Alt başlık\n'
        'Düz paragraf.\n'
        '> Alıntı satırı\n'
        '- madde bir\n'
        '- madde iki\n'
        '1. sıralı bir\n'
        '2. sıralı iki\n'
        '- [x] yapıldı\n'
        '- [ ] yapılacak\n',
      );

      // Read it back as markdown: if the block attributes landed correctly the
      // text comes out the way it went in.
      expect(
        deltaToMarkdown(delta),
        '# Başlık\n'
        '## Alt başlık\n'
        'Düz paragraf.\n'
        '> Alıntı satırı\n'
        '- madde bir\n'
        '- madde iki\n'
        '1. sıralı bir\n'
        '1. sıralı iki\n'
        '- [x] yapıldı\n'
        '- [ ] yapılacak',
      );
    });

    test('a fenced block is literal — its markers are not markup', () {
      final delta = markdownToDelta(
        'önce\n'
        '```dart\n'
        '# bu başlık DEĞİL\n'
        '- bu madde DEĞİL\n'
        '```\n'
        'sonra\n',
      );

      final codeLines = delta
          .where((op) => (op['attributes'] as Map?)?['code-block'] == true)
          .length;
      expect(codeLines, 2);
      expect(deltaToMarkdown(delta), contains('# bu başlık DEĞİL'));
      // …and it stayed INSIDE the fence rather than becoming a real heading.
      expect(
        delta.any(
          (op) =>
              op['insert'] == '\n' &&
              (op['attributes'] as Map?)?['header'] != null,
        ),
        isFalse,
      );
    });

    test('a horizontal rule survives as a line instead of disappearing', () {
      final delta = markdownToDelta('bir\n---\niki\n');
      expect(deltaToMarkdown(delta), 'bir\n———\niki');
    });
  });

  group('inline', () {
    test('bold, italic, strike, code and links', () {
      final delta = markdownToDelta(
        'düz **kalın** ve _italik_ ve ~~üstü çizili~~ ve `kod` ve '
        '[bağlantı](https://alliswell.space)\n',
      );

      Map<String, dynamic>? attrs(String text) =>
          delta.cast<Map<String, dynamic>>().firstWhere(
                (op) => op['insert'] == text,
              )['attributes']
              as Map<String, dynamic>?;

      expect(attrs('kalın'), {'bold': true});
      expect(attrs('italik'), {'italic': true});
      expect(attrs('üstü çizili'), {'strike': true});
      expect(attrs('kod'), {'code': true});
      expect(attrs('bağlantı'), {'link': 'https://alliswell.space'});
    });

    test('code wins over emphasis inside it', () {
      final delta = markdownToDelta('`**yıldızlar**` düz\n');
      expect(delta.first, {
        'insert': '**yıldızlar**',
        'attributes': {'code': true},
      });
    });

    test('a styled link label keeps BOTH attributes', () {
      final delta = markdownToDelta('[**kalın bağlantı**](https://x.test)\n');
      expect(delta.first['attributes'], {
        'bold': true,
        'link': 'https://x.test',
      });
    });

    test('an image becomes an embed, not text', () {
      final delta = markdownToDelta('![](alliswell://file/01ABC)\n');
      expect(delta.first['insert'], {'image': 'alliswell://file/01ABC'});
    });

    test('unrecognised markup survives as literal text, never dropped', () {
      // A table is not supported — but losing the user's data would be worse
      // than importing it as plain lines.
      final delta = markdownToDelta('| a | b |\n| - | - |\n| 1 | 2 |\n');
      expect(deltaToMarkdown(delta), contains('| a | b |'));
      expect(deltaToMarkdown(delta), contains('| 1 | 2 |'));
    });
  });

  group('round trip against deltaToMarkdown', () {
    // Every block and inline shape the toolbar can produce.
    final delta = <Map<String, dynamic>>[
      {'insert': 'Büyük başlık'},
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
      {'insert': 'Gövde '},
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
        'attributes': {'link': 'https://alliswell.space'},
      },
      {'insert': '\nAlt başlık'},
      {
        'insert': '\n',
        'attributes': {'header': 2},
      },
      {'insert': 'madde'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': 'yapıldı'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': 'alıntı'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': 'kod();'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
    ];

    test('markdown → delta → markdown is stable', () {
      final once = deltaToMarkdown(delta);
      final twice = deltaToMarkdown(markdownToDelta(once));
      expect(twice, once);
    });

    test('Turkish text and characters survive the trip', () {
      const source = '# Yayla planı\n\nÇamlıhemşin ığüşöç İĞÜŞÖÇ — 23:59.\n';
      expect(
        deltaToMarkdown(markdownToDelta(source)),
        '# Yayla planı\n\nÇamlıhemşin ığüşöç İĞÜŞÖÇ — 23:59.',
      );
    });
  });

  group('title extraction', () {
    test('a leading H1 becomes the title and leaves the body', () {
      final split = splitMarkdownTitle(
        '# Yayla planı\n\nrota ve notlar\n',
        fallback: 'dosya',
      );
      expect(split.title, 'Yayla planı');
      expect(split.body, 'rota ve notlar\n');
    });

    test('no H1 falls back to the file name and keeps the whole body', () {
      final split = splitMarkdownTitle(
        'ilk satır\nikinci satır\n',
        fallback: 'notlarim',
      );
      expect(split.title, 'notlarim');
      expect(split.body, 'ilk satır\nikinci satır\n');
    });

    test('an H2 first is NOT the title — it is content', () {
      final split = splitMarkdownTitle('## alt\nmetin\n', fallback: 'dosya');
      expect(split.title, 'dosya');
      expect(split.body, '## alt\nmetin\n');
    });
  });
}
