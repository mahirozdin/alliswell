import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/markdown/markdown_forge_adapters.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:markdown_forge/markdown_forge.dart';

/// Issue #43: text in a note's Reading mode could not be selected or copied.
///
/// markdown_forge 0.1.1 puts the rendered document in one `SelectionArea`;
/// this pins it in AllisWell's own host (theme + strings), with a document
/// taller than the screen so a select-all must reach blocks never drawn.
void main() {
  String note() {
    final buffer = StringBuffer(
      '## Kopyalama\n\nİlk paragraf burada.\n\n- madde bir\n- madde iki\n\n'
      '| Ad | Değer |\n| --- | --- |\n| elma | 3 |\n\n',
    );
    for (var i = 1; i <= 30; i++) {
      buffer.writeln('### Bölüm $i\n\nUzun not paragrafı $i.\n');
    }
    buffer.writeln('Notun son satırı.');
    return buffer.toString();
  }

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: Builder(
        builder: (context) => MarkdownForge(
          theme: awMarkdownTheme(context),
          strings: awMarkdownStrings(),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );

  String? copied;

  setUp(() => copied = null);

  void mockClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Reading mode text is selectable and select-all copies the '
      'whole note (#43)', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockClipboard(tester);

    await tester.pumpWidget(host(ReadingMode(markdown: note())));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('note-reading')),
        matching: find.byType(SelectableRegion),
      ),
      findsWidgets,
    );
    // The last line is far below the 700 px screen.
    expect(find.text('Notun son satırı.'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.text('İlk paragraf burada.')) +
          const Offset(2, 2),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    await ctrl(tester, LogicalKeyboardKey.keyA);
    await ctrl(tester, LogicalKeyboardKey.keyC);

    expect(copied, isNotNull);
    expect(copied, contains('İlk paragraf burada.'));
    expect(copied, contains('madde bir\n'));
    expect(copied, contains('elma\t3'));
    expect(copied, contains('Uzun not paragrafı 30.'));
    expect(copied!.trimRight(), endsWith('Notun son satırı.'));
  });

  testWidgets('a mouse drag over one paragraph copies just that text (#43)', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockClipboard(tester);

    await tester.pumpWidget(host(ReadingMode(markdown: note())));
    await tester.pumpAndSettle();

    final text = find.text('İlk paragraf burada.');
    final gesture = await tester.startGesture(
      tester.getTopLeft(text) + const Offset(1, 4),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getBottomRight(text) - const Offset(1, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await ctrl(tester, LogicalKeyboardKey.keyC);

    expect(copied, 'İlk paragraf burada.');
  });
}
