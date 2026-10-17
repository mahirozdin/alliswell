import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/ai_mention.dart';

/// OPH-377 — the "@" parser decides when the attach picker opens. Pure.
void main() {
  AiMentionQuery? at(String text) => activeMention(text, text.length);

  group('activeMention', () {
    test('a bare "@" at the start opens with an empty query', () {
      expect(at('@'), const AiMentionQuery(start: 0, end: 1, query: ''));
    });

    test('after a space, the typed text is the query', () {
      expect(
        at('hey @pla'),
        const AiMentionQuery(start: 4, end: 8, query: 'pla'),
      );
    });

    test('single spaces are allowed — titles have them', () {
      expect(at('toplantı @Proje Not')?.query, 'Proje Not');
    });

    test('an e-mail address never opens the picker', () {
      expect(at('ali@x.com'), isNull);
    });

    test('an opening bracket or quote is a boundary', () {
      expect(at('(@not')?.query, 'not');
      expect(at('"@not')?.query, 'not');
      expect(at('[@not')?.query, 'not');
    });

    test('a cursor at or before the "@" is not in a mention', () {
      expect(activeMention('hey @pla', 4), isNull);
      expect(activeMention('hey @pla', 2), isNull);
      expect(activeMention('hey @pla', 5)?.query, '');
    });

    test('an invalid cursor is null', () {
      expect(activeMention('@a', -1), isNull);
      expect(activeMention('@a', 3), isNull);
      expect(activeMention('', 0), isNull);
    });

    test('a newline inside the query closes it', () {
      expect(at('@abc\ndef'), isNull);
    });

    test('a double space closes it', () {
      expect(at('@abc  def'), isNull);
    });

    test('a space right after the "@" closes it', () {
      expect(at('@ '), isNull);
      expect(at('@ abc'), isNull);
    });

    test('a query longer than the cap closes it', () {
      expect(at('@${'a' * kAiMentionMaxQuery}')?.query.length, 40);
      expect(at('@${'a' * (kAiMentionMaxQuery + 1)}'), isNull);
    });

    test('"@@a" uses the last "@", which is not on a boundary', () {
      expect(at('@@a'), isNull);
    });

    test('Turkish letters are part of the query', () {
      expect(at('@çalış')?.query, 'çalış');
    });

    test('the mention the cursor is in, not a later one', () {
      const text = 'a @not b @dosya';
      expect(activeMention(text, 6)?.query, 'not');
    });
  });

  group('removeMention', () {
    test('removes "@query" and one trailing space; the cursor sits there', () {
      const text = 'Özetle @Q3 lütfen';
      final m = activeMention(text, 10)!;
      final out = removeMention(text, m);
      expect(out.text, 'Özetle lütfen');
      expect(out.cursor, 7);
    });

    test('at the end of the text', () {
      const text = 'Özetle @Q3';
      final out = removeMention(text, at(text)!);
      expect(out.text, 'Özetle ');
      expect(out.cursor, 7);
    });

    test('mid-text keeps what surrounds it', () {
      const text = 'bak (@not) bence';
      final m = activeMention(text, 9)!;
      final out = removeMention(text, m);
      expect(out.text, 'bak () bence');
      expect(out.cursor, 5);
    });
  });
}
