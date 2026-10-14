// Note → Word (ADR-0048). `buildNoteDocx` is pure Dart, so the real file is
// produced here, unzipped, and every part parsed as XML — a part Word cannot
// parse is a file Word refuses to open.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

import 'package:alliswell/src/features/notes/data/markdown_blocks.dart';
import 'package:alliswell/src/features/notes/data/note_blocks.dart';
import 'package:alliswell/src/features/notes/data/note_docx.dart';
import 'package:alliswell/src/features/notes/data/note_print_style.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// A note that touches every block kind the exporter knows.
const richMarkdown = '''
---
tags: [plan, yayla]
---

# Başlık bir

Gövde **kalın**, *italik*, ~~çizik~~, `kod`, ==vurgu== ve [bağlantı](https://example.com/a?b=1&c=2).
Dipnot[^1] & <açılı> "tırnak" ığüşöçİ.

## Başlık iki

### Başlık üç

- madde bir
- madde iki
  - iç madde
    1. iç sıralı bir
    2. iç sıralı iki
- madde üç

1. birinci
2. ikinci

Arada paragraf.

1. yeniden bir
2. yeniden iki

- [ ] açık görev
- [x] bitmiş görev

> Bir alıntı satırı.

> [!WARNING]
> Dikkat edilecek şey.

```dart
void main() {
\tprint('merhaba');
}
```

---

| Ad | Değer |
| --- | --- |
| a | 1 |
| b | 2 |

![çizim](https://example.com/pic.png)

![kayıp](alliswell://file/01HZZZZZZZZZZZZZZZZZZZZZZZ)

```mermaid
graph TD
A-->B
```

```mermaid
graph TD
C-->D
```

[^1]: Dipnot metni.
''';

Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

List<NoteBlock> _blocks(String markdown) => markdownToBlocks(
  markdown,
  placeholderFor: (kind) => 'unsupported:$kind',
  alertLabelFor: (kind) => {'warning': 'Uyarı'}[kind] ?? kind,
);

/// The rich sample, with one fetched picture, one drawn figure, one figure
/// that failed to draw and one missing attachment.
Uint8List buildRichSample() => buildNoteDocx(
  NoteDocxDocument(
    title: 'Yayla planı & <notlar>',
    blocks: _blocks(richMarkdown),
    updatedLabel: 'Düzenlendi 15 Eki 2026',
    images: {
      'https://example.com/pic.png': _png(400, 200),
      noteFigureKey(NoteFigureKind.mermaid, 0): _png(300, 600),
    },
    mediaPlaceholderLabel: 'Medya kullanılamıyor',
  ),
  modified: DateTime.utc(2026, 10, 15),
);

class _Docx {
  _Docx(Uint8List bytes) : archive = ZipDecoder().decodeBytes(bytes);

  final Archive archive;

  List<String> get names => [for (final f in archive.files) f.name];

  Uint8List bytesOf(String name) => archive.findFile(name)!.readBytes()!;

  XmlDocument xml(String name) => XmlDocument.parse(utf8.decode(bytesOf(name)));
}

Iterable<XmlElement> _all(XmlNode node, String local, [String ns = _w]) => node
    .descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local && e.namespaceUri == ns);

String? _attr(XmlElement e, String local, [String ns = _w]) =>
    e.getAttribute(local, namespaceUri: ns);

/// The concatenated `w:t` text of a paragraph.
String _text(XmlElement p) => _all(p, 't').map((t) => t.innerText).join();

XmlElement _paragraphWith(XmlDocument doc, String needle) =>
    _all(doc, 'p').firstWhere((p) => _text(p).contains(needle));

void main() {
  late _Docx docx;
  late XmlDocument document;

  setUpAll(() {
    final bytes = buildRichSample();
    // Leaves a sample for a human (or LibreOffice) to open:
    // NOTE_DOCX_OUT=/tmp/sample.docx flutter test test/features/notes/note_docx_test.dart
    final out = Platform.environment['NOTE_DOCX_OUT'];
    if (out != null && out.isNotEmpty) File(out).writeAsBytesSync(bytes);
    docx = _Docx(bytes);
    document = docx.xml('word/document.xml');
  });

  test('the package has every part, typed and linked', () {
    expect(docx.names.first, '[Content_Types].xml');
    expect(
      docx.names,
      containsAll([
        '_rels/.rels',
        'docProps/core.xml',
        'docProps/app.xml',
        'word/document.xml',
        'word/styles.xml',
        'word/numbering.xml',
        'word/settings.xml',
        'word/fontTable.xml',
        'word/header1.xml',
        'word/header2.xml',
        'word/footer1.xml',
        'word/footer2.xml',
        'word/_rels/document.xml.rels',
      ]),
    );

    // Every XML part parses.
    for (final name in docx.names) {
      if (name.endsWith('.xml') || name.endsWith('.rels')) {
        expect(() => docx.xml(name), returnsNormally, reason: name);
      }
    }

    // Every non-default part has an Override; every media extension a Default.
    final types = docx.xml('[Content_Types].xml');
    final overrides = {
      for (final o in types.findAllElements('Override'))
        o.getAttribute('PartName'),
    };
    final defaults = {
      for (final d in types.findAllElements('Default'))
        d.getAttribute('Extension'),
    };
    for (final name in docx.names) {
      if (name.startsWith('word/media/')) {
        expect(defaults, contains(name.split('.').last), reason: name);
      } else if (name.endsWith('.xml') && name != '[Content_Types].xml') {
        expect(overrides, contains('/$name'), reason: name);
      }
    }

    // Every internal relationship points at a part that exists.
    final rels = docx.xml('word/_rels/document.xml.rels');
    final ids = <String>{};
    for (final rel in rels.findAllElements('Relationship')) {
      expect(ids.add(rel.getAttribute('Id')!), isTrue, reason: 'unique Id');
      if (rel.getAttribute('TargetMode') == 'External') continue;
      expect(
        docx.names,
        contains('word/${rel.getAttribute('Target')}'),
        reason: rel.getAttribute('Id'),
      );
    }

    // And every r:id the stories use is declared.
    for (final part in ['word/document.xml']) {
      for (final e in docx.xml(part).descendants.whereType<XmlElement>()) {
        for (final a in e.attributes) {
          if (a.name.namespaceUri == _r) {
            expect(ids, contains(a.value), reason: '${e.name} → ${a.value}');
          }
        }
      }
    }
  });

  test('A4 page, the PDF margins, a quiet first page header', () {
    final sect = _all(document, 'sectPr').single;
    final size = _all(sect, 'pgSz').single;
    expect(_attr(size, 'w'), '11906');
    expect(_attr(size, 'h'), '16838');
    final margin = _all(sect, 'pgMar').single;
    expect(_attr(margin, 'left'), '1247'); // 2.2 cm
    expect(_attr(margin, 'right'), '1247');
    expect(_attr(margin, 'top'), '1134'); // 2.0 cm
    expect(_attr(margin, 'bottom'), '1134');
    expect(_all(sect, 'titlePg'), hasLength(1));

    // Pages 2+ carry the title; every page is numbered "n / N".
    expect(
      docx.xml('word/header1.xml').innerText,
      contains('Yayla planı & <notlar>'),
    );
    expect(docx.xml('word/header2.xml').innerText.trim(), isEmpty);
    for (final footer in ['word/footer1.xml', 'word/footer2.xml']) {
      final instr = [
        for (final f in _all(docx.xml(footer), 'fldSimple'))
          _attr(f, 'instr')!.trim(),
      ];
      expect(instr.first, startsWith('PAGE'));
      expect(instr.last, startsWith('NUMPAGES'));
    }
  });

  test('title, edited line and the hairline under them', () {
    final title = _all(document, 'p').first;
    expect(_text(title), 'Yayla planı & <notlar>');
    expect(_attr(_all(title, 'pStyle').single, 'val'), 'Title');
    expect(_attr(_all(title, 'sz').first, 'val'), '48'); // 24 pt
    final label = _paragraphWith(document, 'Düzenlendi');
    final rule = _all(label, 'bottom').single;
    expect(_attr(rule, 'color'), NotePrintPalette.hex(NotePrintPalette.rule));

    // The escaped title survives in the metadata too.
    expect(
      docx.xml('docProps/core.xml').innerText,
      contains('Yayla planı & <notlar>'),
    );
  });

  test('headings carry the PDF sizes and are real Word headings', () {
    for (final (needle, style, size) in [
      ('Başlık bir', 'Heading1', '38'), // 19 pt
      ('Başlık iki', 'Heading2', '31'), // 15.5 pt
      ('Başlık üç', 'Heading3', '26'), // 13 pt
    ]) {
      final p = _paragraphWith(document, needle);
      expect(_attr(_all(p, 'pStyle').single, 'val'), style);
      expect(_attr(_all(p, 'sz').first, 'val'), size);
      expect(_all(p, 'b'), isNotEmpty);
    }
    final styles = docx.xml('word/styles.xml');
    final ids = [for (final s in _all(styles, 'style')) _attr(s, 'styleId')];
    expect(ids, containsAll(['Heading1', 'Heading2', 'Heading3', 'Title']));
  });

  test('inline formatting, escaping and Turkish text', () {
    final p = _paragraphWith(document, 'Gövde');
    final runs = _all(p, 'r').toList();
    XmlElement run(String text) =>
        runs.firstWhere((r) => _all(r, 't').any((t) => t.innerText == text));

    expect(_all(run('kalın'), 'b'), isNotEmpty);
    expect(_all(run('italik'), 'i'), isNotEmpty);
    expect(_all(run('çizik'), 'strike'), isNotEmpty);
    expect(
      _attr(_all(run('kod'), 'shd').single, 'fill'),
      NotePrintPalette.hex(NotePrintPalette.codeBg),
    );
    expect(
      _attr(_all(run('vurgu'), 'shd').single, 'fill'),
      NotePrintPalette.hex(NotePrintPalette.markBg),
    );

    expect(_text(p), contains('& <açılı> "tırnak" ığüşöçİ'));
    // The footnote reference is raised and NOT a dead hyperlink: the only
    // hyperlink in the paragraph is the real one.
    final sup = _all(p, 'vertAlign').single;
    expect(_attr(sup, 'val'), 'superscript');
    final links = _all(p, 'hyperlink').toList();
    expect(links, hasLength(1));
    expect(_all(links.single, 'vertAlign'), isEmpty);
  });

  test('a link is a real hyperlink with an external relationship', () {
    final link = _all(document, 'hyperlink').single;
    expect(link.innerText, 'bağlantı');
    final id = link.getAttribute('id', namespaceUri: _r)!;
    final rel = docx
        .xml('word/_rels/document.xml.rels')
        .findAllElements('Relationship')
        .firstWhere((r) => r.getAttribute('Id') == id);
    expect(rel.getAttribute('Target'), 'https://example.com/a?b=1&c=2');
    expect(rel.getAttribute('TargetMode'), 'External');
    expect(rel.getAttribute('Type'), endsWith('/hyperlink'));
    expect(
      _attr(_all(link, 'color').single, 'val'),
      NotePrintPalette.hex(NotePrintPalette.accent),
    );
    expect(_all(link, 'u'), isNotEmpty);
  });

  test('lists are Word lists; every ordered list counts from its own 1', () {
    int numId(String needle) => int.parse(
      _attr(_all(_paragraphWith(document, needle), 'numId').single, 'val')!,
    );
    int ilvl(String needle) => int.parse(
      _attr(_all(_paragraphWith(document, needle), 'ilvl').single, 'val')!,
    );

    // Bullets share one list; nesting is the level.
    expect(numId('madde bir'), numId('madde üç'));
    expect(ilvl('madde bir'), 0);
    expect(ilvl('iç madde'), 1);
    expect(ilvl('iç sıralı bir'), 2);

    // Three ordered runs, three separate lists.
    final nested = numId('iç sıralı bir');
    final first = numId('birinci');
    final second = numId('yeniden bir');
    expect(numId('iç sıralı iki'), nested);
    expect(numId('ikinci'), first);
    expect(numId('yeniden iki'), second);
    expect({nested, first, second, numId('madde bir')}, hasLength(4));

    // Each points at its own abstract definition, starting at 1, decimal,
    // indented 16 pt per level after an 18 pt marker column.
    final numbering = docx.xml('word/numbering.xml');
    final abstractOf = {
      for (final n in _all(numbering, 'num'))
        int.parse(_attr(n, 'numId')!): _attr(
          _all(n, 'abstractNumId').single,
          'val',
        ),
    };
    expect({
      abstractOf[nested],
      abstractOf[first],
      abstractOf[second],
    }, hasLength(3));
    final abstract = _all(
      numbering,
      'abstractNum',
    ).firstWhere((a) => _attr(a, 'abstractNumId') == abstractOf[first]);
    final level0 = _all(abstract, 'lvl').first;
    expect(_attr(_all(level0, 'start').single, 'val'), '1');
    expect(_attr(_all(level0, 'numFmt').single, 'val'), 'decimal');
    expect(_attr(_all(level0, 'ind').single, 'left'), '360');
    final level2 = _all(abstract, 'lvl').elementAt(2);
    expect(_attr(_all(level2, 'ind').single, 'left'), '1000'); // 18 + 2*16 pt
    final bullets = _all(numbering, 'abstractNum').first;
    expect(
      _attr(_all(_all(bullets, 'lvl').first, 'numFmt').single, 'val'),
      'bullet',
    );
  });

  test('checklist items carry the PDF box colours', () {
    final open = _paragraphWith(document, 'açık görev');
    final done = _paragraphWith(document, 'bitmiş görev');
    expect(_text(open), startsWith('☐'));
    expect(_text(done), startsWith('☑'));
    expect(
      _attr(_all(_all(done, 'r').first, 'color').single, 'val'),
      NotePrintPalette.hex(NotePrintPalette.success),
    );
    expect(
      _attr(_all(_all(open, 'r').first, 'color').single, 'val'),
      NotePrintPalette.hex(NotePrintPalette.muted),
    );
    // The text itself is untouched — no strike, as on screen.
    expect(_all(done, 'strike'), isEmpty);
  });

  test('quote, alert, code, front matter and rule', () {
    final quote = _paragraphWith(document, 'Bir alıntı');
    expect(_all(quote, 'i'), isNotEmpty);
    expect(
      _attr(_all(quote, 'left').single, 'color'),
      NotePrintPalette.hex(NotePrintPalette.rule),
    );

    final alert = _paragraphWith(document, 'Dikkat');
    expect(_text(alert), startsWith('Uyarı'));
    expect(
      _attr(_all(alert, 'left').single, 'color'),
      NotePrintPalette.hex(NotePrintPalette.warning),
    );
    expect(
      _attr(_all(alert, 'shd').first, 'fill'),
      NotePrintPalette.hex(NotePrintPalette.calloutTint('warning')),
    );

    // One shaded panel, lines kept as breaks and the tab as a tab.
    final code = _paragraphWith(document, 'void main');
    expect(
      _attr(_all(code, 'shd').first, 'fill'),
      NotePrintPalette.hex(NotePrintPalette.codeBg),
    );
    // Three lines; the fence's trailing newline is not a fourth (nor in the
    // PDF).
    expect(_all(code, 'br'), hasLength(2));
    expect(_all(code, 'tab'), hasLength(1));
    expect(_attr(_all(code, 'sz').first, 'val'), '19'); // 9.5 pt

    final front = _paragraphWith(document, 'tags:');
    expect(_attr(_all(front, 'sz').first, 'val'), '18');

    final rules = _all(document, 'p').where(
      (p) =>
          _all(p, 'bottom').any(
            (b) =>
                _attr(b, 'color') ==
                NotePrintPalette.hex(NotePrintPalette.tableRule),
          ) &&
          _text(p).isEmpty,
    );
    expect(rules, isNotEmpty);
  });

  test('a table with a repeating bold header row', () {
    final table = _all(document, 'tbl').single;
    final rows = _all(table, 'tr').toList();
    expect(rows, hasLength(3));
    expect(_all(rows.first, 'tblHeader'), hasLength(1));
    expect(_all(rows.first, 'b'), isNotEmpty);
    expect(_all(rows[1], 'b'), isEmpty);
    // Intrinsic-ish widths like `pw.Table`: the short column stays narrow.
    final grid = [
      for (final g in _all(table, 'gridCol')) int.parse(_attr(g, 'w')!),
    ];
    expect(grid, hasLength(2));
    expect(grid.first, lessThan(grid.last));
    expect(rows[1].innerText, contains('a'));
    expect(
      _attr(_all(table, 'insideH').single, 'color'),
      NotePrintPalette.hex(NotePrintPalette.tableRule),
    );
  });

  test('pictures are embedded inline, sized like the PDF', () {
    final drawings = _all(
      document,
      'inline',
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    ).toList();
    // The fetched picture and the one drawn mermaid; the second mermaid had
    // no raster and prints its source.
    expect(drawings, hasLength(2));

    const wp =
        'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
    final ids = [
      for (final d in drawings) _all(d, 'docPr', wp).single.getAttribute('id'),
    ];
    expect(ids.toSet(), hasLength(ids.length), reason: 'docPr ids are unique');

    (int, int) extent(XmlElement d) {
      final e = _all(d, 'extent', wp).single;
      return (
        int.parse(e.getAttribute('cx')!),
        int.parse(e.getAttribute('cy')!),
      );
    }

    // 400×200 into content width × 320 pt: width-bound, ratio kept.
    final (cx, cy) = extent(drawings.first);
    expect(cx, closeTo(NotePrintMetrics.contentWidth * 12700, 2));
    expect(cx / cy, closeTo(2, 0.001));
    // 300×600 into content width × 420 pt: height-bound.
    final (fx, fy) = extent(drawings.last);
    expect(fy, closeTo(420 * 12700, 2));
    expect(fy / fx, closeTo(2, 0.001));

    final media = docx.names.where((n) => n.startsWith('word/media/'));
    expect(media, hasLength(2));
    expect(media.every((n) => n.endsWith('.png')), isTrue);

    expect(_paragraphWith(document, 'C-->D'), isNotNull);
    expect(_paragraphWith(document, 'Medya kullanılamıyor'), isNotNull);
  });

  test(
    'a picture Word cannot show is re-encoded; garbage is a placeholder',
    () {
      final gif = Uint8List.fromList(
        img.encodeGif(img.Image(width: 3, height: 3)),
      );
      final bytes = buildNoteDocx(
        NoteDocxDocument(
          title: 't',
          blocks: const [
            NoteBlock(NoteBlockKind.image, source: 'gif'),
            NoteBlock(NoteBlockKind.image, source: 'junk'),
          ],
          images: {
            'gif': gif,
            'junk': Uint8List.fromList([1, 2, 3, 4]),
          },
          mediaPlaceholderLabel: 'yok',
        ),
      );
      final out = _Docx(bytes);
      final media = out.names
          .where((n) => n.startsWith('word/media/'))
          .toList();
      expect(media, ['word/media/image1.png']);
      expect(img.decodePng(out.bytesOf(media.single))!.width, 3);
      expect(out.xml('word/document.xml').innerText, contains('yok'));
    },
  );

  test('a JPEG goes in untouched with its own content type', () {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 4)),
    );
    final out = _Docx(
      buildNoteDocx(
        NoteDocxDocument(
          title: 't',
          blocks: const [NoteBlock(NoteBlockKind.image, source: 'j')],
          images: {'j': jpeg},
        ),
      ),
    );
    expect(out.bytesOf('word/media/image1.jpeg'), jpeg);
    final cx = _all(
      out.xml('word/document.xml'),
      'extent',
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    ).single;
    expect(
      int.parse(cx.getAttribute('cx')!) / int.parse(cx.getAttribute('cy')!),
      closeTo(2, 0.001),
    );
  });

  test('control characters never reach the XML', () {
    final out = _Docx(
      buildNoteDocx(
        NoteDocxDocument(
          title: 'a\u0001b',
          blocks: const [
            NoteBlock(
              NoteBlockKind.paragraph,
              spans: [
                NoteSpan('x\u0008y'),
                NoteSpan('bad', link: 'not a uri'),
              ],
            ),
          ],
        ),
      ),
    );
    final text = out.xml('word/document.xml').innerText;
    expect(text, contains('ab'));
    expect(text, contains('xy'));
  });

  test('a CRLF code block breaks once per line, with no CR left', () {
    final out = _Docx(
      buildNoteDocx(
        NoteDocxDocument(
          title: 't',
          blocks: const [
            NoteBlock(NoteBlockKind.code, spans: [NoteSpan('a\r\nb\rc')]),
          ],
        ),
      ),
    );
    final raw = utf8.decode(out.bytesOf('word/document.xml'));
    expect(raw, isNot(contains('\r')));
    final code = _paragraphWith(out.xml('word/document.xml'), 'a');
    expect(_all(code, 'br'), hasLength(2));
    expect(_text(code), 'abc');
  });
}
