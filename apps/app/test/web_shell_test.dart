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
}
