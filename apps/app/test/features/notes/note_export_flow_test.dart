import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/notes/data/note_blocks.dart';
import 'package:alliswell/src/features/notes/data/note_pdf.dart';
import 'package:alliswell/src/features/notes/ui/note_figure_raster.dart';
import 'package:alliswell/src/features/notes/ui/note_export.dart';
import 'package:pdf/widgets.dart' as pw;

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// Records what the export handed to the OS instead of opening a share sheet.
class _RecordingSink implements NotePdfSink {
  final shared = <String>[];
  final printed = <String>[];
  final saved = <String>[];
  Uint8List? lastBytes;

  /// `null` mimics the user backing out of the save dialog.
  String? savePath = '/tmp/note.pdf';

  @override
  Future<void> share(Uint8List bytes, String filename) async {
    lastBytes = bytes;
    shared.add(filename);
  }

  @override
  Future<void> print(Uint8List bytes, String name) async {
    lastBytes = bytes;
    printed.add(name);
  }

  @override
  Future<String?> saveToFiles(Uint8List bytes, String filename) async {
    lastBytes = bytes;
    saved.add(filename);
    return savePath;
  }
}

/// Round 19 #1: stands in for the off-screen drawing pass.
///
/// The real one needs two real frames and a live overlay; what this test is
/// about is the WIRING — that the figures the walker found reach the layout
/// engine as bytes under their raster keys.
class _FakeRasterizer implements NoteFigureRasterizer {
  final asked = <String>[];

  @override
  Future<Map<String, Uint8List>> rasterize(
    BuildContext context,
    List<NoteBlock> blocks,
  ) async {
    final out = <String, Uint8List>{};
    for (final block in blocks) {
      if (block.kind != NoteBlockKind.figure || block.source == null) continue;
      asked.add(block.source!);
      out[block.source!] = _onePixelPng;
    }
    return out;
  }
}

/// A 1x1 opaque PNG — enough for `pw.MemoryImage` to decode.
final Uint8List _onePixelPng = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  252,
  207,
  192,
  80,
  15,
  0,
  4,
  133,
  1,
  128,
  132,
  169,
  140,
  33,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

/// The real faces, read the way the app reads them.
///
/// Through `rootBundle`, NOT `dart:io`: inside `testWidgets` the clock is fake,
/// and a real filesystem read would never complete while the test pumps frames.
Future<NotePdfFonts> _realFonts() async {
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return NotePdfFonts(
    regular: await load('Roboto-Regular'),
    bold: await load('Roboto-Bold'),
    italic: await load('Roboto-Italic'),
    boldItalic: await load('Roboto-BoldItalic'),
    symbols: await load('DejaVuSans'),
  );
}

Future<Widget> _app(
  FakeApi api,
  _RecordingSink sink, {
  Duration fontDelay = Duration.zero,
  NoteFigureRasterizer? rasterizer,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
      notePdfSinkProvider.overrideWithValue(sink),
      if (rasterizer != null)
        noteFigureRasterizerProvider.overrideWithValue(rasterizer),
      // In a test the whole export resolves in microtasks, so the progress
      // dialog would be pushed and popped without ever being built. Slowing
      // ONE await puts the timing under the test's control instead of leaving
      // the assertion to luck.
      if (fontDelay > Duration.zero)
        notePdfFontsProvider.overrideWith((ref) async {
          await Future<void>.delayed(fontDelay);
          return _realFonts();
        }),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> _openTheNote(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Notes').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Taps through the overflow menu and pumps frames until the export finishes,
/// reporting whether the progress dialog was on screen at any point.
///
/// Not `pumpAndSettle` while it runs: the dialog holds a `CircularProgress`
/// indicator, which never settles — and not a single `pump` either, because the
/// popup route has to pop before the dialog route can push.
Future<bool> _chooseExport(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('note-quick-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('note-export-pdf')));

  var sawProgress = false;
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byKey(const Key('note-export-progress')).evaluate().isNotEmpty) {
      sawProgress = true;
    }
    if (find.byKey(const Key('note-export-print')).evaluate().isNotEmpty) break;
  }
  await tester.pumpAndSettle();
  return sawProgress;
}

void main() {
  testWidgets('export shows progress, then offers share / save / print', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(
        title: 'Yayla planı',
        contentDelta: [
          {'insert': 'Başlık'},
          {
            'insert': '\n',
            'attributes': {'header': 1},
          },
          {'insert': 'Gövde metni ığüşöç\n'},
        ],
      );
    final sink = _RecordingSink();

    await tester.pumpWidget(
      await _app(api, sink, fontDelay: const Duration(milliseconds: 300)),
    );
    await _openTheNote(tester, 'Yayla planı');
    final sawProgress = await _chooseExport(tester);

    // The user is told the app is working — the whole point of the dialog.
    expect(sawProgress, isTrue);

    // Progress gone, the ways out offered.
    expect(find.byKey(const Key('note-export-progress')), findsNothing);
    expect(find.byKey(const Key('note-export-share')), findsOneWidget);
    expect(find.byKey(const Key('note-export-save')), findsOneWidget);
    expect(find.byKey(const Key('note-export-print')), findsOneWidget);

    await tester.tap(find.byKey(const Key('note-export-share')));
    await tester.pumpAndSettle();

    expect(sink.shared, ['Yayla planı.pdf']);
    // Real bytes, not a stub.
    expect(String.fromCharCodes(sink.lastBytes!.take(5)), '%PDF-');
    // The sheet closes once the file is on its way.
    expect(find.byKey(const Key('note-export-share')), findsNothing);
  });

  testWidgets('save routes to the file picker and reports back', (
    tester,
  ) async {
    final api = FakeApi()..seedNote(title: 'Kayıt', plainText: 'gövde');
    final sink = _RecordingSink();

    await tester.pumpWidget(await _app(api, sink));
    await _openTheNote(tester, 'Kayıt');
    await _chooseExport(tester);

    await tester.tap(find.byKey(const Key('note-export-save')));
    await tester.pumpAndSettle();

    expect(sink.saved, ['Kayıt.pdf']);
    expect(sink.shared, isEmpty);
  });

  testWidgets('backing out of the save dialog leaves the sheet open', (
    tester,
  ) async {
    final api = FakeApi()..seedNote(title: 'Vazgeç', plainText: 'gövde');
    final sink = _RecordingSink()..savePath = null; // user cancelled

    await tester.pumpWidget(await _app(api, sink));
    await _openTheNote(tester, 'Vazgeç');
    await _chooseExport(tester);

    await tester.tap(find.byKey(const Key('note-export-save')));
    await tester.pumpAndSettle();

    // Nothing was saved and the user is still where they can try again —
    // silently closing would have looked like success.
    expect(find.byKey(const Key('note-export-save')), findsOneWidget);
  });

  test('the file name is derived from the title and stays filesystem-safe', () {
    expect(pdfFileName('Yayla planı'), 'Yayla planı.pdf');
    expect(pdfFileName('a/b:c*d?e"f<g>h|i'), 'a b c d e f g h i.pdf');
    expect(pdfFileName('   '), 'note.pdf');
    expect(pdfFileName('satır\nkırma'), 'satır kırma.pdf');
    expect(pdfFileName('x' * 200).length, 84); // 80 + '.pdf'
  });

  // Round 19 #1: "the MD file has to export the way it LOOKS."
  testWidgets('a diagram reaches the page as a picture, not as source', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(
        title: 'Akış',
        contentMarkdown:
            'öncesi\n\n```mermaid\ngraph TD\nA-->B\n```\n\nsonrası',
      );
    final sink = _RecordingSink();
    final rasterizer = _FakeRasterizer();

    await tester.pumpWidget(await _app(api, sink, rasterizer: rasterizer));
    await _openTheNote(tester, 'Akış');
    await _chooseExport(tester);

    // The walker found the diagram and the exporter asked for its picture.
    expect(rasterizer.asked, ['aw-figure:mermaid:0']);

    await tester.tap(find.byKey(const Key('note-export-share')));
    await tester.pumpAndSettle();
    expect(String.fromCharCodes(sink.lastBytes!.take(5)), '%PDF-');
  });
}
