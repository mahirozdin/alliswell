import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:alliswell/src/features/notes/data/note_blocks.dart';
import 'package:alliswell/src/features/notes/data/note_pdf.dart';

/// Round 16 #3. `buildNotePdf` touches no platform channel, so the real
/// document — real fonts, real layout — is produced right here.
Future<NotePdfFonts> _fonts() async {
  Future<pw.Font> load(String name) async => pw.Font.ttf(
    ByteData.sublistView(await File('assets/fonts/$name.ttf').readAsBytes()),
  );
  return NotePdfFonts(
    regular: await load('Roboto-Regular'),
    bold: await load('Roboto-Bold'),
    italic: await load('Roboto-Italic'),
    boldItalic: await load('Roboto-BoldItalic'),
  );
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

  test('an empty note still produces a valid one-page document', () async {
    final bytes = await buildNotePdf(
      NotePdfDocument(title: 'Boş not', blocks: const []),
      await _fonts(),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
