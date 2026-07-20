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
}
