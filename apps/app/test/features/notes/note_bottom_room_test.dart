import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../projects/fake_api.dart';
import 'notes_flow_test_support.dart';

/// Round 19c — "I scrolled to the end of a long note and could not tap there."
///
/// Two failures wear the same face, and only one is about comfort:
///
///  * The shell floats a glass bar over the document (`extendBody: true`), so
///    the last lines are UNDER it — not awkward, **unreachable**.
///  * Even clear of the bar, the end of a document is a ~20 px target at the
///    very bottom edge of the screen.
///
/// The host reports the first as `MediaQuery.padding.bottom`. The second is
/// scroll-past-end, and it has to be scrollable CONTENT: `expands: true` +
/// `contentPadding` would carve a permanent strip out of the visible area and
/// still pin the last line to the bottom of a shorter box.
const double _kBarInset = 96;
const double _kHeight = 780;

String _longNote() =>
    List.generate(60, (i) => 'satır ${i + 1} — biraz metin').join('\n\n');

Widget _host(Widget child) => ProviderScope(
  child: MediaQuery(
    // What a Scaffold body sees under `extendBody: true`: the floating bar's
    // height arrives as bottom padding.
    data: const MediaQueryData(
      size: Size(390, _kHeight),
      padding: EdgeInsets.only(bottom: _kBarInset),
    ),
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: Scaffold(body: child),
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, _kHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('reading mode leaves the last line clear of the host chrome', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_host(ReadingMode(markdown: _longNote())));
    await tester.pumpAndSettle();

    // A lazy list: the ending has to be scrolled to, not dragged at blindly.
    final last = find.text('satır 60 — biraz metin');
    await tester.scrollUntilVisible(last, 400);
    await tester.pumpAndSettle();
    // …then all the way, so it rests where it finally rests.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(last, findsOneWidget, reason: 'the note ends here');
    expect(
      tester.getRect(last).bottom,
      lessThan(_kHeight - _kBarInset),
      reason: 'the last line must not sit under the floating bar',
    );
  });

  testWidgets('the editor can be scrolled PAST the end of a long note', (
    tester,
  ) async {
    _phone(tester);
    final controller = MdSourceController(text: _longNote());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(SourceMode(controller: controller)));
    await tester.pumpAndSettle();

    // Drag the VIEWPORT, not the field: the field is now taller than the
    // screen, so its centre is off-screen and a drag aimed there lands nowhere.
    // These are the pixels a thumb actually touches — and they sit over the
    // text, which is the case that must keep scrolling.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pumpAndSettle();

    // Scrolled as far as it goes, the end of the text is NOT at the bottom
    // edge: the trailing room has carried it up the screen, which is the whole
    // point — `expands: true` could only ever pin it to the bottom.
    final tail = tester.getRect(find.byKey(const Key('note-source-tail')));
    expect(
      tail.top,
      lessThan(_kHeight * 0.75),
      reason: 'the end should be reachable without stretching for the edge',
    );
    expect(
      tail.height,
      greaterThan(120),
      reason: 'a token gap is not room to scroll past the end',
    );
  });

  testWidgets('tapping the empty space below the text appends to the end', (
    tester,
  ) async {
    _phone(tester);
    final controller = MdSourceController(text: _longNote())
      ..selection = const TextSelection.collapsed(offset: 0);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(SourceMode(controller: controller)));
    await tester.pumpAndSettle();

    // Drag the VIEWPORT, not the field: the field is now taller than the
    // screen, so its centre is off-screen and a drag aimed there lands nowhere.
    // These are the pixels a thumb actually touches — and they sit over the
    // text, which is the case that must keep scrolling.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pumpAndSettle();

    // Blank space that places no caret is a dead affordance (§22).
    await tester.tap(find.byKey(const Key('note-source-tail')));
    await tester.pumpAndSettle();

    expect(
      controller.selection.baseOffset,
      controller.text.length,
      reason: 'a tap past the last line puts the caret at the end',
    );
  });

  testWidgets('a SHORT note still fills the screen and appends on tap', (
    tester,
  ) async {
    // The behaviour `expands: true` used to give for free, and the one most
    // likely to be lost by moving the field into a scroll view.
    _phone(tester);
    final controller = MdSourceController(text: 'tek satır');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(SourceMode(controller: controller)));
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byKey(const Key('note-source-field')));
    expect(
      field.height,
      greaterThan(200),
      reason: 'a one-line note still offers a full-height place to write',
    );

    await tester.tapAt(Offset(field.center.dx, field.bottom - 20));
    await tester.pumpAndSettle();
    expect(controller.selection.baseOffset, controller.text.length);
  });

  // The synthetic host above proves the geometry. This proves the INSET
  // actually survives the real app's nested scaffolds — the shell's floating
  // bar reports itself through `MediaQuery.padding.bottom`, and a Scaffold
  // strips that from its body when it has a bottom bar of its own. The note
  // editor's does not, so it passes through; that is a fact about Flutter's
  // Scaffold, and facts about other people's code are worth measuring.
  testWidgets('the host chrome inset reaches the editor through the shell', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi()
      ..seedNote(title: 'Uzun not', contentMarkdown: _longNote());
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);
    await tester.tap(find.text('Uzun not'));
    await tester.pumpAndSettle();

    final tail = find.byKey(const Key('note-source-tail'));
    expect(tail, findsOneWidget, reason: 'the editor opens in Source mode');

    // Whatever the shell reports, the tail is real room rather than a token.
    expect(tester.getRect(tail).height, greaterThan(120));
  });
}
