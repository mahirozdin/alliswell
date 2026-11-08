import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/linkify.dart';

/// OPH-164 — URL detection for task descriptions.
void main() {
  List<LinkSegment> seg(String text) => linkifySegments(text);

  test('plain text stays one plain segment', () {
    final out = seg('sadece düz metin, link yok');
    expect(out, hasLength(1));
    expect(out.single.uri, isNull);
  });

  test('a mid-sentence https URL becomes a link segment', () {
    final out = seg('tasarım şurada https://example.com/spec duruyor');
    expect(
      out.map((s) => s.text).join(),
      'tasarım şurada https://example.com/spec duruyor',
    );
    final link = out.singleWhere((s) => s.uri != null);
    expect(link.text, 'https://example.com/spec');
    expect(link.uri.toString(), 'https://example.com/spec');
  });

  test('trailing sentence punctuation stays out of the link', () {
    for (final tail in ['.', ',', '!', '?', ':', ';']) {
      final out = seg('bak: https://x.dev$tail');
      final link = out.singleWhere((s) => s.uri != null);
      expect(link.text, 'https://x.dev', reason: 'tail was "$tail"');
    }
  });

  test('a wrapping paren is trimmed, a Wikipedia-style one survives', () {
    final wrapped = seg('(kaynak: https://x.dev/a)');
    expect(wrapped.singleWhere((s) => s.uri != null).text, 'https://x.dev/a');

    final wiki = seg('https://en.wikipedia.org/wiki/Task_(project)');
    expect(
      wiki.singleWhere((s) => s.uri != null).text,
      'https://en.wikipedia.org/wiki/Task_(project)',
    );
  });

  test('bare www hosts link with an https scheme', () {
    final out = seg('siteye www.alliswell.dev üzerinden gir');
    final link = out.singleWhere((s) => s.uri != null);
    expect(link.text, 'www.alliswell.dev');
    expect(link.uri.toString(), 'https://www.alliswell.dev');
  });

  test('multiple URLs split the text losslessly', () {
    const text = 'a https://one.dev b www.two.dev c';
    final out = seg(text);
    expect(out.map((s) => s.text).join(), text);
    expect(out.where((s) => s.uri != null), hasLength(2));
  });

  // OPH-400 (DESIGN §46 R4): what a task ROW shows for its title. The detail
  // screen keeps the whole string; the row must never spend five lines on it.
  group('awRowTitle', () {
    test('a bare URL reads as "host › path" and says it is a link', () {
      final row = awRowTitle(
        'https://github.com/alliswell/app/issues/412?tab=comments#top',
      );
      expect(row.isLink, isTrue);
      expect(row.text, 'github.com › alliswell/app/issues/412');
    });

    test('www and a bare host drop the noise', () {
      expect(awRowTitle('www.example.com').text, 'example.com');
      expect(awRowTitle('https://example.com/').text, 'example.com');
      expect(
        awRowTitle('  https://www.Example.com/a/  ').text,
        'example.com › a',
      );
    });

    test('a percent-encoded path is shown decoded, a broken one as is', () {
      expect(
        awRowTitle('https://tr.wikipedia.org/wiki/%C4%B0stanbul').text,
        'tr.wikipedia.org › wiki/İstanbul',
      );
      expect(awRowTitle('https://x.dev/%E0%A4%A').text, 'x.dev › %E0%A4%A');
    });

    test('a URL inside a sentence stays, breakable after its separators', () {
      const title = 'Read https://a.dev/x/y?q=1&r=2 today';
      final row = awRowTitle(title);
      expect(row.isLink, isFalse);
      expect(row.text.replaceAll('​', ''), title);
      expect(row.text, contains('a.dev/​x/​y?​q=​1&'));
      // The words around it are untouched.
      expect(row.text, startsWith('Read https:/'));
      expect(row.text, endsWith(' today'));
    });

    test('a plain title is returned as it is', () {
      const title = 'Pazartesi sunumu için slaytları hazırla';
      expect(awRowTitle(title), (text: title, isLink: false));
    });
  });
}
