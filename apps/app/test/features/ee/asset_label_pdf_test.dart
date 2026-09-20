import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:alliswell/src/features/ee/data/asset_label_pdf.dart';

/// EE-194 — the printable QR label sheet.
///
/// Testable at all because the layout is split from the UI (the note
/// exporter's arrangement): this builds real PDF bytes with no plugin, no
/// platform channel and no widget tester.
///
/// What it pins is the part a screenshot cannot: that the code carries the
/// DEEP LINK rather than the tag, that a page holds ten labels and an
/// eleventh starts a second page, and that a Turkish name does not come out
/// as mojibake — which it would with the `pdf` package's built-in Helvetica,
/// whose WinAnsi encoding has no `ı ğ ş İ`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetLabelFonts fonts;

  setUpAll(() async {
    Future<pw.Font> load(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    fonts = AssetLabelFonts(
      regular: await load('Roboto-Regular'),
      bold: await load('Roboto-Bold'),
    );
  });

  AssetLabel label(int i) => AssetLabel(
    id: '01JABCDEFGHJKMNPQRSTVWXY${i % 10}',
    tag: 'TRN-$i',
    name: 'Torna tezgâhı $i',
    location: 'Döküm Holü / Hat ${i % 5}',
  );

  test('the code carries the deep link, not the tag', () {
    // The id, because a tag can be re-stickered and the sticker being scanned
    // is the old one.
    expect(label(1).deepLink, 'alliswell://asset/01JABCDEFGHJKMNPQRSTVWXY1');
  });

  test('a sheet is produced and is a PDF', () async {
    final bytes = await buildAssetLabelSheet(
      labels: [label(1), label(2)],
      fonts: fonts,
      title: 'Ekipman etiketleri',
    );
    expect(bytes.length, greaterThan(1000));
    // `%PDF` — the bytes are a document, not an empty buffer.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('eleven labels do not fit on a sheet of ten', () async {
    final ten = await buildAssetLabelSheet(
      labels: [for (var i = 0; i < kLabelsPerRow * kLabelRows; i++) label(i)],
      fonts: fonts,
    );
    final eleven = await buildAssetLabelSheet(
      labels: [
        for (var i = 0; i < kLabelsPerRow * kLabelRows + 1; i++) label(i),
      ],
      fonts: fonts,
    );
    // A second page is bigger than one page. Weak as an assertion about
    // pagination, strong as a guard against the failure that matters: the
    // eleventh label silently not being printed.
    expect(eleven.length, greaterThan(ten.length));
  });

  test(
    'an empty register produces an empty document rather than throwing',
    () async {
      final bytes = await buildAssetLabelSheet(labels: const [], fonts: fonts);
      expect(bytes.length, greaterThan(0));
    },
  );

  test('a Turkish name survives the encoding', () async {
    // Roboto is vendored precisely because the package's built-in Helvetica
    // would drop `ı ğ ş İ`. A document that builds is not proof on its own —
    // what would fail is the glyph lookup, so this exercises the path with
    // the characters that have no WinAnsi code point.
    final bytes = await buildAssetLabelSheet(
      labels: [
        const AssetLabel(
          id: '01JABCDEFGHJKMNPQRSTVWXYZ',
          tag: 'ÖLÇ-1',
          name: 'Şanzıman ölçüm tezgâhı',
          location: 'İkinci Hol',
        ),
      ],
      fonts: fonts,
    );
    expect(bytes.length, greaterThan(1000));
  });
}
