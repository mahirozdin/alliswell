// OPH-400 / R-09 (polish round 2): AX3 broke words in the middle and cut
// headings short — "Entegrasyonla / r" and "demo@alliswel / l.space" on the
// Settings index, "Kasım 2…" over the Home calendar, "Yeni …" over the
// new-task sheet and its "Başlık" label clipped by the form's top edge.
//
// Measured with the repo's real Roboto/DejaVu: the test font's square glyphs
// make every long Turkish word wider than an AX3 line and would prove nothing.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/word_safe_text.dart';

import '../design_screenshots_test.dart'
    show loadRealFontsForStore, seededStoreApi, signedInStoreApp;

const _family = 'ScreenshotSans';

/// iOS AX3 (≈ 2.35× body) and AX5 (≈ 3.1×).
const _scales = [2.35, 3.1];
const _phone = Size(393, 852);

void _surface(WidgetTester tester, double scale, {Size size = _phone}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

TextPainter _painterLike(RenderParagraph p) => TextPainter(
  text: p.text,
  textDirection: p.textDirection,
  textScaler: p.textScaler,
  maxLines: p.maxLines,
  ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
  strutStyle: p.strutStyle,
  textWidthBasis: p.textWidthBasis,
  textHeightBehavior: p.textHeightBehavior,
)..layout(maxWidth: p.constraints.maxWidth);

/// Every wrap in [p] that is not after a space, a zero-width break or a
/// hyphen — i.e. inside a word — as "before|after".
List<String> _midWordBreaks(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final painter = _painterLike(p);
  final lines = painter.computeLineMetrics();
  final bad = <String>[];
  for (final line in lines.take(lines.length - 1)) {
    final end = painter
        .getLineBoundary(
          painter.getPositionForOffset(
            Offset(0, line.baseline - line.ascent / 2),
          ),
        )
        .end;
    if (end <= 0 || end >= text.length) continue;
    final ok =
        RegExp('[\\s$kAwZwsp\\-]').hasMatch(text[end - 1]) ||
        RegExp(r'\s').hasMatch(text[end]);
    if (!ok) {
      bad.add(
        '${text.substring((end - 8).clamp(0, end), end)}|'
        '${text.substring(end, (end + 8).clamp(end, text.length))}',
      );
    }
  }
  painter.dispose();
  return bad;
}

List<RenderParagraph> _paragraphsIn(WidgetTester tester, Finder of) => [
  for (final e
      in find.descendant(of: of, matching: find.byType(RichText)).evaluate())
    e.renderObject! as RenderParagraph,
];

void main() {
  setUpAll(loadRealFontsForStore);
  setUp(() => AwI18n.instance.setActiveCached(const Locale('tr')));
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  // Polish 4 T-06 narrowed this: after the "@" only, the domain one piece
  // (`large_text_cuts_test.dart` draws it).
  test('an address breaks after "@", nowhere else', () {
    expect(
      awBreakableAddress('demo@alliswell.space'),
      'demo@${kAwZwsp}alliswell.space',
    );
    expect(awBreakableAddress('.x'), '.x');
  });

  testWidgets('a word wider than its slot is drawn smaller, not cut', (
    tester,
  ) async {
    _surface(tester, 3.1);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light, fontFamilyOverride: _family),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: AwWordSafeText(
                'Entegrasyonlar ve takvimler',
                key: Key('t'),
              ),
            ),
          ),
        ),
      ),
    );
    final p = _paragraphsIn(tester, find.byKey(const Key('t'))).single;
    expect(_midWordBreaks(p), isEmpty);
    expect(p.textScaler.scale(1), lessThan(3.1));
  });

  testWidgets('a short label keeps the reader\'s size', (tester) async {
    _surface(tester, 2.35);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light, fontFamilyOverride: _family),
        home: const Scaffold(
          body: AwWordSafeText('Genel ayarlar', key: Key('t')),
        ),
      ),
    );
    final p = _paragraphsIn(tester, find.byKey(const Key('t'))).single;
    expect(p.textScaler.scale(1), closeTo(2.35, 0.001));
  });

  for (final scale in _scales) {
    testWidgets('$scale×: the Settings index never breaks inside a word', (
      tester,
    ) async {
      _surface(tester, scale, size: const Size(393, 3000));
      await tester.pumpWidget(await signedInStoreApp(seededStoreApi()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined).first);
      await tester.pumpAndSettle();

      final rows = find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('settings-group-'),
      );
      expect(rows, findsAtLeastNWidgets(5));
      final failures = <String>[];
      for (final p in _paragraphsIn(tester, rows)) {
        for (final b in _midWordBreaks(p)) {
          failures.add(b);
        }
      }
      expect(failures, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$scale×: the calendar names the whole month and year', (
      tester,
    ) async {
      _surface(tester, scale);
      await tester.pumpWidget(await signedInStoreApp(seededStoreApi()));
      await tester.pumpAndSettle();

      final title = find.byKey(const Key('calendar-month-title'));
      expect(title, findsOneWidget);
      final p = _paragraphsIn(tester, title).single;
      expect(p.didExceedMaxLines, isFalse);
      expect(p.text.toPlainText(), contains('${DateTime.now().year}'));
      // Drawn whole inside its slot: the FittedBox shrinks, never clips.
      final box = tester.renderObject<RenderBox>(title);
      expect(
        tester
            .getRect(
              find.descendant(of: title, matching: find.byType(RichText)),
            )
            .width,
        lessThanOrEqualTo(box.size.width + 0.5),
      );
    });

    testWidgets('$scale×: the new-task sheet names itself whole and its '
        'title label is not clipped', (tester) async {
      _surface(tester, scale);
      await tester.pumpWidget(await signedInStoreApp(seededStoreApi()));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      // ignore: unawaited_futures
      showTaskCreateSheet(context);
      await tester.pumpAndSettle();

      final heading = _paragraphsIn(
        tester,
        find.byKey(const Key('task-sheet-heading')),
      ).single;
      expect(heading.didExceedMaxLines, isFalse);
      expect(_midWordBreaks(heading), isEmpty);

      final form = tester.getRect(find.byKey(const Key('task-sheet-form')));
      final label = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('task-sheet-title')),
          matching: find.text('Başlık'),
        ),
      );
      expect(label.top, greaterThanOrEqualTo(form.top));
      expect(tester.takeException(), isNull);
    });
  }
}
