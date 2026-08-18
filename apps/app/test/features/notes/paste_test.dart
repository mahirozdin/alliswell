import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_forge/markdown_forge.dart';

import 'package:alliswell/src/theme/theme.dart';

/// OPH-274 — D20's other half: pasting HTML and images.
///
/// The measurement this feature exists for: `Clipboard.getData('text/html')`
/// returns null on EVERY platform, because Flutter's clipboard channel
/// implements `text/plain` and nothing else. So the HTML branch of smart paste
/// had shipped, looked like a feature, and had never executed — `htmlToMarkdown`
/// was reachable only from its own unit test. These tests drive the paste
/// through the SEAM, which is the thing that made both flavours reachable.
void main() {
  late MdSourceController controller;
  late List<String> uploaded;

  setUp(() {
    controller = MdSourceController(text: '');
    uploaded = [];
  });
  tearDown(() => controller.dispose());

  Widget host({
    required MarkdownPaste paste,
    MarkdownImagePasteHandler? onPasteImage,
  }) => MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: MarkdownForge(
      clipboardReader: () async => paste,
      child: Scaffold(
        body: SourceMode(controller: controller, onPasteImage: onPasteImage),
      ),
    ),
  );

  /// The paste keystroke the editor listens for (⌘V / Ctrl+V).
  Future<void> pressPaste(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('note-source-field')));
    await tester.pump();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  group('HTML pastes as markdown — the branch that never ran', () {
    testWidgets('bold and a link survive as markdown, not as tags', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          paste: const MarkdownPaste(
            html:
                '<p>Bir <b>kalın</b> ve <a href="https://ornek.test">bağ</a></p>',
            text: 'Bir kalın ve bağ',
          ),
        ),
      );
      await pressPaste(tester);

      expect(controller.text, contains('**kalın**'));
      expect(controller.text, contains('[bağ](https://ornek.test)'));
      expect(controller.text, isNot(contains('<b>')));
    });

    testWidgets('plain text is used when there is no HTML flavour', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(paste: const MarkdownPaste(text: 'düz metin')),
      );
      await pressPaste(tester);

      expect(controller.text, 'düz metin');
    });
  });

  group('an image pastes as an embed', () {
    testWidgets('the host uploads it and the markdown lands at the caret', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          paste: MarkdownPaste(
            imageBytes: Uint8List.fromList([1, 2, 3]),
            imageName: 'pano-2026.png',
            text: 'yok sayılmalı',
          ),
          onPasteImage: (bytes, name) async {
            uploaded.add('${name!}:${bytes.length}');
            return '![$name](alliswell://file/F1)';
          },
        ),
      );
      await pressPaste(tester);

      expect(uploaded, ['pano-2026.png:3']);
      expect(controller.text, '![pano-2026.png](alliswell://file/F1)');
      // The image WON over the text flavour that came with it — a screenshot
      // copied from a browser carries both, and the picture is what was meant.
      expect(controller.text, isNot(contains('yok sayılmalı')));
    });

    testWidgets('a failed upload falls back to the text, never to nothing', (
      tester,
    ) async {
      // The upload strip already shows the failure (F2). Pasting NOTHING here
      // would read as "the paste key is broken".
      await tester.pumpWidget(
        host(
          paste: MarkdownPaste(
            imageBytes: Uint8List.fromList([9]),
            imageName: 'a.png',
            text: 'yedek metin',
          ),
          onPasteImage: (_, _) async => null,
        ),
      );
      await pressPaste(tester);

      expect(controller.text, 'yedek metin');
    });

    testWidgets('without a handler an image is not pasteable, and says so by '
        'pasting the text instead', (tester) async {
      await tester.pumpWidget(
        host(
          paste: MarkdownPaste(
            imageBytes: Uint8List.fromList([9]),
            text: 'sadece metin',
          ),
        ),
      );
      await pressPaste(tester);

      expect(controller.text, 'sadece metin');
    });
  });

  group('one paste is one undo (D20)', () {
    testWidgets('the whole new text is assigned once', (tester) async {
      controller.text = 'önce ';
      await tester.pumpWidget(
        host(
          paste: MarkdownPaste(
            imageBytes: Uint8List.fromList([1]),
            imageName: 'x.png',
          ),
          onPasteImage: (_, name) async => '![$name](alliswell://file/F2)',
        ),
      );
      await pressPaste(tester);

      // Both the upload's markdown and the surrounding text arrive in ONE
      // controller assignment — an insert of the host's own would make the
      // image and the text two separate undo steps.
      expect(controller.text, 'önce ![x.png](alliswell://file/F2)');
    });

    testWidgets('an empty clipboard changes nothing', (tester) async {
      controller.text = 'dokunulmamalı';
      await tester.pumpWidget(host(paste: const MarkdownPaste()));
      await pressPaste(tester);

      expect(controller.text, 'dokunulmamalı');
    });
  });

  group('the default reader is honest about what Flutter can do', () {
    testWidgets('it returns plain text only — no html, no image', (
      tester,
    ) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': 'panodan'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final paste = await defaultClipboardReader();

      expect(paste.text, 'panodan');
      expect(
        paste.html,
        isNull,
        reason:
            'Flutter has no html flavour — pretending otherwise is what '
            'made the old branch dead code',
      );
      expect(paste.imageBytes, isNull);
    });
  });
}
