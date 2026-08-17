import 'package:flutter_test/flutter_test.dart';

import 'package:markdown_forge/markdown_forge.dart';

/// OPH-250 — typing comfort as pure transforms (DESIGN §29 D17/D20/D22).
void main() {
  group('D17 — Enter inside a list', () {
    test(
      'continues an unordered list, keeping the marker the author chose',
      () {
        const text = '- bir';
        final edit = continueList(text, text.length)!;

        // `*` must not silently become `-`: the document is the author's.
        expect(edit.text, '- bir\n- ');
        expect(continueList('* bir', 5)!.text, '* bir\n* ');
        expect(continueList('+ bir', 5)!.text, '+ bir\n+ ');
      },
    );

    test(
      'numbers the next ordered item, and keeps `)` if that is the style',
      () {
        expect(continueList('3. üç', 5)!.text, '3. üç\n4. ');
        expect(continueList('3) üç', 5)!.text, '3) üç\n4) ');
      },
    );

    test('leaves the list on an EMPTY item instead of adding another', () {
      // The behaviour people notice: without it, the only way out of a list is
      // to delete the bullet you were just given.
      const text = '- bir\n- ';
      final edit = continueList(text, text.length)!;

      expect(edit.text, '- bir\n\n');
      expect(edit.selection, 7);
    });

    test('a continued task item starts UNCHECKED', () {
      // Carrying `[x]` forward would tick a box nobody ticked.
      expect(continueList('- [x] bitti', 11)!.text, '- [x] bitti\n- [ ] ');
      expect(continueList('- [ ] açık', 10)!.text, '- [ ] açık\n- [ ] ');
    });

    test('keeps the indent, so a nested list stays nested', () {
      expect(continueList('  - iç', 6)!.text, '  - iç\n  - ');
    });

    test('a plain paragraph is left alone', () {
      expect(continueList('düz metin', 9), isNull);
    });
  });

  group('D17 — Tab / Shift-Tab', () {
    test('Tab nests by one level', () {
      final edit = indentListItem('- bir', 5, outdent: false)!;
      expect(edit.text, '  - bir');
      expect(edit.selection, 7);
    });

    test('Shift-Tab un-nests, and does nothing at the outer level', () {
      expect(indentListItem('  - bir', 7, outdent: true)!.text, '- bir');
      expect(indentListItem('- bir', 5, outdent: true), isNull);
    });

    test('does nothing outside a list', () {
      expect(indentListItem('düz metin', 4, outdent: false), isNull);
    });
  });

  group('D17 — renumbering', () {
    test('a list written 1. 1. 1. reads 1. 2. 3.', () {
      expect(
        renumberOrderedLists('1. bir\n1. iki\n1. üç'),
        '1. bir\n2. iki\n3. üç',
      );
    });

    test('an inserted item renumbers everything AFTER it', () {
      // A half-renumbered list is worse than an unnumbered one, which is why
      // this runs over the whole document.
      expect(
        renumberOrderedLists('1. bir\n2. yeni\n2. iki\n3. üç'),
        '1. bir\n2. yeni\n3. iki\n4. üç',
      );
    });

    test('nested levels count separately', () {
      expect(
        renumberOrderedLists('1. bir\n  1. a\n  5. b\n2. iki'),
        '1. bir\n  1. a\n  2. b\n2. iki',
      );
    });

    test('a paragraph between two lists resets the counter', () {
      expect(
        renumberOrderedLists('1. bir\n\n2. iki'),
        '1. bir\n\n2. iki',
        reason: 'a blank line alone does not interrupt a list',
      );
      expect(
        renumberOrderedLists('1. bir\n\nmetin\n\n5. yeni'),
        '1. bir\n\nmetin\n\n1. yeni',
      );
    });

    test('unordered lists are untouched', () {
      const src = '- bir\n- iki';
      expect(renumberOrderedLists(src), src);
    });
  });

  group('D20 — smart paste', () {
    test('a URL over a selection becomes a link', () {
      final edit = pasteOverSelection('AllisWell rocks', 0, 9, 'https://a.dev');

      expect(edit.text, '[AllisWell](https://a.dev) rocks');
    });

    test('a URL over NOTHING is just pasted', () {
      expect(
        pasteOverSelection('abc', 3, 3, 'https://a.dev').text,
        'abchttps://a.dev',
      );
    });

    test('non-URL text over a selection replaces it, as paste always did', () {
      expect(pasteOverSelection('bir iki', 0, 3, 'üç').text, 'üç iki');
    });

    test('recognises what is and is not a pastable url', () {
      expect(isPastableUrl('https://a.dev'), isTrue);
      expect(isPastableUrl('  http://a.dev  '), isTrue);
      expect(isPastableUrl('mailto:a@b.c'), isTrue);
      expect(isPastableUrl('bir cümle'), isFalse);
      expect(isPastableUrl('javascript:alert(1)'), isFalse);
      expect(isPastableUrl('https://a.dev iki kelime'), isFalse);
    });

    test('HTML pastes as markdown', () {
      expect(htmlToMarkdown('<b>kalın</b>'), '**kalın**');
      expect(htmlToMarkdown('<h2>Başlık</h2>'), '## Başlık');
      expect(
        htmlToMarkdown('<a href="https://a.dev">site</a>'),
        '[site](https://a.dev)',
      );
      expect(
        htmlToMarkdown('<ul><li>bir</li><li>iki</li></ul>'),
        '- bir\n- iki',
      );
    });

    test('entities are decoded AFTER the tags, not before', () {
      // Decoding first would turn an escaped `&lt;b&gt;` into a real tag and
      // then "convert" text the author wrote as literal.
      expect(
        htmlToMarkdown('&lt;b&gt;kalın değil&lt;/b&gt;'),
        '<b>kalın değil</b>',
      );
    });

    test('markup we do not know keeps its tags rather than vanishing', () {
      // §28 M2 one surface over: a lossy paste of somebody's content is worse
      // than an ugly one.
      expect(
        htmlToMarkdown('<table><tr><td>a</td></tr></table>'),
        contains('<table>'),
      );
    });
  });

  group('D22 — counts', () {
    test('counts words and characters as a person would', () {
      expect(countText('bir iki üç').words, 3);
      expect(countText('bir iki üç').characters, 10);
      expect(countText('   ').words, 0);
      expect(countText('').words, 0);
    });

    test('collapses whitespace runs when counting words', () {
      expect(countText('bir\n\niki   üç').words, 3);
    });
  });
}
