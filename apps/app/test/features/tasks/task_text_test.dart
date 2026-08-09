import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_text.dart';

/// OPH-243 — the rules that turn shared text into a task's fields. Pure, so the
/// product decisions are asserted here instead of inside a widget pump.
void main() {
  group('clipTaskTitle', () {
    test('keeps a short single line exactly as it is', () {
      expect(clipTaskTitle('Yayla planını yap'), 'Yayla planını yap');
    });

    test('takes only the first line', () {
      expect(clipTaskTitle('Başlık\nikinci satır\nüçüncü'), 'Başlık');
    });

    test('clips at the limit, ellipsis included — never one over', () {
      final long = 'a' * 300;
      final clipped = clipTaskTitle(long);
      expect(clipped.length, kTaskTitleMaxChars);
      expect(clipped.endsWith('…'), isTrue);
    });

    test('a line exactly at the limit is not clipped', () {
      final exact = 'b' * kTaskTitleMaxChars;
      expect(clipTaskTitle(exact), exact);
    });
  });

  group('taskFieldsFromSharedText', () {
    test('a short line becomes the title and nothing else', () {
      final f = taskFieldsFromSharedText('Süt al');
      expect(f.title, 'Süt al');
      expect(
        f.description,
        isNull,
        reason: 'a description that only repeats the title is noise',
      );
    });

    test('multi-line text keeps the WHOLE text in the description', () {
      final f = taskFieldsFromSharedText('Alışveriş\nsüt\nekmek');
      expect(f.title, 'Alışveriş');
      expect(
        f.description,
        'Alışveriş\nsüt\nekmek',
        reason:
            'nothing a person shared may be dropped — this is '
            'captureToInbox\'s existing rule, kept identical',
      );
    });

    test('a clipped title still leaves the full text behind', () {
      final long = 'c' * 200;
      final f = taskFieldsFromSharedText(long);
      expect(f.title.length, kTaskTitleMaxChars);
      expect(f.description, long);
    });

    test('a URL goes at the END of the description, on its own line', () {
      final f = taskFieldsFromSharedText(
        'Bunu oku\nnotlar burada',
        url: 'https://example.com/a',
      );
      expect(f.title, 'Bunu oku');
      expect(f.description, 'Bunu oku\nnotlar burada\nhttps://example.com/a');
    });

    test('a bare URL share titles the link and does not repeat it', () {
      final f = taskFieldsFromSharedText(
        'https://example.com/a',
        url: 'https://example.com/a',
      );
      expect(f.title, 'https://example.com/a');
      expect(
        f.description,
        isNull,
        reason: 'the url IS the text here; repeating it would be clutter',
      );
    });

    test('a short title plus a different URL still gets a description', () {
      final f = taskFieldsFromSharedText('Example', url: 'https://example.com');
      expect(f.title, 'Example');
      expect(f.description, 'https://example.com');
    });

    test('surrounding whitespace never reaches the fields', () {
      final f = taskFieldsFromSharedText('   Boşluklu   \n  gövde  ');
      expect(f.title, 'Boşluklu');
      expect(f.description, 'Boşluklu   \n  gövde');
    });
  });
}
