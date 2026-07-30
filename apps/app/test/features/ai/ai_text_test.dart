import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

  // OPH-226 — the shared red-team corpus. Every hostile string the model could
  // echo (HTML, exfil URLs, markdown-link exfil, alliswell://complete) renders
  // as inert, selectable text with no tap target — so there is nothing to
  // launch. The corpus is shared with the server (mcp/ai-injection tests).
  group('red-team corpus renders inert', () {
    final cases =
        (jsonDecode(
                  File('test/fixtures/ai_redteam.json').readAsStringSync(),
                )['cases']
                as List)
            .cast<Map<String, dynamic>>();

    for (final c in cases) {
      test('"${c['id']}" produces no tappable link', () {
        final spans = parseAiSpans(c['text'] as String);
        // The ONLY tappable span AiText ever emits is a resolved alliswell://
        // nav link; no hostile case is one.
        expect(spans.whereType<AiSpanNavLink>(), isEmpty);
        // And the content is preserved as data (nothing is silently dropped).
        expect(spans.whereType<AiSpanText>(), isNotEmpty);
      });
    }

    testWidgets('rendering every case never navigates', (tester) async {
      final navigated = <String>[];
      for (final c in cases) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AiText(c['text'] as String, onNavigate: navigated.add),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      // No case auto-opens anything: there is no url_launcher in AiText at all,
      // and hostile content yields no nav link to even call onNavigate.
      expect(navigated, isEmpty);
    });
  });
}
