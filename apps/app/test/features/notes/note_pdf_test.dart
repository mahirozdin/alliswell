import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:alliswell/src/features/notes/data/note_blocks.dart';
import 'package:alliswell/src/features/notes/data/note_pdf.dart';

/// Round 16 #3. `buildNotePdf` touches no platform channel, so the real
/// document — real fonts, real layout — is produced right here.
/// A 1x1 opaque PNG — the smallest thing `pw.MemoryImage` will decode. The
/// figure tests care that the bytes reach the page, not what they look like.
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

Future<NotePdfFonts> _fonts() async {
  Future<pw.Font> load(String name) async => pw.Font.ttf(
    ByteData.sublistView(await File('assets/fonts/$name.ttf').readAsBytes()),
  );
  return NotePdfFonts(
    regular: await load('Roboto-Regular'),
    bold: await load('Roboto-Bold'),
    italic: await load('Roboto-Italic'),
    boldItalic: await load('Roboto-BoldItalic'),
    symbols: await load('DejaVuSans'),
  );
}

/// `pdf` reports a glyph it cannot draw by `print`ing inside an `assert`, so
/// capturing stdout is the only way to ASSERT coverage rather than eyeball a
/// page. Tests run in debug, so the assert is live.
Future<List<String>> _missingGlyphWarnings(
  Future<void> Function() build,
) async {
  final warnings = <String>[];
  await runZoned(
    build,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (line.contains('Unable to find a font to draw')) warnings.add(line);
      },
    ),
  );
  return warnings;
}

void main() {
  test('produces a real PDF with an EMBEDDED font', () async {
    final bytes = await buildNotePdf(
      NotePdfDocument(
        title: 'Yayla planı',
        updatedLabel: 'Edited 05.08.2026 14:00',
        blocks: deltaToBlocks([
          {'insert': 'Başlık'},
          {
            'insert': '\n',
            'attributes': {'header': 1},
          },
          {'insert': 'Gövde metni ile '},
          {
            'insert': 'kalın',
            'attributes': {'bold': true},
          },
          {'insert': '\n'},
        ]),
      ),
      await _fonts(),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));

    // THE regression this file exists for: the `pdf` package's built-in
    // Helvetica is WinAnsi-encoded and has no ı/ğ/ş/İ, so a note in Turkish
    // would export as mojibake. Seeing "Roboto" in the output proves a Unicode
    // TTF was actually embedded rather than silently falling back.
    final raw = String.fromCharCodes(bytes);
    expect(raw, contains('Roboto'));
  });

  test('every block kind renders without throwing, in Turkish', () async {
    final blocks = deltaToBlocks([
      {'insert': 'Başlık ığüşöç İĞÜŞÖÇ'},
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
      {'insert': 'İkinci'},
      {
        'insert': '\n',
        'attributes': {'header': 2},
      },
      {'insert': 'madde'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': 'sıralı'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
      {'insert': 'bitti'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': 'bitmedi'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {'insert': 'alıntı'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': 'kod();'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
      {
        'insert': 'tıklanır',
        'attributes': {'link': 'https://alliswell.space'},
      },
      {'insert': '\n'},
    ]);

    final bytes = await buildNotePdf(
      NotePdfDocument(title: 'Türkçe', blocks: blocks),
      await _fonts(),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // The link annotation has to reach the file, or "clickable" was a lie.
    expect(String.fromCharCodes(bytes), contains('alliswell.space'));
  });

  test(
    'an image whose bytes never arrived degrades to a placeholder',
    () async {
      final blocks = deltaToBlocks([
        {'insert': 'önce'},
        {
          'insert': {'image': 'alliswell://file/01HZY0000000000000000000AB'},
        },
        {'insert': '\n'},
      ]);

      // No `images` map at all — offline, or the fetch timed out.
      final bytes = await buildNotePdf(
        NotePdfDocument(title: 'Eksik medya', blocks: blocks),
        await _fonts(),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    },
  );

  test(
    'symbols people actually type keep their glyph (round 16 follow-up)',
    () async {
      // Roboto has NONE of these — its cmap is 896 code points. Before DejaVu was
      // wired in as the fallback, every one of them drew a hollow box.
      const symbols =
          '→ ← ↔ ⇒ ✓ ✗ ★ ☆ ▪ ▫ ☐ ☑ ✔ ✱ ♦ ♥ ± ≥ ≤ ≠ ∞ × ÷ ° € ₺ α β π Ω';
      late Uint8List bytes;

      final warnings = await _missingGlyphWarnings(() async {
        bytes = await buildNotePdf(
          NotePdfDocument(
            title: 'Semboller $symbols',
            blocks: deltaToBlocks([
              {'insert': 'Gövde: $symbols'},
              {'insert': '\n'},
              {'insert': 'Kalın: $symbols'},
              {
                'insert': '\n',
                'attributes': {'header': 1},
              },
              {'insert': 'Kod: $symbols'},
              {
                'insert': '\n',
                'attributes': {'code-block': true},
              },
              {'insert': 'Madde: $symbols'},
              {
                'insert': '\n',
                'attributes': {'list': 'bullet'},
              },
              {'insert': 'Alıntı: $symbols'},
              {
                'insert': '\n',
                'attributes': {'blockquote': true},
              },
            ]),
            updatedLabel: 'Düzenlendi $symbols',
          ),
          await _fonts(),
        );
      });

      expect(warnings, isEmpty, reason: warnings.join('\n'));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // The fallback has to be EMBEDDED too, not merely consulted.
      expect(String.fromCharCodes(bytes), contains('DejaVu'));
    },
  );

  test(
    'an emoji with no monochrome glyph anywhere still degrades quietly',
    () async {
      // The honest half of the story: a PDF cannot embed a COLOR emoji font, and
      // no monochrome face carries the modern pictographs. This pins the limit so
      // nobody re-opens it expecting a bug.
      final warnings = await _missingGlyphWarnings(() async {
        await buildNotePdf(
          NotePdfDocument(
            title: 'Parti',
            blocks: deltaToBlocks([
              {'insert': 'kutlama 🎉\n'},
            ]),
          ),
          await _fonts(),
        );
      });
      expect(warnings.length, 1);
      expect(warnings.single, contains('U+1f389'));
    },
  );

  test('an empty note still produces a valid one-page document', () async {
    final bytes = await buildNotePdf(
      NotePdfDocument(title: 'Boş not', blocks: const []),
      await _fonts(),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  // Round 19 #1 (ADR-0034): a figure is "a picture if we could make one, the
  // source if we could not". Both halves are pinned, because the fallback is
  // the half a reader only ever sees when something has already gone wrong.
  group('figures', () {
    test('a figure with bytes draws the picture', () async {
      final bytes = await buildNotePdf(
        NotePdfDocument(
          title: 'Diyagram',
          blocks: [
            NoteBlock(
              NoteBlockKind.figure,
              figureKind: NoteFigureKind.mermaid,
              source: noteFigureKey(NoteFigureKind.mermaid, 0),
              spans: const [NoteSpan('graph TD\nA-->B')],
            ),
          ],
          images: {noteFigureKey(NoteFigureKind.mermaid, 0): _onePixelPng},
        ),
        await _fonts(),
      );
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('a figure with no bytes prints its SOURCE, not an apology', () async {
      // "unsupported block" tells a reader nothing they can act on; the
      // diagram's own mermaid tells them everything.
      const source = 'graph TD\n  A[Başla] --> B[Bitir]';
      final doc = NotePdfDocument(
        title: 'Diyagram',
        blocks: const [
          NoteBlock(
            NoteBlockKind.figure,
            figureKind: NoteFigureKind.mermaid,
            source: 'aw-figure:mermaid:0',
            spans: [NoteSpan(source)],
          ),
        ],
        // Deliberately empty: this is the rasterizer-failed path.
      );
      final bytes = await buildNotePdf(doc, await _fonts());
      expect(bytes.length, greaterThan(1000));
      expect(doc.blocks.single.text, source);
    });
  });
}
