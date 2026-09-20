/// Asset → printable QR label sheet (EE-194).
///
/// Split from the UI exactly as the note exporter is: this file turns assets
/// into PDF bytes and touches no platform channel, so the layout is testable
/// in a plain `flutter test` with no plugin and no widget tester.
///
/// ── ZERO NEW DEPENDENCIES, AND THAT WAS MEASURED ───────────────────────
///
/// `pdf` and `printing` already ship for the note export, and `barcode` is
/// already in the lock file as a transitive dependency of `pdf` — which is
/// what `pw.BarcodeWidget` draws with. A QR package was not added because
/// nothing was missing.
///
/// ── WHAT THE CODE CARRIES, AND WHY NOT A URL ───────────────────────────
///
/// `alliswell://asset/{id}` — the app's own scheme, registered with both
/// operating systems since OPH-189. Not an https link: a phone with the app
/// installed opens the card directly, and one without it does nothing at all
/// rather than landing on a page that asks somebody in a machine hall to log
/// in. The id rather than the tag, because a tag can be re-stickered and the
/// sticker being scanned is the old one.
///
/// ── AND THE TAG IS PRINTED IN TEXT BESIDE IT ───────────────────────────
///
/// A QR code that will not scan — wet, scratched, oily, which is what happens
/// to a label on a lathe — still has to identify the machine to a person.
/// That is the whole reason the number is painted on equipment in the first
/// place, and a label that only carries a barcode throws it away.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The faces the sheet draws with. Passed in rather than loaded here so the
/// layout can be built in a test with no asset bundle — the note exporter's
/// arrangement, for the note exporter's reason.
class AssetLabelFonts {
  const AssetLabelFonts({required this.regular, required this.bold});
  final pw.Font regular;
  final pw.Font bold;
}

/// One label, as the sheet needs it. A model of its own rather than `EeAsset`
/// so this file stays free of the API layer and its json.
class AssetLabel {
  const AssetLabel({
    required this.id,
    required this.tag,
    required this.name,
    this.location,
  });

  final String id;
  final String tag;
  final String name;
  final String? location;

  /// What the QR carries. See the header: the app's scheme, and the id.
  String get deepLink => 'alliswell://asset/$id';
}

/// Two columns by five rows on A4 — a common self-adhesive label pitch, and
/// big enough that a phone reads the code from arm's length on a machine.
const int kLabelsPerRow = 2;
const int kLabelRows = 5;

/// Builds the sheet. `title` is the caller's, already translated: this file
/// does no i18n, because a PDF builder that reaches for a locale is a PDF
/// builder that cannot be unit-tested.
Future<Uint8List> buildAssetLabelSheet({
  required List<AssetLabel> labels,
  required AssetLabelFonts fonts,
  String? title,
}) async {
  final doc = pw.Document();
  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
  const perPage = kLabelsPerRow * kLabelRows;

  for (var start = 0; start < labels.length; start += perPage) {
    final page = labels.sublist(
      start,
      start + perPage > labels.length ? labels.length : start + perPage,
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              pw.Text(
                title,
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 8),
            ],
            pw.Expanded(
              child: pw.GridView(
                crossAxisCount: kLabelsPerRow,
                childAspectRatio: 2.1,
                children: page.map((label) => _label(label, fonts)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  return doc.save();
}

pw.Widget _label(AssetLabel label, AssetLabelFonts fonts) => pw.Container(
  margin: const pw.EdgeInsets.all(4),
  padding: const pw.EdgeInsets.all(6),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
    borderRadius: pw.BorderRadius.circular(4),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: label.deepLink,
        width: 64,
        height: 64,
        drawText: false,
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            // The tag, large. A code that will not scan still has to name the
            // machine to a person.
            pw.Text(
              label.tag,
              style: pw.TextStyle(font: fonts.bold, fontSize: 14),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label.name,
              style: pw.TextStyle(font: fonts.regular, fontSize: 9),
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
            ),
            if (label.location != null && label.location!.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                label.location!,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ],
          ],
        ),
      ),
    ],
  ),
);
