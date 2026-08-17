import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-247 — a document is untrusted input (DESIGN §29 D10, ADR-0028 §Zorlama).
///
/// Epic 20 built `ai_redteam.json` for model output, but §24 AI6 was never
/// really about AI: it is about rendering text somebody else wrote. A `.md`
/// from a stranger's repository arrives through OPH-241's "open with" handler
/// with nobody vouching for it, so the same corpus is replayed here — embedded
/// **inside a markdown document**, which is the shape this surface actually
/// receives.
void main() {
  final corpus =
      (jsonDecode(File('test/fixtures/ai_redteam.json').readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List<dynamic>;

  Widget host(String markdown, {void Function(Uri)? onOpen}) => MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: Scaffold(
      body: MarkdownView(
        document: parseMarkdown(markdown),
        shrinkWrap: true,
        onOpenLink: onOpen ?? (_) {},
      ),
    ),
  );

  group('the URI allowlist', () {
    test('permits only what a document may navigate to', () {
      expect(isSafeMarkdownLink('https://alliswell.space'), isTrue);
      expect(isSafeMarkdownLink('http://example.com'), isTrue);
      expect(isSafeMarkdownLink('mailto:a@b.c'), isTrue);
      expect(isSafeMarkdownLink('alliswell://task/01H'), isTrue);
      // Relative links and anchors have no scheme; they are resolved, never
      // executed (OPH-249/OPH-251 own where they point).
      expect(isSafeMarkdownLink('./other.md'), isTrue);
      expect(isSafeMarkdownLink('#heading'), isTrue);
    });

    test('is an allowlist, so the scheme nobody thought of also fails', () {
      for (final bad in [
        "javascript:alert('x')",
        'JavaScript:alert(1)', // case must not be an escape hatch
        'data:text/html;base64,PHN2Zz4=',
        'vbscript:msgbox(1)',
        'file:///etc/passwd',
        'blob:https://evil.example/x',
        'intent://scan/#Intent;scheme=zxing;end',
      ]) {
        expect(isSafeMarkdownLink(bad), isFalse, reason: bad);
      }
    });

    test('recognises in-document anchors', () {
      expect(inDocumentAnchor('#türkçe-başlık'), 'türkçe-başlık');
      expect(inDocumentAnchor('https://x.dev#frag'), isNull);
      expect(inDocumentAnchor('#'), isNull);
    });
  });

  group('the red-team corpus, embedded in a document', () {
    for (final raw in corpus) {
      final c = raw as Map<String, dynamic>;
      final id = c['id'] as String;
      final text = c['text'] as String;

      testWidgets('$id renders inert', (tester) async {
        final opened = <Uri>[];
        // Wrapped in real document furniture: the payload has to survive being
        // a paragraph among others, not just a lone string.
        await tester.pumpWidget(
          host('# Belge\n\n$text\n\nson satır', onOpen: opened.add),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Nothing is launched without a tap. This is the guarantee that makes
        // an untrusted document safe to merely OPEN.
        expect(opened, isEmpty, reason: '$id fired a link on its own');

        // A payload with no legitimate link must produce no tap target at all.
        // (Counting recognizers, not reading hrefs: a span only knows its
        // display text, and "here" tells you nothing about where it goes. The
        // href policy itself is proved by the allowlist tests above, and the
        // per-scheme widget assertions live in `aw_markdown_test.dart`.)
        // `http` covers both shapes GFM makes tappable: an explicit
        // `[text](url)` and a BARE url, which the autolink extension turns
        // into a link exactly as GitHub does. `exfil-url` is the bare kind —
        // an earlier version of this guard only looked for `](http` and
        // flagged it, which would have been a false alarm about correct
        // behaviour.
        if (!text.contains('http')) {
          expect(
            _recognizerCount(tester),
            0,
            reason: '$id created a tap target with no legitimate link',
          );
        }
      });
    }
  });

  group('HTML is shown, never run', () {
    testWidgets('a script block becomes visible source', (tester) async {
      await tester.pumpWidget(
        host("<div>\n<script>fetch('https://evil.example/x')</script>\n</div>"),
      );

      expect(find.byType(MdRawHtmlBlock), findsOneWidget);
      expect(
        find.textContaining('<script>', findRichText: true),
        findsWidgets,
        reason: 'the source must be readable, not swallowed',
      );
    });

    testWidgets('inline HTML stays literal text', (tester) async {
      await tester.pumpWidget(host('bu <b>kalın olmamalı</b> bir cümle'));

      // The package's InlineHtmlSyntax is a TextSyntax, so the tags arrive as
      // characters. Asserting it here keeps that guarantee from silently
      // changing under a package upgrade.
      expect(find.textContaining('<b>', findRichText: true), findsWidgets);
    });
  });

  group('an exfiltration link is a link, and stays visible as one', () {
    testWidgets('it is tappable but only through the callback', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        host(
          'Click [here](https://evil.example/steal?token=SECRET) to continue',
          onOpen: opened.add,
        ),
      );

      // https IS allowed — refusing every external link would break every
      // README. The guarantee is that nothing opens on its own, and that the
      // host app decides what to do with the uri.
      expect(opened, isEmpty);

      // `tapOnText`, not `tap`: the link is one word inside a sentence, and
      // tapping the RichText taps its CENTRE — which here lands on " to ".
      await tester.tapOnText(find.textRange.ofSubstring('here'));
      expect(opened.single.host, 'evil.example');
    });
  });
}

/// How many tappable spans the rendered document created.
int _recognizerCount(WidgetTester tester) {
  var count = 0;
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.recognizer is TapGestureRecognizer) count++;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return count;
}
