import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/ui/ai_text.dart';

/// OPH-221/226 — AiText's parser is pure and strict: HTML is never markup,
/// only alliswell:// URIs that resolve become nav links, everything else
/// (including http URLs) stays inert text.
void main() {
  test('bold, italic and code become styled spans', () {
    final spans = parseAiSpans('**bold** and *italic* and `code`');
    final texts = spans.whereType<AiSpanText>().toList();
    expect(texts.any((s) => s.bold && s.text == 'bold'), isTrue);
    expect(texts.any((s) => s.italic && s.text == 'italic'), isTrue);
    expect(texts.any((s) => s.code && s.text == 'code'), isTrue);
  });

  test('HTML is inert text, never interpreted', () {
    final spans = parseAiSpans(
      '<script>alert(1)</script><img src=x onerror=y>',
    );
    expect(spans, everyElement(isA<AiSpanText>()));
    expect(spans.whereType<AiSpanNavLink>(), isEmpty);
    final joined = spans.whereType<AiSpanText>().map((s) => s.text).join();
    expect(joined, contains('<script>'));
  });

  test('an http(s) URL is plain text — no tap target', () {
    final spans = parseAiSpans(
      'see https://evil.example/steal?token=SECRET now',
    );
    expect(spans.whereType<AiSpanNavLink>(), isEmpty);
  });

  test('a valid alliswell://task/<ulid> becomes a nav link to the route', () {
    const ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
    final spans = parseAiSpans('open alliswell://task/$ulid please');
    final link = spans.whereType<AiSpanNavLink>().single;
    expect(link.route, '/tasks/$ulid');
  });

  test('a background-action scheme is inert — never a nav link', () {
    final spans = parseAiSpans('run alliswell://complete?id=all');
    expect(spans.whereType<AiSpanNavLink>(), isEmpty);
    expect(
      spans.whereType<AiSpanText>().map((s) => s.text).join(),
      contains('alliswell://complete'),
    );
  });

  test('an unresolvable alliswell:// URI is inert', () {
    final spans = parseAiSpans('alliswell://task/not-a-ulid');
    expect(spans.whereType<AiSpanNavLink>(), isEmpty);
  });
}
