import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Round 16 #2 — the web shell carries a fix that no Dart test can exercise,
/// because the bug lives in the browser's CSS.
///
/// Drag-selecting text in a note on Firefox drew the text TWICE: once by
/// Flutter on the canvas and once, in 13 px monospace, by
/// `<textarea class="flt-text-editing">` — the hidden proxy the web engine
/// keeps over the canvas for IME and the clipboard. The engine hides it with
/// `color: transparent`, and `::selection` is exactly what overrides `color`,
/// so the moment a selection was mirrored into that textarea Firefox repainted
/// the range in the system selection colours. Chromium keeps the transparent
/// colour, which is why it never showed there — and why three faithful repro
/// builds in Chromium came back clean.
///
/// `web/index.html` is a file `flutter create` templates rewrite wholesale, so
/// this guards the rule rather than the symptom.
void main() {
  test('index.html keeps the hidden IME proxy invisible while selected', () {
    final html = File('web/index.html').readAsStringSync();

    expect(
      html,
      contains('.flt-text-editing::selection'),
      reason:
          'without this, Firefox paints Flutter\'s hidden textarea over the '
          'canvas whenever text is selected (round 16 #2)',
    );
    // Firefox still honours the legacy pseudo-element, and an unknown one
    // invalidates the WHOLE selector — so it has to be its own rule, never
    // comma-joined with ::selection.
    expect(html, contains('.flt-text-editing::-moz-selection'));
    expect(
      html.contains('::selection,') || html.contains('::-moz-selection,'),
      isFalse,
      reason:
          'comma-joining the two pseudo-elements makes browsers drop the '
          'entire rule',
    );
  });

  test('OPH-413 (K3): index.html paints an opening screen until the first '
      'frame, then removes it', () {
    final html = File('web/index.html').readAsStringSync();
    final body = html.substring(html.indexOf('<body'));
    final splash = body.indexOf('id="aw-splash"');
    expect(
      splash,
      isNonNegative,
      reason: 'a white page until the engine loads',
    );
    expect(
      splash,
      lessThan(body.indexOf('flutter_bootstrap.js')),
      reason: 'it must paint while the bootstrap script downloads',
    );
    expect(body, contains('Opening AllisWell'));
    expect(html, contains('flutter-first-frame'));
    expect(html, contains('prefers-color-scheme: dark'));
    expect(html, contains('prefers-reduced-motion: reduce'));
    // ADR-0063 #7: no request to another host, so no web font.
    expect(html.contains('fonts.googleapis.com'), isFalse);
  });

  test('OPH-413 (R-08): index.html declares the viewport the engine will use, '
      'before the opening screen paints', () {
    final html = File('web/index.html').readAsStringSync();
    final head = html.substring(0, html.indexOf('</head>'));
    final meta = RegExp(r'<meta[^>]*name="viewport"[^>]*>').firstMatch(head);
    expect(
      meta,
      isNotNull,
      reason:
          'without it a phone lays the opening screen out at 980 px and '
          'shrinks it: a 32 px icon and unreadable text',
    );
    final tag = meta!.group(0)!;
    // The same content the engine writes when it boots
    // (FullPageEmbeddingStrategy._applyViewportMeta), so the swap at the
    // first frame changes nothing and the page does not re-flow.
    expect(
      tag,
      contains(
        'content="width=device-width, initial-scale=1.0, maximum-scale=5.0"',
      ),
    );
    // WCAG 1.4.4: pinch zoom stays possible.
    expect(tag.contains('user-scalable=no'), isFalse);
    expect(
      head.indexOf(tag),
      lessThan(head.indexOf('#aw-splash')),
      reason: 'it must be in force before the splash CSS',
    );
  });
}
